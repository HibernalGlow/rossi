//! 出厂预设（neoview `DEFAULT_READER_INPUT_BINDINGS` 的结构 + Rossi 现状的行为）。
//!
//! 设计立场：**预设是「数据」，不是「代码里的 if」**。九宫格与键盘的默认值在这里
//! 列成一张绑定表，运行时（Dart 侧）只问解析器「这个输入是什么动作」，从不自己
//! 猜方向 —— 左开下点右边为什么是上一页，答案在 [`crate::operation_binding::resolve::resolve_page_turn`]
//! 里，不在这里。
//!
//! ## 「左右手模式」与「阅读方向」为什么是两件事
//!
//! - **阅读方向**决定「下一页在画面的哪一边」：右开在右、左开在左。
//! - **手持手式**（这个预设）决定「把前进动作绑在拇指常驻的那一侧」：
//!   右手持机拇指在右，左手持机拇指在左。
//! - 两者正交：左开 + 右手 ⇄ 前进侧在左（翻漫画的常见姿势），由
//!   `page-left`（空间动作）× `RightToLeft` 解析出来，不需要任何特判。

use super::model::{InputBinding, InputDescriptor, KeyTrigger, PointerAction};
use super::vocabulary::{InputContext, ReaderViewArea, action};

/// 点击分区的出厂预设。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TapPreset {
    /// 右手：右侧是**前进热区**（绑 `page-right`），左侧退回，正中唤出上下栏。
    RightHand,
    /// 左手：镜像 —— 左侧是前进热区（绑 `page-right`），右侧退回。
    LeftHand,
}

impl TapPreset {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::RightHand => "right-hand",
            Self::LeftHand => "left-hand",
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        match raw {
            "right-hand" => Some(Self::RightHand),
            "left-hand" => Some(Self::LeftHand),
            _ => None,
        }
    }

    /// 「下一页」所在的那一格（空间动作绑定在哪边）。
    ///
    /// 两个预设绑的都是 `page-right`，差别只在格子：右手把它放右格、左手放左格。
    /// 阅读方向在解析时把 `page-right` 变成前进或退回 —— 方向换挡不需要重写绑定表。
    const fn advance_area(self) -> ReaderViewArea {
        match self {
            Self::RightHand => ReaderViewArea::MiddleRight,
            Self::LeftHand => ReaderViewArea::MiddleLeft,
        }
    }

    /// 「上一页」所在的那一格：永远在前进热区的**对侧中格**。
    const fn retreat_area(self) -> ReaderViewArea {
        match self {
            Self::RightHand => ReaderViewArea::MiddleLeft,
            Self::LeftHand => ReaderViewArea::MiddleRight,
        }
    }
}

/// 键盘的出厂预设：**左右方向键绑空间动作**（`page-left` / `page-right`），
/// 空格 / `PageDown` / `PageUp` 绑语义动作（「下一页」与方向无关）。
///
/// 旧实现的 bug 正在这里：`key.dart` 把 ArrowRight 写死成 `next`，左开下
/// 按右键是「下一页」而不是「往右翻」—— 换成空间动作后方向自动生效。
///
/// ## 为什么这一张表要**盖全**改造前 `key.dart` 认的那些键
///
/// 绑定表一旦接管运行时就是**唯一**的判定处（回退到 Dart 里那份硬编码名单，等于
/// 「删掉一条绑定它还在生效」，判据 E2「改绑定不重新编译即生效」当场作废）。
/// 所以小键盘 2/4/6/8、WASD、上下方向键、F11 都得在这里，一条都不能少。
pub const DEFAULT_KEY_BINDINGS: [(&str, &str); 20] = [
    // 空间族：左右两个方向（含小键盘与 WASD 的左右）。
    ("ArrowRight", action::PAGE_RIGHT),
    ("ArrowLeft", action::PAGE_LEFT),
    ("KeyD", action::PAGE_RIGHT),
    ("KeyA", action::PAGE_LEFT),
    ("Numpad6", action::PAGE_RIGHT),
    ("Numpad4", action::PAGE_LEFT),
    // 语义族：竖向滚动就是「前进/退回」，与阅读方向无关。
    ("Space", action::NEXT_PAGE),
    ("PageDown", action::NEXT_PAGE),
    ("PageUp", action::PREVIOUS_PAGE),
    ("ArrowDown", action::NEXT_PAGE),
    ("ArrowUp", action::PREVIOUS_PAGE),
    ("KeyS", action::NEXT_PAGE),
    ("KeyW", action::PREVIOUS_PAGE),
    ("Numpad2", action::NEXT_PAGE),
    ("Numpad8", action::PREVIOUS_PAGE),
    // 首尾跳转。
    ("Home", action::FIRST_PAGE),
    ("End", action::LAST_PAGE),
    // 缩放族。三条出厂绑法逐条照 neoview 的 `DEFAULT_READER_INPUT_BINDINGS`
    // （`Equal` / `Minus` / `Digit0`）—— 动作登记了却没有默认键，等于设置页里
    // 解了灰、用户还是不知道该按哪个键。
    ("Equal", action::ZOOM_IN),
    ("Minus", action::ZOOM_OUT),
    ("Digit0", action::RESET_VIEW),
];

