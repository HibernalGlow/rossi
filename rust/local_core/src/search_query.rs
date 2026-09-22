//! Vendored directly from `vendor/mimageviewer/src/search_query.rs` (MIT).
//!
//! The file manager's name filter calls this parser instead of maintaining a second
//! query grammar, so the token model stays diffable against upstream.
//!
//! 语法:
//! - 空格分隔 = 包含所有 token 的项匹配 (AND)
//! - 开头 `-` = 不包含该 token 的项匹配 (NOT)
//! - `"..."` = 用引号包裹时，连同其中的空格一起作为一个 token 处理
//! - `-"..."` = 也支持 NOT + 引号的组合
//! - 没有闭合引号时，直接取到末尾作为一个 token (宽松解析)
//!
//! token 会小写化后保存在 `needle` 中。匹配时把原始 hay 传给 `matches`，内部会自行小写化。
//!
//! ## 组合模式 (`MatchMode`)
//!
//! 通过搜索 UI 的「□OR」复选框切换 (docs/archive/search-metadata/search-expansion-design.md §20)。
//! - `MatchMode::And` (默认): 包含**所有** include token 的项匹配
//! - `MatchMode::Or`: 包含**至少 1 个** include token 的项匹配
//!
//! **NOT token 始终是 AND** (OR 模式下也一样)。
//! 例如: `klee #klee -sleep -nsfw` 在 OR 模式下求值时
//! 会被解释为 `(klee OR #klee) AND (NOT sleep) AND (NOT nsfw)`。

/// include token 群的组织方式。NOT token 始终为 AND，不依赖这个 enum。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum MatchMode {
    /// 默认。以 AND 组合 include token。
    #[default]
    And,
    /// 以 OR 组合 include token (NOT 保持 AND)。
    Or,
}