/// 桌面端的系统级按键（不属于翻页，但改造前 `reader_input_controller.dart` 里写死了
/// `F11` 全屏）。接管运行时后它也得是**数据**，否则「把 F11 改绑成别的」做不到。
///
/// `Enter` → 唤出轮盘是 neoview 的出厂绑法之一（另一条是右键按下，见下面的鼠标表）：
/// 「怎么打开轮盘」与「轮盘里每一格干什么」在 Rossi 里同一套机制 —— 一条输入 →
/// 一个动作 id，由同一张表解析。
pub const DEFAULT_SYSTEM_KEY_BINDINGS: [(&str, &str); 2] = [
    ("F11", action::FULLSCREEN),
    ("Enter", action::OPEN_RADIAL_MENU),
];

/// 出厂鼠标绑定。neoview 用**右键按下**（不是点击）开轮盘：按下即开、拖到某一格
/// 松手即执行 —— 这条路径不该被单击的翻页判定吃掉，所以 `action` 是 `press`。
pub const DEFAULT_MOUSE_BINDINGS: [(u8, PointerAction, &str); 1] =
    [(2, PointerAction::Press, action::OPEN_RADIAL_MENU)];

/// 九宫格点击预设 → 绑定表（`context = reader`，全部启用）。
pub fn tap_preset_bindings(preset: TapPreset) -> Vec<InputBinding> {
    let advance = preset.advance_area();
    let retreat = preset.retreat_area();
    vec![
        area_binding("preset-tap-advance", advance, action::PAGE_RIGHT),
        area_binding("preset-tap-retreat", retreat, action::PAGE_LEFT),
        area_binding(
            "preset-tap-center",
            ReaderViewArea::MiddleCenter,
            action::TOGGLE_CONTROLS,
        ),
    ]
}

/// 视频出厂键位（`context = video`，优先级 150 > `reader` 的 100）。
///
/// **逐条照抄 neoview `READER_FACTORY_INPUT_BINDINGS` 里
/// `// video (legacy videoPlayer context → video)` 那一段的键盘部分**
/// （`packages/nodes/neoview/src/domain/input/ReaderInputBindings.ts`）。
/// 上游还有两类没搬过来，理由不同：
/// - 三条 `area` 点击（中格播放/暂停、左格 −10 s、右格 +10 s）在 Rossi 由
///   `VideoPageSurface._tapZones` 直接实现（对应上游 `PageVideo.tsx` 那一处），
///   再进一遍绑定表就是双触发；
/// - 上游把 `KeyC`/`KeyX`/`KeyZ`（加速 / 减速 / 切换倍速）挂在 **`global`**。
///   Rossi 先把它们留在 `video` 档：全局吃掉这三个键而当前没有活动视频时，
///   用户看到的是「按了没反应」，那比「视频里没有这两个键」更糟。
pub const DEFAULT_VIDEO_KEY_BINDINGS: [(&str, &str); 7] = [
    ("ArrowRight", action::VIDEO_SEEK_FORWARD),
    ("ArrowLeft", action::VIDEO_SEEK_BACKWARD),
    ("MediaTrackNext", action::VIDEO_SEEK_FORWARD),
    ("MediaTrackPrevious", action::VIDEO_SEEK_BACKWARD),
    ("KeyC", action::VIDEO_SPEED_UP),
    ("KeyX", action::VIDEO_SPEED_DOWN),
    ("KeyZ", action::VIDEO_TOGGLE_SPEED),
];

/// 出厂按键/鼠标预设 → 绑定表（翻页键 + `F11` 全屏 + `Enter`/右键按下开轮盘 + 视频档）。
pub fn key_preset_bindings() -> Vec<InputBinding> {
    let mut bindings: Vec<InputBinding> = DEFAULT_KEY_BINDINGS
        .iter()
        .chain(DEFAULT_SYSTEM_KEY_BINDINGS.iter())
        .enumerate()
        .map(|(index, (code, action_id))| key_binding(index, *code, *action_id))
        .collect();
    bindings.extend(
        DEFAULT_VIDEO_KEY_BINDINGS
            .iter()
            .enumerate()
            .map(|(index, (code, action_id))| video_key_binding(index, *code, *action_id)),
    );
    bindings.extend(DEFAULT_MOUSE_BINDINGS.iter().enumerate().map(
        |(index, (button, action_kind, action_id))| {
            mouse_binding(index, *button, *action_kind, *action_id)
        },
    ));
    bindings
}

/// 视频档按键绑定：与 [`key_binding`] 只差 `context` 一项。
fn video_key_binding(index: usize, code: &str, action_id: &str) -> InputBinding {
    InputBinding {
        id: format!("preset-video-key-{index}-{code}"),
        action: action_id.into(),
        follow_up_actions: Vec::new(),
        context: InputContext::Video,
        enabled: true,
        ignore_repeat: false,
        input: InputDescriptor::Keyboard {
            code: code.into(),
            trigger: KeyTrigger::Down,
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
        },
    }
}

fn mouse_binding(
    index: usize,
    button: u8,
    action_kind: PointerAction,
    action_id: &str,
) -> InputBinding {
    InputBinding {
        id: format!("preset-mouse-{index}-b{button}"),
        action: action_id.into(),
        follow_up_actions: Vec::new(),
        context: InputContext::Reader,
        enabled: true,
        ignore_repeat: false,
        input: InputDescriptor::Mouse {
            button,
            action: action_kind,
        },
    }
}

fn key_binding(index: usize, code: &str, action_id: &str) -> InputBinding {
    InputBinding {
        id: format!("preset-key-{index}-{code}"),
        action: action_id.into(),
        follow_up_actions: Vec::new(),
        context: InputContext::Reader,
        enabled: true,
        ignore_repeat: false,
        input: InputDescriptor::Keyboard {
            code: code.into(),
            trigger: KeyTrigger::Down,
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
        },
    }
}