impl From<bool> for MatchMode {
    /// 把 UI 复选框的 `or_mode: bool` 转换为 `MatchMode`。`true` 时为 `Or`。
    fn from(or_mode: bool) -> Self {
        if or_mode {
            MatchMode::Or
        } else {
            MatchMode::And
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Token {
    /// true: 只保留包含该 token 的项。false: 排除包含它的项。
    pub include: bool,
    /// 小写化后的匹配目标字符串。为空的 token 会在 parse 中丢弃。
    pub needle: String,
    /// 为 true 时是「标签搜索 token」。以 `#标签名` 前缀输入时会被置位。
    /// needle 中包含 `#` (例如: "#原神")。
    /// 标签搜索 token 不是对 all_text_norm 做 substring 搜索，
    /// 而是对 fts_meta.db 的 tags 列 (空格分隔) 做**完全匹配**判定。
    pub is_tag: bool,
}

/// 把查询字符串分解为正负 token 序列。仅空白或单独的 `-` 会被忽略。
pub fn parse(query: &str) -> Vec<Token> {
    let chars: Vec<char> = query.chars().collect();
    let mut tokens = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        // 跳过开头的空白
        while i < chars.len() && chars[i].is_whitespace() {
            i += 1;
        }
        if i >= chars.len() {
            break;
        }

        // NOT 前缀 (仅当 `-X` 中 X 不是空白时)
        let mut include = true;
        if chars[i] == '-' {
            match chars.get(i + 1) {
                Some(&c) if !c.is_whitespace() => {
                    include = false;
                    i += 1;
                }
                _ => {
                    // 裸的 `-` 作为噪声跳过
                    i += 1;
                    continue;
                }
            }
        }

        let mut buf = String::new();
        if i < chars.len() && chars[i] == '"' {
            i += 1;
            while i < chars.len() && chars[i] != '"' {
                buf.push(chars[i]);
                i += 1;
            }
            if i < chars.len() {
                i += 1;
            }
        } else {
            while i < chars.len() && !chars[i].is_whitespace() {
                buf.push(chars[i]);
                i += 1;
            }
        }

        let raw = buf.trim();
        // `#标签名` 前缀判定: 以 `#` 开头，且 `#` 之后还有 1 个字符以上。
        // 单独的 `#` 和 `##...` 按普通关键词处理 (因为用户意图不明确)。
        let is_tag = raw.starts_with('#') && raw.chars().count() >= 2 && !raw.starts_with("##");
        let needle = raw.to_lowercase();
        if !needle.is_empty() && needle != "-" {
            tokens.push(Token {
                include,
                needle,
                is_tag,
            });
        }
    }
    tokens
}

/// 判定 `hay` 是否匹配 token 序列 (内部做小写化，默认 AND 模式)。
/// - include token: hay 中不包含则不匹配
/// - exclude token: hay 中包含则不匹配
/// - token 序列为空: 始终匹配 (视为无过滤器)
///
/// 带 `is_tag` 标记的 token 也按普通关键词处理，对 hay 做 substring 判定
/// (即去找 `#原神`)。tags 字段会被 bigram tokenize 并合并进 per-source
/// 文本，因此在 post-filter 中也能自然匹配。
pub fn matches(tokens: &[Token], hay: &str) -> bool {
    matches_with_mode(tokens, hay, MatchMode::And)
}

/// `matches` 的指定组合模式版 (docs §20)。
/// - `MatchMode::And`: include 必须全部包含
/// - `MatchMode::Or`: include 只要包含 1 个即可 (exclude 始终为 AND)
///
/// include 为 0 个 + 仅有 exclude + OR 模式时，只要「不包含 exclude」即视为匹配
/// (与 AND 模式行为一致，NOT-only 会被 UI 侧拒绝)。
pub fn matches_with_mode(tokens: &[Token], hay: &str, mode: MatchMode) -> bool {
    let hay_lower = hay.to_lowercase();
    matches_lowercased_with_mode(tokens, &hay_lower, mode)
}

/// 针对已小写化的 `hay_lower` 做匹配。
pub fn matches_lowercased_with_mode(tokens: &[Token], hay_lower: &str, mode: MatchMode) -> bool {
    if tokens.is_empty() {
        return true;
    }
    let mut any_include = false;
    let mut include_hit = false;
    for t in tokens {
        if t.include {
            any_include = true;
            let hit = hay_lower.contains(&t.needle);
            match mode {
                MatchMode::And => {
                    if !hit {
                        return false;
                    }
                }
                MatchMode::Or => {
                    if hit {
                        include_hit = true;
                    }
                }
            }
        } else if hay_lower.contains(&t.needle) {
            return false;
        }
    }
    match mode {
        MatchMode::And => true,
        // OR 模式: 若没有任何 include，则「无过滤器 + 已通过 exclude」 = true
        MatchMode::Or => !any_include || include_hit,
    }
}

/// `decide_partial` 的返回值。指示是否需要获取附加信息 (XMP 等)。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PartialResult {
    /// 仅凭当前 hay 结果已确定。无需读取附加信息。
    Decided(bool),
    /// `include` token 在 hay 中尚未发现，或 `exclude` token 在 hay 中
    /// 尚未发现 (= 可能混在附加信息里)，因此需要附加信息。
    NeedsMore,
}

/// 返回仅凭 hay_so_far 能否做出确定判定 (默认 AND 模式，向后兼容)。
pub fn decide_partial(tokens: &[Token], hay_so_far: &str) -> PartialResult {
    decide_partial_with_mode(tokens, hay_so_far, MatchMode::And)
}

/// 返回仅凭 hay_so_far 能否做出确定判定。用于 Ctrl+F 元数据搜索中的
/// 前置判定，以便「能避免高成本 XMP 读取时就避免」。
///
/// 返回值有以下 3 种:
/// - `Decided(false)`: exclude token **已包含在** hay_so_far 中。
///   无论附加信息如何都确定不匹配，无需读取 XMP (AND/OR 通用)。
/// - `Decided(true)`:
///   - AND: 全部 include 都在 hay_so_far 中，且不存在任何 exclude。
///   - OR: 至少有 1 个 include 在 hay_so_far 中，且不存在任何 exclude。
/// - `NeedsMore`: 结果可能被附加信息推翻。
///   - AND: 有 include 缺失，或存在尚未确认的 exclude。
///   - OR: 没有任何 include 命中 (附加信息中或许能找到)，或 exclude 未确认。
pub fn decide_partial_with_mode(
    tokens: &[Token],
    hay_so_far: &str,
    mode: MatchMode,
) -> PartialResult {
    if tokens.is_empty() {
        return PartialResult::Decided(true);
    }
    let hay_lower = hay_so_far.to_lowercase();
    let mut has_include = false;
    let mut any_include_missing = false;
    let mut include_hit = false;
    let mut has_exclude = false;
    for t in tokens {
        if t.include {
            has_include = true;
            if hay_lower.contains(&t.needle) {
                include_hit = true;
            } else {
                any_include_missing = true;
            }
        } else {
            has_exclude = true;
            if hay_lower.contains(&t.needle) {
                return PartialResult::Decided(false);
            }
        }
    }
    match mode {
        MatchMode::And => {
            if any_include_missing || has_exclude {
                PartialResult::NeedsMore
            } else {
                PartialResult::Decided(true)
            }
        }
        MatchMode::Or => {
            // OR: 只要找到 1 个 include，剩下的取决于 exclude。
            // 无 exclude 则 Decided(true)，有则需通过附加信息确认是否混入。
            if has_include && !include_hit {
                // 任何 include 都还没找到 → 可能包含在附加信息中。
                return PartialResult::NeedsMore;
            }
            if has_exclude {
                PartialResult::NeedsMore
            } else {
                PartialResult::Decided(true)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn inc(s: &str) -> Token {
        Token {
            include: true,
            needle: s.to_string(),
            is_tag: false,
        }
    }
    fn exc(s: &str) -> Token {
        Token {
            include: false,
            needle: s.to_string(),
            is_tag: false,
        }
    }
    fn tag(s: &str) -> Token {
        Token {
            include: true,
            needle: s.to_string(),
            is_tag: true,
        }
    }
    fn not_tag(s: &str) -> Token {
        Token {
            include: false,
            needle: s.to_string(),
            is_tag: true,
        }
    }

    #[test]
    fn parse_empty() {
        assert!(parse("").is_empty());
        assert!(parse("   ").is_empty());
    }

    #[test]
    fn parse_single() {
        assert_eq!(parse("hello"), vec![inc("hello")]);
    }

    #[test]
    fn parse_and_lowercases() {
        assert_eq!(parse("Hello WORLD"), vec![inc("hello"), inc("world")]);
    }

    #[test]
    fn parse_not() {
        assert_eq!(parse("foo -bar"), vec![inc("foo"), exc("bar")]);
    }

    #[test]
    fn parse_quoted_phrase() {
        assert_eq!(
            parse(r#"foo "hello world" bar"#),
            vec![inc("foo"), inc("hello world"), inc("bar")],
        );
    }

    #[test]
    fn parse_quoted_not() {
        assert_eq!(parse(r#"-"low quality""#), vec![exc("low quality")],);
    }

    #[test]
    fn parse_unterminated_quote() {
        // 无闭合引号时取到末尾作为一个 token
        assert_eq!(parse(r#""abc def"#), vec![inc("abc def")]);
    }

    #[test]
    fn parse_lone_dash_ignored() {
        // 裸的 `-` 不会成为 token
        assert_eq!(parse("foo - bar"), vec![inc("foo"), inc("bar")]);
    }

    #[test]
    fn parse_dash_inside_word_kept() {
        // 单词中的 `-` 不会成为 NOT (例如: "jean-claude")
        assert_eq!(parse("jean-claude"), vec![inc("jean-claude")]);
    }

    #[test]
    fn matches_and() {
        let t = parse("foo bar");
        assert!(matches(&t, "foo xxx bar"));
        assert!(matches(&t, "barfoo"));
        assert!(!matches(&t, "foo only"));
        assert!(!matches(&t, "bar only"));
    }

    #[test]
    fn matches_not() {
        let t = parse("foo -bar");
        assert!(matches(&t, "foo alone"));
        assert!(!matches(&t, "foo bar together"));
    }

    #[test]
    fn matches_not_only() {
        // NOT-only query: 不包含 bar 的全部匹配
        let t = parse("-bar");
        assert!(matches(&t, "anything"));
        assert!(!matches(&t, "has bar in it"));
    }

    #[test]
    fn matches_phrase() {
        let t = parse(r#""hello world""#);
        assert!(matches(&t, "say hello world to me"));
        assert!(!matches(&t, "hello and world are apart"));
    }

    #[test]
    fn matches_empty_tokens() {
        // 0 个 token 始终匹配
        assert!(matches(&[], "anything"));
    }

    // ---- decide_partial ----

    #[test]
    fn decide_partial_all_includes_no_excludes() {
        // 全部 include 都在 hay 中且无 exclude → Decided(true)
        let t = parse("foo bar");
        assert_eq!(
            decide_partial(&t, "foo and bar"),
            PartialResult::Decided(true)
        );
    }

    #[test]
    fn decide_partial_include_missing() {
        // hay 中缺少 include → 也许能由附加信息补上，因此 NeedsMore
        let t = parse("foo bar");
        assert_eq!(decide_partial(&t, "only foo"), PartialResult::NeedsMore);
    }

    #[test]
    fn decide_partial_exclude_hit() {
        // exclude 已存在于 hay 中即确定不匹配 → Decided(false)
        let t = parse("foo -bad");
        assert_eq!(
            decide_partial(&t, "foo has bad"),
            PartialResult::Decided(false)
        );
    }

    #[test]
    fn decide_partial_exclude_not_found_yet() {
        // 即使未发现 exclude，也需验证其是否在附加信息中 → NeedsMore
        let t = parse("foo -bad");
        assert_eq!(decide_partial(&t, "foo is clean"), PartialResult::NeedsMore);
    }

    #[test]
    fn decide_partial_exclude_only_missing_in_hay() {
        // 仅有 "-bad" 时，即使 hay 中没有 bad，也需要确认附加信息 → NeedsMore
        let t = parse("-bad");
        assert_eq!(decide_partial(&t, "anything"), PartialResult::NeedsMore);
    }

    #[test]
    fn decide_partial_empty_tokens() {
        // 0 个 token 始终 Decided(true) (无需读取附加信息)
        assert_eq!(
            decide_partial(&[], "anything"),
            PartialResult::Decided(true)
        );
    }

    #[test]
    fn decide_partial_exclude_hit_short_circuits_missing_include() {
        // 只要找到 exclude，即使其它 include 缺失也返回 Decided(false)
        // (无需读取附加信息)
        let t = parse("missing -bad");
        assert_eq!(
            decide_partial(&t, "text with bad here"),
            PartialResult::Decided(false),
        );
    }

    // ---- 标签语法 (docs/archive/search-metadata/tag-feature.md) ----

    #[test]
    fn parse_tag_prefix() {
        let tokens = parse("#原神");
        assert_eq!(tokens, vec![tag("#原神")]);
    }

    #[test]
    fn parse_tag_with_keyword() {
        let tokens = parse("#原神 写真");
        assert_eq!(tokens, vec![tag("#原神"), inc("写真")]);
    }

    #[test]
    fn parse_tag_exclude() {
        let tokens = parse("-#原神");
        assert_eq!(tokens, vec![not_tag("#原神")]);
    }

    #[test]
    fn parse_hash_alone_is_keyword() {
        // 单独的 `#` 按关键词处理 (不能作为前缀)
        let tokens = parse("#");
        assert_eq!(tokens, vec![inc("#")]);
    }

    #[test]
    fn parse_tag_flag_set() {
        // `#原神` 的 is_tag=true，needle 包含 `#`
        let tokens = parse("#原神");
        assert_eq!(tokens.len(), 1);
        assert!(tokens[0].is_tag);
        assert_eq!(tokens[0].needle, "#原神");
    }

    #[test]
    fn parse_double_hash_is_keyword() {
        // `##foo` 的 is_tag=false (用户意图不明确，按普通关键词处理)
        let tokens = parse("##foo");
        assert_eq!(tokens.len(), 1);
        assert!(!tokens[0].is_tag);
    }

    // ---- OR 模式 (docs §20) ----

    #[test]
    fn or_mode_matches_any_include() {
        // OR: 包含任一 include 即匹配
        let t = parse("klee #klee");
        assert!(matches_with_mode(&t, "this is klee art", MatchMode::Or));
        assert!(matches_with_mode(&t, "#klee is here", MatchMode::Or));
        assert!(!matches_with_mode(&t, "unrelated text", MatchMode::Or));
    }

    #[test]
    fn or_mode_with_excludes_still_and() {
        // OR: include 为 OR，但 exclude 为 AND (始终排除)
        let t = parse("klee #klee -sleep -nsfw");
        assert!(matches_with_mode(&t, "klee portrait", MatchMode::Or));
        assert!(!matches_with_mode(&t, "klee is sleep", MatchMode::Or));
        assert!(!matches_with_mode(&t, "#klee nsfw", MatchMode::Or));
    }

    #[test]
    fn or_mode_none_match_fails() {
        // OR: 一个 include 都不包含则不匹配
        let t = parse("foo bar");
        assert!(!matches_with_mode(
            &t,
            "neither token present",
            MatchMode::Or
        ));
    }

    #[test]
    fn or_mode_single_include_ok() {
        // 即使 OR 模式，include 只有 1 个时行为也与 AND 相同
        let t = parse("klee");
        assert!(matches_with_mode(&t, "this is klee", MatchMode::Or));
        assert!(!matches_with_mode(&t, "unrelated", MatchMode::Or));
    }

    #[test]
    fn or_mode_only_excludes_matches_any() {
        // OR 模式下 exclude only (前提是 UI 会拦掉 NOT-only) 与 AND 一样，
        // 匹配不包含 exclude 的项。
        let t = parse("-bad");
        assert!(matches_with_mode(&t, "anything", MatchMode::Or));
        assert!(!matches_with_mode(&t, "has bad", MatchMode::Or));
    }

    #[test]
    fn matches_default_is_and() {
        // 默认的简写 `matches` 为 AND 行为
        let t = parse("foo bar");
        assert!(matches(&t, "foo and bar"));
        assert!(!matches(&t, "only foo"));
    }

    #[test]
    fn lowercased_matcher_preserves_filename_query_rules() {
        assert!(matches_lowercased_with_mode(
            &parse(""),
            "anything.jpg",
            MatchMode::And
        ));
        assert!(matches_lowercased_with_mode(
            &parse("PHOTO"),
            "summer_photo.jpg",
            MatchMode::And
        ));
        assert!(matches_lowercased_with_mode(
            &parse("summer photo"),
            "summer_photo.jpg",
            MatchMode::And
        ));
        assert!(!matches_lowercased_with_mode(
            &parse("summer -draft"),
            "summer_draft.jpg",
            MatchMode::And
        ));
        assert!(matches_lowercased_with_mode(
            &parse("summer -draft"),
            "summer_final.jpg",
            MatchMode::And
        ));
    }

    #[test]
    fn decide_partial_or_mode_any_include_hit() {
        // OR: hay_so_far 中只要有 1 个 include 就 Decided(true) (无 exclude)
        let t = parse("foo bar");
        assert_eq!(
            decide_partial_with_mode(&t, "only foo here", MatchMode::Or),
            PartialResult::Decided(true)
        );
    }

    #[test]
    fn decide_partial_or_mode_no_include_yet() {
        // OR: 一个 include 都没找到 → 附加信息中或许能找到
        let t = parse("foo bar");
        assert_eq!(
            decide_partial_with_mode(&t, "unrelated", MatchMode::Or),
            PartialResult::NeedsMore
        );
    }

    #[test]
    fn decide_partial_or_mode_exclude_hit_short_circuit() {
        // 即使 OR 模式，exclude 在 hay 中则 Decided(false)
        let t = parse("foo bar -bad");
        assert_eq!(
            decide_partial_with_mode(&t, "foo here but bad", MatchMode::Or),
            PartialResult::Decided(false)
        );
    }

    #[test]
    fn decide_partial_or_mode_include_hit_but_exclude_unchecked() {
        // OR: 已找到 include，exclude 不在 hay 中 → 需确认附加信息中有没有 exclude
        let t = parse("foo -bad");
        assert_eq!(
            decide_partial_with_mode(&t, "foo is here", MatchMode::Or),
            PartialResult::NeedsMore
        );
    }
}