fn area_binding(id: &str, area: ReaderViewArea, action_id: &str) -> InputBinding {
    InputBinding {
        id: id.into(),
        action: action_id.into(),
        follow_up_actions: Vec::new(),
        context: InputContext::Reader,
        enabled: true,
        ignore_repeat: false,
        input: InputDescriptor::Area {
            area,
            button: 0,
            action: PointerAction::Click,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::operation_binding::model::InputDescriptor;
    use crate::operation_binding::resolve::{PageTurn, resolve, resolve_page_turn};
    use crate::operation_binding::vocabulary::ReadingDirection;

    fn area_click(area: ReaderViewArea) -> InputDescriptor {
        InputDescriptor::Area {
            area,
            button: 0,
            action: PointerAction::Click,
        }
    }

    #[test]
    fn video_context_wins_over_reader_on_the_same_key() {
        let bindings = key_preset_bindings();
        let keyboard = |code: &str| InputDescriptor::Keyboard {
            code: code.into(),
            trigger: KeyTrigger::Down,
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
        };

        // 静图页：右箭头还是「向右翻页」。
        assert_eq!(
            resolve(&bindings, &keyboard("ArrowRight"), &[InputContext::Reader])
                .expect("reader 档右箭头有绑定")
                .action,
            action::PAGE_RIGHT
        );

        // 视频页：同一个键改成 +10 秒。这就是 `video` = 150 高于 `reader` = 100 的全部意义。
        assert_eq!(
            resolve(
                &bindings,
                &keyboard("ArrowRight"),
                &[InputContext::Reader, InputContext::Video],
            )
            .expect("视频在场时右箭头必须归视频")
            .action,
            action::VIDEO_SEEK_FORWARD
        );

        // 视频专属键在没有视频时**没有解**（不能既绑了键又让静图页的输入被吃掉）。
        assert!(resolve(&bindings, &keyboard("KeyX"), &[InputContext::Reader]).is_none());
        assert_eq!(
            resolve(&bindings, &keyboard("KeyX"), &[InputContext::Video])
                .expect("视频档 KeyX 有绑定")
                .action,
            action::VIDEO_SPEED_DOWN
        );

        // 缩放族三条出厂键（逐条照 neoview 的默认表）。注册表把它们标成已实现，
        // 但「已实现」要能被**默认按键**证明端到端可达 —— 否则解了灰也没人知道按哪个。
        for (code, expected) in [
            ("Equal", action::ZOOM_IN),
            ("Minus", action::ZOOM_OUT),
            ("Digit0", action::RESET_VIEW),
        ] {
            assert_eq!(
                resolve(&bindings, &keyboard(code), &[InputContext::Reader])
                    .expect("缩放族默认键必须有解")
                    .action,
                expected,
                "{code} 应当解到 {expected}"
            );
        }
    }

    #[test]
    fn right_hand_preset_binds_right_side_to_page_right() {
        let bindings = tap_preset_bindings(TapPreset::RightHand);
        let advance = resolve(
            &bindings,
            &area_click(ReaderViewArea::MiddleRight),
            &[InputContext::Reader],
        )
        .expect("右中格必须有绑定");
        assert_eq!(advance.action, action::PAGE_RIGHT);
        assert_eq!(advance.id, "preset-tap-advance");

        let retreat = resolve(
            &bindings,
            &area_click(ReaderViewArea::MiddleLeft),
            &[InputContext::Reader],
        )
        .expect("左中格必须有绑定");
        assert_eq!(retreat.action, action::PAGE_LEFT);
    }

    #[test]
    fn left_hand_preset_mirrors_the_advance_side() {
        let bindings = tap_preset_bindings(TapPreset::LeftHand);
        let advance = resolve(
            &bindings,
            &area_click(ReaderViewArea::MiddleLeft),
            &[InputContext::Reader],
        )
        .expect("左中格必须是前进热区");
        assert_eq!(advance.action, action::PAGE_RIGHT);
        assert_eq!(
            resolve(
                &bindings,
                &area_click(ReaderViewArea::MiddleRight),
                &[InputContext::Reader]
            )
            .unwrap()
            .action,
            action::PAGE_LEFT
        );
    }

    #[test]
    fn center_area_toggles_controls_not_pages() {
        for preset in [TapPreset::RightHand, TapPreset::LeftHand] {
            let bindings = tap_preset_bindings(preset);
            let center = resolve(
                &bindings,
                &area_click(ReaderViewArea::MiddleCenter),
                &[InputContext::Reader],
            )
            .expect("正中格必须有绑定");
            assert_eq!(center.action, action::TOGGLE_CONTROLS, "{preset:?}");
        }
    }

    #[test]
    fn presets_are_direction_agnostic_direction_resolves_meaning() {
        // 同一张右手绑定表：右开点右 = 下一页；左开点右 = 上一页。
        let bindings = tap_preset_bindings(TapPreset::RightHand);
        let resolved = resolve(
            &bindings,
            &area_click(ReaderViewArea::MiddleRight),
            &[InputContext::Reader],
        )
        .unwrap();
        assert_eq!(
            resolve_page_turn(&resolved.action, ReadingDirection::LeftToRight),
            Some(PageTurn::Next)
        );
        assert_eq!(
            resolve_page_turn(&resolved.action, ReadingDirection::RightToLeft),
            Some(PageTurn::Previous)
        );
    }

    #[test]
    fn key_preset_is_spatial_for_arrows_semantic_for_space() {
        let bindings = key_preset_bindings();
        let arrow_right = resolve(
            &bindings,
            &InputDescriptor::Keyboard {
                code: "ArrowRight".into(),
                trigger: KeyTrigger::Down,
                ctrl: false,
                alt: false,
                shift: false,
                meta: false,
            },
            &[InputContext::Reader],
        )
        .expect("右方向键必须有绑定");
        assert_eq!(
            arrow_right.action,
            action::PAGE_RIGHT,
            "右键绑空间动作，方向交给解析器"
        );

        let space = resolve(
            &bindings,
            &InputDescriptor::Keyboard {
                code: "Space".into(),
                trigger: KeyTrigger::Down,
                ctrl: false,
                alt: false,
                shift: false,
                meta: false,
            },
            &[InputContext::Reader],
        )
        .unwrap();
        assert_eq!(
            space.action,
            action::NEXT_PAGE,
            "空格是语义动作：任何方向下都是下一页"
        );

        // 键位 id 唯一。
        let mut ids: Vec<&str> = bindings.iter().map(|b| b.id.as_str()).collect();
        ids.sort_unstable();
        let len = ids.len();
        ids.dedup();
        assert_eq!(ids.len(), len, "键盘预设的 id 不许重复");
    }

    #[test]
    fn every_preset_action_is_implemented_in_this_repo() {
        // 预设里出现「schema 认了但运行时不执行」的动作 = 出厂就坏：用户开机第一次按
        // 那个键就没有任何反应，而且看不出原因。注册表的 `implemented` 就是为这条判据存在的。
        for binding in key_preset_bindings()
            .into_iter()
            .chain(tap_preset_bindings(TapPreset::RightHand))
            .chain(tap_preset_bindings(TapPreset::LeftHand))
        {
            let entry = super::super::vocabulary::action_definition(&binding.action)
                .unwrap_or_else(|| panic!("预设绑了一个注册表里没有的动作：{}", binding.action));
            assert!(
                entry.implemented,
                "{} 绑了尚未实现的动作 {}（出厂即失效）",
                binding.id, binding.action
            );
        }
    }

    #[test]
    fn key_preset_covers_every_key_the_legacy_reader_knew() {
        // 绑定表接管运行时之后就是**唯一**判定处：这里少一个键，那个键就当场失效。
        // 名单 = 改造前 `lib/page/comic_read/method/key.dart` 认的全集 + F11。
        let keys: Vec<(&'static str, String)> = key_preset_bindings()
            .into_iter()
            .filter_map(|binding| {
                let context = binding.context.as_str();
                match binding.input {
                    InputDescriptor::Keyboard { code, .. } => Some((context, code)),
                    _ => None,
                }
            })
            .collect();
        let codes: Vec<String> = keys.iter().map(|(_, code)| code.clone()).collect();
        for expected in [
            "ArrowRight",
            "ArrowLeft",
            "ArrowUp",
            "ArrowDown",
            "KeyA",
            "KeyD",
            "KeyW",
            "KeyS",
            "Numpad4",
            "Numpad6",
            "Numpad8",
            "Numpad2",
            "Space",
            "PageDown",
            "PageUp",
            "Home",
            "End",
            "F11",
        ] {
            assert!(
                codes.contains(&expected.to_string()),
                "预设里少了 {expected}"
            );
        }
        // 冲突口径 = **(context, 输入)**，不是「输入」本身。
        // neoview 的 `readerInputConflictKey` 就是 `${context}:${descriptorKey}`：
        // `video` 档把 ArrowRight 再绑一次是**设计**（视频页里右箭头是 +10 秒），
        // 只按裸键名去重会把这种合法的跨档覆盖判成冲突。
        let unique: std::collections::HashSet<(&str, &str)> =
            keys.iter().map(|(c, code)| (*c, code.as_str())).collect();
        assert_eq!(
            unique.len(),
            keys.len(),
            "同一个 context 里同一个键不许出现两次（那才是冲突）"
        );
    }

    #[test]
    fn preset_round_trips_through_config() {
        // 预设要能落进绑定包（导出/导入不丢字段）。
        for preset in [TapPreset::RightHand, TapPreset::LeftHand] {
            let bindings = tap_preset_bindings(preset);
            let json = serde_json::to_string(&bindings).unwrap();
            let parsed: Vec<InputBinding> = serde_json::from_str(&json).unwrap();
            assert_eq!(parsed, bindings, "{preset:?} 的绑定表必须能 JSON 往返");
        }
        assert_eq!(
            TapPreset::parse(TapPreset::RightHand.as_str()),
            Some(TapPreset::RightHand)
        );
    }
}
