//! 域名前置（domain fronting / IP 直连）。
//!
//! # 背景
//!
//! e-hentai.org / exhentai.org 在墙内走「系统 DNS + TLS SNI」时会被 RST，
//! 但「直连站点真实 IP + TLS 不发 SNI + 带 `Host` 头」可以穿透。
//! 这正是 JHenTai（`lib/src/setting/network_setting.dart` 的 `host2IPs`
//! + `lib/src/network/eh_ip_provider.dart` 的 `RoundRobinIpProvider`
//! + Dio 拦截器改写 host）所使用的方案。
//!
//! # 为什么必须由宿主实现
//!
//! Breeze 插件的 JS 请求最终走 `reqwest`，默认会协商 HTTP/2。
//! 而 HTTP/2 没有 `Host` 头，只有 `:authority` 伪头；hyper 的 `:authority`
//! **只从 URI 取**，于是 IP 形式的 URL 会让 `:authority = <IP>`，
//! Cloudflare / Apache 对「IP authority + Host 头」一律回 **400 Bad Request**。
//!
//! JS 侧没有任何手段强制 reqwest 只发 HTTP/1.1（`http1_only()` 是 Rust 侧
//! `ClientBuilder` 的配置），所以这段逻辑只能落在宿主。
//!
//! # 职责划分
//!
//! - **插件**：维护 host -> IP 表（内置表 + 用户覆盖），通过公开的 `fronting`
//!   对象下发（`fronting.setHosts`），用 `fronting.probe` 给候选 IP 测延迟，
//!   再把最优结果写回。`fronting` 是 `js/35_fronting.js` 对内部 `__http_*`
//!   函数的封装，参数与返回值都是普通对象。
//! - **宿主**（本模块）：把命中的请求改写为 IP URL、注入 `Host` 头、
//!   强制 HTTP/1.1、不自动跟随重定向、跳过证书校验、轮询选 IP、
//!   连接失败时把 IP 标记为不健康（5 分钟）。
//!
//! 表为空时全部请求走原链路，对既有行为零影响。
//!
//! # 启用方式
//!
//! Flutter 构建默认编译进产物（`hook/build.dart` 默认传 `--features host-fronting`），
//! 需要关闭时设置环境变量 `BREEZE_HOST_FRONTING=0` 后重新构建。
//! 直接跑 cargo 时用 `cargo build --features host-fronting`。
//! 未启用时四个内部函数不注册，公开的 `fronting` 对象（`js/35_fronting.js`）
//! 统一返回 `fronting-unsupported`，插件不需要做能力探测。
//!
//! 注意：默认开启只是让宿主「具备能力」；插件不调用 `fronting.setHosts`
//! 时前置表为空，所有请求仍走原链路。
//!
//! # 延迟探测
//!
//! 插件侧入口是 `fronting.probe(payload, { signal })`；下面是它封装的
//! 内部实现 `__http_probe_front_hosts(payloadJson)`，返回 Promise<string>：
//!
//! ```json
//! {
//!   "host": "e-hentai.org",
//!   "ips": ["172.66.132.196", "172.66.140.62"],
//!   "scheme": "https",
//!   "timeoutMs": 3000,
//!   "concurrency": 4,
//!   "samples": 1
//! }
//! ```
//!
//! `ips` 可省略（默认测当前前置表里该 host 的全部 IP）；显式传入时直接测这些
//! IP，**不要求先写进前置表**，这样插件可以「先测再写回最优结果」。只允许
//! http/https、端口固定 80/443、路径固定 `/`、方法固定 `HEAD`，不发送自定义
//! header/body，也不读取响应体。返回：
//!
//! ```json
//! {
//!   "ok": true,
//!   "host": "e-hentai.org",
//!   "scheme": "https",
//!   "results": [
//!     { "ip": "172.66.132.196", "ok": true, "status": 200,
//!       "ttfbMs": 85, "avgMs": 92, "samplesMs": [85, 99],
//!       "samplesSent": 2, "samplesReceived": 2, "lossRate": 0.0,
//!       "error": null }
//!   ]
//! }
//! ```
//!
//! - `ttfbMs`：最快一次采样的耗时（TCP + TLS + 服务端处理 + 首字节）
//! - `avgMs`：成功采样的平均耗时
//! - `lossRate`：`(samplesSent - samplesReceived) / samplesSent`，0.0 ~ 1.0
//! - `ok`：收到过至少一次 HTTP 响应（任何状态码都算可达）
//! - `error`：`timeout` / `connect` / `request` / `other` / `busy` /
//!   `batch-timeout`
//!
//! 采样遇到连续两次失败就放弃剩余采样，所以死 IP 不会白等 `samples * timeout`。
//!
//! # 限流
//!
//! 配额按插件隔离，资源限制见 [`super::front_probe`] 模块文档：单插件并发 4、
//! 单插件同时 2 批、每插件批次令牌桶（容量 2、5 秒补 1）。刻意不设全局并发上限，
//! 避免一个插件探测时把另一个插件的探测挤成 `probe-busy`。超限分别返回
//! `probe-busy` / `probe-rate-limited`（后者带 `retryAfterMs`）。
//!
//! # 信任模型
//!
//! 前置表按 runtime（插件）隔离：key 是 `install_host_bindings` 收到的 runtime
//! name（Breeze 侧就是 plugin id），插件只能读写自己的 host -> IP 表，不能看到
//! 或清空别的插件的表。宿主默认只校验 IP 是公网地址，不校验 host 白名单（白名单
//! 由插件维护）；`allow_private_network` 打开时保留地址也放行，与普通请求的内网
//! 拦截共用同一个开关。探测 API 接受任意合法公网 IP（不限于前置表内），
//! 但同样拒绝保留地址段，并且受并发与批次令牌桶限流。

use std::collections::HashMap;
use std::net::{IpAddr, Ipv6Addr};
use std::str::FromStr;
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Context as _, Result as AnyResult, anyhow};
use reqwest::Client;
use reqwest::redirect::Policy;
use reqwest_middleware::ClientWithMiddleware;
use serde_json::{Value, json};

use super::http::{HttpClientConfig, apply_proxy_config, wrap_http_client};

/// 不健康 IP 的冷却时长：5 分钟（与 JHenTai `RoundRobinIpProvider` 的
/// `inMinutes < 5` 判定一致）。
pub const FRONT_UNHEALTHY_TTL: Duration = Duration::from_secs(300);

/// 前置客户端的超时时间。
const FRONT_CLIENT_TIMEOUT: Duration = Duration::from_secs(30);

/// 一条前置目标：域名 + 选中的 IP。
#[derive(Debug, Clone)]
pub(crate) struct FrontTarget {
    /// 原始域名（小写），用于 `Host` 头。
    pub host: String,
    /// 实际连接的 IP。
    pub ip: String,
}

/// 单个插件 runtime 的前置状态。
///
/// - `hosts`：host（小写）-> IP 列表
/// - `unhealthy`：IP -> 不健康截止时刻
/// - `cursor`：host -> 轮询游标
#[derive(Debug, Default)]
struct FrontHostState {
    hosts: HashMap<String, Vec<String>>,
    unhealthy: HashMap<String, Instant>,
    cursor: HashMap<String, usize>,
}

/// 按 runtime（插件）隔离的前置状态。
///
/// key 是 `install_host_bindings` 收到的 runtime name（Breeze 侧就是 plugin id）。
/// 这样插件 A 既看不到、也改不了插件 B 的 host -> IP 表。
static FRONT_RUNTIME_STATES: LazyLock<Mutex<HashMap<String, FrontHostState>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn front_runtime_states() -> &'static Mutex<HashMap<String, FrontHostState>> {
    &FRONT_RUNTIME_STATES
}

/// 前置状态按 runtime 隔离，但测试共享同一进程，仍需串行化。
#[cfg(test)]
pub(crate) static FRONT_TEST_LOCK: Mutex<()> = Mutex::new(());

/// 把 IP 字面量规范化成标准文本形式，非 IP 字面量返回 `None`。
///
/// - IPv4：严格点分十进制，拒绝前导零（`01.2.3.4` 会被某些解析器当八进制）。
/// - IPv6：接受裸写法和 `[...]` 写法，统一输出压缩小写形式，这样同一个地址
///   无论插件怎么写都只会存成一条记录。
fn normalize_front_ip(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }
    // 方括号只用于 IPv6（RFC 3986），`[1.2.3.4]` 视为非法。
    if let Some(inner) = trimmed.strip_prefix('[') {
        let inner = inner.strip_suffix(']')?;
        return inner.parse::<Ipv6Addr>().ok().map(|ip| ip.to_string());
    }
    if trimmed.contains(':') {
        return trimmed.parse::<Ipv6Addr>().ok().map(|ip| ip.to_string());
    }
    if is_valid_ipv4_literal(trimmed) {
        return Some(trimmed.to_string());
    }
    None
}

/// 严格校验 IPv4 点分十进制写法。
fn is_valid_ipv4_literal(value: &str) -> bool {
    let mut parts = value.split('.');
    for _ in 0..4 {
        let part = match parts.next() {
            Some(p) => p,
            None => return false,
        };
        if part.is_empty() || part.len() > 3 {
            return false;
        }
        if !part.bytes().all(|b| b.is_ascii_digit()) {
            return false;
        }
        if part.len() > 1 && part.starts_with('0') {
            return false;
        }
        if part.parse::<u8>().is_err() {
            return false;
        }
    }
    parts.next().is_none()
}

/// 判断 IP 是否属于「不应被前置」的保留地址段。
///
/// 前置表由插件下发，理论上可能来自不可信来源。如果表里混入内网 / 环回 /
/// 链路本地地址并被前置，等于凭空开出一条访问内网的通道（SSRF）。
/// 宿主原有的 `ensure_http_target_allowed` 也会拦这类地址，但那条检查在
/// **域名解析之后**才生效；前置时我们根本不解析域名，所以要在这里直接拒绝。
///
/// 是否启用由 `allow_private_network` 决定，与普通请求的内网拦截共用同一个
/// 开关：配置打开时本函数不参与判定（用户显式选择放行内网）。
fn is_rejectable_front_ip(ip: &str) -> bool {
    let parsed = match IpAddr::from_str(ip.trim()) {
        Ok(v) => v,
        Err(_) => return true,
    };
    match parsed {
        IpAddr::V4(v4) => {
            let octets = v4.octets();
            v4.is_loopback()
                || v4.is_private()
                || v4.is_link_local()
                || v4.is_unspecified()
                || v4.is_broadcast()
                || v4.is_documentation()
                // 100.64.0.0/10：运营商级 NAT（RFC 6598）
                || (octets[0] == 100 && (64..=127).contains(&octets[1]))
        }
        // 与请求时的内网拦截共用同一套判断，避免两处规则漂移。
        // 额外拒绝文档段 2001:db8::/32（`Ipv6Addr::is_documentation` 尚未稳定）。
        IpAddr::V6(v6) => {
            let segments = v6.segments();
            super::http::is_private_or_local_ipv6(v6)
                || (segments[0] == 0x2001 && segments[1] == 0x0db8)
        }
    }
}

/// 下发前置表。`payload` 是 JSON 字符串：`{ "e-hentai.org": ["1.2.3.4"] }`。
///
/// - 非 IP 字面量与保留地址段（环回 / 内网 / 链路本地等）在写入时就被拒绝，
///   计入 `rejected`，避免它们在每次请求时再被判断。
/// - 传空对象等于关闭前置。
/// - 幂等：表内容没变就不动状态（保留不健康记录与轮询游标）。
pub fn set_front_hosts(runtime: &str, payload: String) -> String {
    let parsed: Value = match serde_json::from_str(&payload) {
        Ok(v) => v,
        Err(e) => {
            return json!({
                "ok": false,
                "error": crate::tr!("failed-to-parse-front-hosts-json", e = e.to_string()),
            })
            .to_string();
        }
    };

    // 与请求路径 `ensure_http_target_allowed` 共用同一个开关，避免出现
    // 「直接 fetch 能连内网、前置却连不了」这种不可解释的行为差异。
    let allow_private_network = super::http::worker_http_config().allow_private_network;

    let mut table: HashMap<String, Vec<String>> = HashMap::new();
    let mut rejected = 0usize;
    if let Value::Object(obj) = parsed {
        for (raw_host, raw_ips) in obj {
            let host = raw_host
                .trim()
                .trim_start_matches("https://")
                .trim_start_matches("http://")
                .trim_end_matches('/')
                .to_ascii_lowercase();
            if host.is_empty() {
                continue;
            }
            let mut ips: Vec<String> = Vec::new();
            if let Value::Array(items) = raw_ips {
                for item in items {
                    let ip = match item.as_str().and_then(normalize_front_ip) {
                        Some(ip) => ip,
                        None => {
                            rejected += 1;
                            continue;
                        }
                    };
                    if !allow_private_network && is_rejectable_front_ip(&ip) {
                        rejected += 1;
                        continue;
                    }
                    if !ips.contains(&ip) {
                        ips.push(ip);
                    }
                }
            }
            if !ips.is_empty() {
                table.insert(host, ips);
            }
        }
    }

    let host_count = table.len();
    let ip_count: usize = table.values().map(|v| v.len()).sum();

    let mut states = match front_runtime_states().lock() {
        Ok(s) => s,
        Err(_) => {
            return json!({ "ok": false, "error": crate::tr!("front-host-state-lock-is-poisoned") })
                .to_string();
        }
    };
    let state = states.entry(runtime.to_string()).or_default();

    if state.hosts != table {
        state.hosts = table;
        // 表变了就重置游标，但保留不健康记录（新表里没有的 IP 记录会被忽略）。
        state.cursor.clear();
    }

    json!({
        "ok": true,
        "hosts": host_count,
        "ips": ip_count,
        "rejected": rejected,
        // 告诉插件本次是否放行了保留地址，方便排查「为什么 127.0.0.1 没被拒」。
        "allowPrivateNetwork": allow_private_network,
    })
    .to_string()
}

/// 读回当前前置表 + 每个 IP 的健康状态。
pub fn get_front_hosts(runtime: &str) -> String {
    let states = match front_runtime_states().lock() {
        Ok(s) => s,
        Err(_) => {
            return json!({ "ok": false, "error": crate::tr!("front-host-state-lock-is-poisoned") })
                .to_string();
        }
    };
    let state = match states.get(runtime) {
        Some(state) => state,
        None => return json!({ "ok": true, "hosts": {} }).to_string(),
    };

    let now = Instant::now();
    let mut hosts_map = serde_json::Map::new();
    for (host, ips) in &state.hosts {
        let mut entries = Vec::new();
        for ip in ips {
            let healthy = match state.unhealthy.get(ip) {
                Some(deadline) => *deadline <= now,
                None => true,
            };
            entries.push(json!({ "ip": ip, "healthy": healthy }));
        }
        hosts_map.insert(host.clone(), Value::Array(entries));
    }

    json!({ "ok": true, "hosts": Value::Object(hosts_map) }).to_string()
}

/// 清空前置表（关闭前置）。
pub fn clear_front_hosts(runtime: &str) -> String {
    if let Ok(mut states) = front_runtime_states().lock() {
        states.remove(runtime);
    }
    json!({ "ok": true }).to_string()
}

/// 读取某个 host 当前登记的所有 IP（最长后缀匹配，返回副本）。
///
/// 供延迟探测使用：调用方不传 `ips` 时，默认测的就是这张表。
pub(crate) fn front_host_ips(runtime: &str, host: &str) -> Option<Vec<String>> {
    let states = front_runtime_states().lock().ok()?;
    let state = states.get(runtime)?;
    match_front_host(&state.hosts, host).cloned()
}

/// 探测入口的 IP 校验：必须是合法 IP 字面量，且（未放行内网时）不是保留地址。
///
/// 返回规范化后的 IP，方便调用方直接用于构造 URL 和去重。
pub(crate) fn validate_probe_ip(ip: &str, allow_private_network: bool) -> Option<String> {
    let ip = normalize_front_ip(ip)?;
    if !allow_private_network && is_rejectable_front_ip(&ip) {
        return None;
    }
    Some(ip)
}

/// 最长后缀匹配：优先命中更具体的键。
///
/// 例如表里有 `exhentai.org` 和 `s.exhentai.org` 时，`s.exhentai.org` 命中前者自己的键；
/// 只有表里没有 `s.exhentai.org` 时才回落到 `exhentai.org`。
fn match_front_host<'a>(
    table: &'a HashMap<String, Vec<String>>,
    host: &str,
) -> Option<&'a Vec<String>> {
    let mut best: Option<(usize, &Vec<String>)> = None;
    for (key, ips) in table {
        if host == key || host.ends_with(&format!(".{key}")) {
            let len = key.len();
            if best.is_none() || len > best.unwrap().0 {
                best = Some((len, ips));
            }
        }
    }
    best.map(|(_, ips)| ips)
}

/// 解析出本次请求要用的前置目标。
///
/// 流程：最长后缀匹配 -> 过滤不健康 IP -> 轮询选取 -> 拒绝保留地址段。
pub(crate) fn resolve_front_target(runtime: &str, url: &str) -> AnyResult<Option<FrontTarget>> {
    let parsed = match reqwest::Url::parse(url) {
        Ok(v) => v,
        Err(e) => {
            return Err(anyhow::Error::new(e).context(crate::tr!("failed-to-parse-url", url = url)));
        }
    };
    let host = match parsed.host_str() {
        Some(h) => h.trim().to_ascii_lowercase(),
        None => return Ok(None),
    };
    if host.is_empty() {
        return Ok(None);
    }

    let mut states = match front_runtime_states().lock() {
        Ok(s) => s,
        Err(_) => return Ok(None),
    };
    let state = match states.get_mut(runtime) {
        Some(state) => state,
        None => return Ok(None),
    };

    let ips = match match_front_host(&state.hosts, &host) {
        Some(v) => v.clone(),
        None => return Ok(None),
    };
    if ips.is_empty() {
        return Ok(None);
    }
    let cursor = *state.cursor.get(&host).unwrap_or(&0);
    let unhealthy_ips: Vec<String> = state
        .unhealthy
        .iter()
        .filter(|(_, deadline)| **deadline > Instant::now())
        .map(|(ip, _)| ip.clone())
        .collect();

    // 从游标位置起按全表顺序找第一个健康 IP；全都不健康时退化为游标位置，
    // 宁可用坏 IP 反复重试，也不要直接失败。游标始终按全表长度推进，
    // 这样过滤掉部分 IP 后仍能均匀轮询。
    let start = cursor % ips.len();
    let pick = (0..ips.len())
        .map(|offset| (start + offset) % ips.len())
        .find(|idx| !unhealthy_ips.contains(&ips[*idx]))
        .unwrap_or(start);
    let ip = ips[pick].clone();

    if is_rejectable_front_ip(&ip) {
        tracing::warn!("fronting: refusing to use reserved address {}", ip);
        return Ok(None);
    }

    // 推进游标：从本次选中的 IP 之后继续，保证健康 IP 之间均匀轮询。
    let next = (pick + 1) % ips.len();
    state.cursor.insert(host.clone(), next);

    Ok(Some(FrontTarget { host, ip }))
}

/// 把 URL 的主机部分替换成 IP，路径与查询串原样保留。
///
/// IPv6 必须加方括号：`Url::set_host` 收到裸 IPv6 时会在第一个 `:` 处截断，
/// 把前半段当域名解析，结果连到完全不相干的主机（而且不会报错）。
pub(crate) fn front_url_with_ip(url: &str, ip: &str) -> AnyResult<String> {
    let mut parsed =
        reqwest::Url::parse(url).with_context(|| crate::tr!("failed-to-parse-url", url = url))?;
    let host = if ip.contains(':') && !ip.starts_with('[') {
        format!("[{ip}]")
    } else {
        ip.to_string()
    };
    parsed
        .set_host(Some(&host))
        .map_err(|e| anyhow!("failed-to-set-url-host: {e}"))?;
    Ok(parsed.to_string())
}

/// 标记 IP 为不健康，冷却 `FRONT_UNHEALTHY_TTL`。
pub(crate) fn mark_front_host_unhealthy(runtime: &str, ip: &str) {
    if let Ok(mut states) = front_runtime_states().lock()
        && let Some(state) = states.get_mut(runtime)
    {
        state
            .unhealthy
            .insert(ip.to_string(), Instant::now() + FRONT_UNHEALTHY_TTL);
    }
    tracing::warn!("fronting: marked ip {} unhealthy", ip);
}

/// 创建用于前置请求的客户端。
///
/// 与普通客户端的差别：
/// - `http1_only()`：**关键**。HTTP/2 下 `:authority` 取自 URI（会是 IP），
///   Cloudflare / Apache 一律回 400。
/// - `Policy::none()`：不自动跟随重定向。里站大量使用 302（例如跳到
///   `forums.e-hentai.org/remoteapi.php`），跳转目标在墙内同样解析不到，
///   必须把 3xx 交回插件逐跳手动跟随。
/// - `danger_accept_invalid_certs(true)`：证书签给域名，用 IP 直连必然不匹配。
///   （宿主已在 `lib/main.dart` 全局关闭 TLS 校验，这里与既有用法保持一致。）
fn front_http_client(config: &HttpClientConfig) -> AnyResult<ClientWithMiddleware> {
    let mut builder = Client::builder()
        .timeout(FRONT_CLIENT_TIMEOUT)
        .http1_only()
        .redirect(Policy::none())
        .danger_accept_invalid_certs(true);

    // 与普通客户端共用代理逻辑（HTTP 优先、可回落 SOCKS5）。
    builder = apply_proxy_config(builder, config)?;

    let client = builder
        .build()
        .context(crate::tr!("failed-to-create-http-client"))?;
    Ok(wrap_http_client(client))
}

/// 缓存的前置 client 最长存活时间（与普通 client 一致：兜系统代理变化）。
const FRONT_CLIENT_TTL: Duration = Duration::from_secs(60);

/// 为前置请求挑选客户端（按当前 worker 配置缓存）。
///
/// 缓存键包含代理配置：用户在宿主设置里改代理后缓存自然换键并重建；
/// 系统代理（Clash）变化没有代际信号，靠 [`FRONT_CLIENT_TTL`] 兜底。
pub(crate) fn cached_front_client(config: &HttpClientConfig) -> AnyResult<ClientWithMiddleware> {
    let key = format!(
        "{}|{}|{}|{}|{}",
        config.use_http_proxy,
        config.use_socks5_proxy,
        config.http_proxy.as_deref().unwrap_or(""),
        config.socks5_proxy.as_deref().unwrap_or(""),
        super::http::system_proxy_signature()
    );
    static FRONT_CLIENT_CACHE: LazyLock<Mutex<HashMap<String, (Instant, ClientWithMiddleware)>>> =
        LazyLock::new(|| Mutex::new(HashMap::new()));

    let mut guard = match FRONT_CLIENT_CACHE.lock() {
        Ok(g) => g,
        Err(_) => return front_http_client(config),
    };
    if let Some((built_at, client)) = guard.get(&key)
        && built_at.elapsed() < FRONT_CLIENT_TTL
    {
        return Ok(client.clone());
    }
    let client = front_http_client(config)?;
    guard.insert(key, (Instant::now(), client.clone()));
    Ok(client)
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_RUNTIME: &str = "test-runtime";

    /// 前置表是进程级全局状态，测试之间会互相干扰，必须串行化。
    fn with_serialized_state<T>(f: impl FnOnce() -> T) -> T {
        let _guard = FRONT_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        f()
    }

    /// 前置表的内网拦截读 `allow_private_network`。测试里显式钉住这个值，
    /// 避免被其他用例改动的全局配置影响（每个用例跑在独立线程上，互不干扰）。
    fn set_private_network_allowed(allowed: bool) {
        crate::web_runtime::set_worker_http_config(crate::web_runtime::HttpClientConfig {
            allow_private_network: allowed,
            ..Default::default()
        });
    }

    #[test]
    fn rejects_non_ip_entries() {
        with_serialized_state(|| {
            let result = set_front_hosts(
                TEST_RUNTIME,
                json!({
                    "e-hentai.org": ["172.66.132.196", "not-an-ip", "999.1.1.1"],
                    "exhentai.org": [],
                })
                .to_string(),
            );
            let parsed: Value = serde_json::from_str(&result).unwrap();
            assert_eq!(parsed["ok"], json!(true));
            assert_eq!(parsed["hosts"], json!(1));
            assert_eq!(parsed["ips"], json!(1));
            assert_eq!(parsed["rejected"], json!(2));

            let readback: Value = serde_json::from_str(&get_front_hosts(TEST_RUNTIME)).unwrap();
            let hosts = readback["hosts"].as_object().unwrap();
            assert_eq!(hosts.len(), 1);
            assert!(hosts.contains_key("e-hentai.org"));

            clear_front_hosts(TEST_RUNTIME);
        });
    }

    #[test]
    fn rejects_invalid_json() {
        with_serialized_state(|| {
            let result = set_front_hosts(TEST_RUNTIME, "{not json".to_string());
            let parsed: Value = serde_json::from_str(&result).unwrap();
            assert_eq!(parsed["ok"], json!(false));
            assert!(parsed["error"].as_str().unwrap().contains("JSON"));
        });
    }

    #[test]
    fn longest_suffix_match_wins() {
        with_serialized_state(|| {
            set_front_hosts(
                TEST_RUNTIME,
                json!({
                    "exhentai.org": ["1.1.1.1"],
                    "s.exhentai.org": ["2.2.2.2"],
                })
                .to_string(),
            );
            assert_eq!(
                front_host_ips(TEST_RUNTIME, "s.exhentai.org"),
                Some(vec!["2.2.2.2".to_string()])
            );
            assert_eq!(
                front_host_ips(TEST_RUNTIME, "exhentai.org"),
                Some(vec!["1.1.1.1".to_string()])
            );
            assert_eq!(
                front_host_ips(TEST_RUNTIME, "cdn.exhentai.org"),
                Some(vec!["1.1.1.1".to_string()])
            );
            assert!(front_host_ips(TEST_RUNTIME, "e-hentai.org").is_none());
            clear_front_hosts(TEST_RUNTIME);
        });
    }

    #[test]
    fn rewrite_keeps_path_and_query() {
        let rewritten = front_url_with_ip("https://e-hentai.org/g/1/token/?p=2", "172.66.132.196")
            .expect("rewrite should succeed");
        assert_eq!(rewritten, "https://172.66.132.196/g/1/token/?p=2");
    }

    /// IPv6 字面量：接受裸写法和 `[...]` 写法，统一规范化成压缩小写形式。
    #[test]
    fn normalizes_ipv6_literals() {
        assert_eq!(
            normalize_front_ip("2606:4700:0:0:0:0:6810:84e4").as_deref(),
            Some("2606:4700::6810:84e4")
        );
        assert_eq!(
            normalize_front_ip("  [2606:4700::6810:84e4]  ").as_deref(),
            Some("2606:4700::6810:84e4")
        );
        // IPv4 原样保留，且依旧拒绝前导零。
        assert_eq!(
            normalize_front_ip("172.66.132.196").as_deref(),
            Some("172.66.132.196")
        );
        assert!(normalize_front_ip("172.66.132.0196").is_none());
        assert!(normalize_front_ip("999.1.1.1").is_none());
        assert!(normalize_front_ip("not-an-ip").is_none());
        assert!(normalize_front_ip("").is_none());
        // 方括号只对 IPv6 有意义，IPv4 加方括号视为非法。
        assert!(normalize_front_ip("[172.66.132.196]").is_none());
    }

    /// `Url::set_host` 收到裸 IPv6 会在第一个 `:` 处截断，必须加方括号。
    #[test]
    fn rewrite_brackets_ipv6() {
        let rewritten = front_url_with_ip("https://e-hentai.org/g/1/?p=2", "2606:4700::6810:84e4")
            .expect("rewrite should succeed");
        assert_eq!(rewritten, "https://[2606:4700::6810:84e4]/g/1/?p=2");
    }

    /// 未放行内网时保留地址被拒；放行后 IPv6 公网地址能正常入表。
    #[test]
    fn accepts_public_ipv6_in_front_table() {
        with_serialized_state(|| {
            set_private_network_allowed(false);
            let result = set_front_hosts(
                TEST_RUNTIME,
                json!({
                    "e-hentai.org": [
                        "2606:4700::6810:84e4",
                        "[2606:4700::6810:84e4]",
                        "::1",
                        "fe80::1",
                        "2002:7f00:1::1",
                        "64:ff9b::7f00:1",
                    ],
                })
                .to_string(),
            );
            let parsed: Value = serde_json::from_str(&result).unwrap();
            assert_eq!(parsed["ok"], json!(true));
            // 两种写法去重成一条，其余四个保留地址被拒。
            assert_eq!(parsed["ips"], json!(1));
            assert_eq!(parsed["rejected"], json!(4));
            assert_eq!(
                front_host_ips(TEST_RUNTIME, "e-hentai.org"),
                Some(vec!["2606:4700::6810:84e4".to_string()])
            );
            clear_front_hosts(TEST_RUNTIME);
        });
    }

    #[test]
    fn reserved_ipv6_addresses_are_refused() {
        assert!(is_rejectable_front_ip("::1"));
        assert!(is_rejectable_front_ip("::"));
        assert!(is_rejectable_front_ip("fe80::1"));
        assert!(is_rejectable_front_ip("fc00::1"));
        assert!(is_rejectable_front_ip("2001:db8::1"));
        // 6to4 / NAT64 内嵌 IPv4 的环回地址。
        assert!(is_rejectable_front_ip("2002:7f00:1::1"));
        assert!(is_rejectable_front_ip("64:ff9b::7f00:1"));
        assert!(!is_rejectable_front_ip("2606:4700::6810:84e4"));
    }

    #[test]
    fn reserved_addresses_are_refused() {
        assert!(is_rejectable_front_ip("127.0.0.1"));
        assert!(is_rejectable_front_ip("10.0.0.1"));
        assert!(is_rejectable_front_ip("192.168.1.1"));
        assert!(is_rejectable_front_ip("169.254.1.1"));
        assert!(is_rejectable_front_ip("100.64.0.1"));
        assert!(!is_rejectable_front_ip("172.66.132.196"));
        assert!(!is_rejectable_front_ip("178.175.128.251"));
    }

    #[test]
    fn unhealthy_ip_is_skipped() {
        with_serialized_state(|| {
            set_front_hosts(
                TEST_RUNTIME,
                json!({ "e-hentai.org": ["172.66.132.196", "172.66.140.62"] }).to_string(),
            );
            mark_front_host_unhealthy(TEST_RUNTIME, "172.66.132.196");

            let first = resolve_front_target(TEST_RUNTIME, "https://e-hentai.org/")
                .unwrap()
                .unwrap();
            let second = resolve_front_target(TEST_RUNTIME, "https://e-hentai.org/")
                .unwrap()
                .unwrap();
            // 不健康的 IP 不应被选中。
            assert_ne!(first.ip, "172.66.132.196");
            assert_ne!(second.ip, "172.66.132.196");

            clear_front_hosts(TEST_RUNTIME);
        });
    }

    #[test]
    fn no_fronting_when_table_is_empty() {
        with_serialized_state(|| {
            clear_front_hosts(TEST_RUNTIME);
            assert!(
                resolve_front_target(TEST_RUNTIME, "https://e-hentai.org/")
                    .unwrap()
                    .is_none()
            );
        });
    }

    /// 只映射一个域名时，其他域名必须完全不受影响。
    #[test]
    fn only_mapped_hosts_are_fronted() {
        with_serialized_state(|| {
            set_front_hosts(
                TEST_RUNTIME,
                json!({
                    "e-hentai.org": ["172.66.132.196"],
                    "exhentai.org": ["178.175.128.251"],
                })
                .to_string(),
            );

            let eh = resolve_front_target(TEST_RUNTIME, "https://e-hentai.org/g/1/")
                .unwrap()
                .unwrap();
            assert_eq!(eh.host, "e-hentai.org");
            assert_eq!(eh.ip, "172.66.132.196");

            let ex = resolve_front_target(TEST_RUNTIME, "https://exhentai.org/")
                .unwrap()
                .unwrap();
            assert_eq!(ex.host, "exhentai.org");
            assert_eq!(ex.ip, "178.175.128.251");

            // 子域名跟随父域的映射。
            let cdn = resolve_front_target(TEST_RUNTIME, "https://s.exhentai.org/x")
                .unwrap()
                .unwrap();
            assert_eq!(cdn.ip, "178.175.128.251");

            // 未映射的域名、相似后缀、非子域字符串后缀一律不前置。
            for url in [
                "https://example.com/",
                "https://evil-e-hentai.org/",
                "https://e-hentai.org.evil.com/",
                "https://e-hentai.org.cn/",
                "https://notexhentai.org/",
            ] {
                assert!(
                    resolve_front_target(TEST_RUNTIME, url).unwrap().is_none(),
                    "{url} should not be fronted"
                );
            }

            clear_front_hosts(TEST_RUNTIME);
        });
    }

    #[test]
    fn reserved_ips_are_rejected_at_set_time() {
        with_serialized_state(|| {
            set_private_network_allowed(false);
            let result = set_front_hosts(
                TEST_RUNTIME,
                json!({ "e-hentai.org": ["127.0.0.1", "10.0.0.1", "172.66.132.196"] }).to_string(),
            );
            let parsed: Value = serde_json::from_str(&result).unwrap();
            assert_eq!(parsed["ok"], json!(true));
            assert_eq!(parsed["hosts"], json!(1));
            assert_eq!(parsed["ips"], json!(1));
            assert_eq!(parsed["rejected"], json!(2));
            clear_front_hosts(TEST_RUNTIME);
        });
    }

    /// 前置表写入时必须拒绝 IPv6 的各种内网 / 内嵌形式，否则等于给插件
    /// 开一条访问内网的通道（SSRF）。
    /// `allow_private_network` 打开时前置表要放行保留地址，与普通请求保持一致。
    #[test]
    fn private_ips_are_accepted_when_private_network_allowed() {
        with_serialized_state(|| {
            let payload =
                json!({ "e-hentai.org": ["127.0.0.1", "10.0.0.1", "172.66.132.196"] }).to_string();

            set_private_network_allowed(true);
            let parsed: Value =
                serde_json::from_str(&set_front_hosts(TEST_RUNTIME, payload.clone())).unwrap();
            assert_eq!(parsed["ips"], json!(3));
            assert_eq!(parsed["rejected"], json!(0));
            assert_eq!(parsed["allowPrivateNetwork"], json!(true));
            clear_front_hosts(TEST_RUNTIME);

            set_private_network_allowed(false);
            let parsed: Value =
                serde_json::from_str(&set_front_hosts(TEST_RUNTIME, payload)).unwrap();
            assert_eq!(parsed["ips"], json!(1));
            assert_eq!(parsed["rejected"], json!(2));
            assert_eq!(parsed["allowPrivateNetwork"], json!(false));
            clear_front_hosts(TEST_RUNTIME);
        });
    }

    #[test]
    fn rejectable_front_ips_cover_ipv6_forms() {
        for ip in [
            "::1",
            "::",
            "fc00::1",
            "fe80::1",
            "ff02::1",
            "::ffff:127.0.0.1",
            "::ffff:10.0.0.1",
            "::ffff:169.254.169.254",
            "2002:7f00:0001::",
            "2002:0a00:0001::",
            "64:ff9b::7f00:1",
            "64:ff9b::a00:1",
            "2001:db8::1",
        ] {
            assert!(is_rejectable_front_ip(ip), "{ip} should be rejected");
        }
        for ip in ["2606:4700:3032::6815:2dee", "104.20.32.15"] {
            assert!(!is_rejectable_front_ip(ip), "{ip} should be allowed");
        }
    }

    #[test]
    fn rotation_alternates_between_healthy_ips() {
        with_serialized_state(|| {
            set_front_hosts(
                TEST_RUNTIME,
                json!({
                    "e-hentai.org": ["172.66.132.196", "172.66.140.62", "178.175.128.251"],
                })
                .to_string(),
            );
            mark_front_host_unhealthy(TEST_RUNTIME, "172.66.140.62");

            let picks: Vec<String> = (0..4)
                .map(|_| {
                    resolve_front_target(TEST_RUNTIME, "https://e-hentai.org/")
                        .unwrap()
                        .unwrap()
                        .ip
                })
                .collect();
            // 中间那个 IP 在冷却，剩下两个应严格交替，而不是一直命中同一个。
            assert_eq!(picks[0], "172.66.132.196");
            assert_eq!(picks[1], "178.175.128.251");
            assert_eq!(picks[2], "172.66.132.196");
            assert_eq!(picks[3], "178.175.128.251");

            clear_front_hosts(TEST_RUNTIME);
        });
    }

    /// 不同 runtime（插件）的前置表必须完全隔离。
    #[test]
    fn runtime_tables_are_isolated() {
        with_serialized_state(|| {
            set_front_hosts(
                "runtime-a",
                json!({ "e-hentai.org": ["172.66.132.196"] }).to_string(),
            );
            set_front_hosts(
                "runtime-b",
                json!({ "e-hentai.org": ["172.66.140.62"] }).to_string(),
            );

            assert_eq!(
                front_host_ips("runtime-a", "e-hentai.org"),
                Some(vec!["172.66.132.196".to_string()])
            );
            assert_eq!(
                front_host_ips("runtime-b", "e-hentai.org"),
                Some(vec!["172.66.140.62".to_string()])
            );

            clear_front_hosts("runtime-a");
            assert!(front_host_ips("runtime-a", "e-hentai.org").is_none());
            assert_eq!(
                front_host_ips("runtime-b", "e-hentai.org"),
                Some(vec!["172.66.140.62".to_string()])
            );

            clear_front_hosts("runtime-b");
        });
    }

    /// feature 打开时必须注册四个内部函数，并暴露不带下划线前缀的 `fronting` 对象。
    #[cfg(feature = "host-fronting")]
    #[test]
    fn globals_are_registered_with_feature_enabled() {
        let script = r#"
            JSON.stringify({
              set: typeof __http_set_front_hosts,
              get: typeof __http_get_front_hosts,
              clear: typeof __http_clear_front_hosts,
              probe: typeof __http_probe_front_hosts,
              api: typeof fronting,
              apiSet: typeof fronting.setHosts,
              apiGet: typeof fronting.getHosts,
              apiClear: typeof fronting.clearHosts,
              apiProbe: typeof fronting.probe,
            })
        "#;
        let result = crate::tests::run_async_script(script).expect("script should run");
        let parsed: Value = serde_json::from_str(&result).expect("result should be JSON");
        assert_eq!(parsed["set"], json!("function"));
        assert_eq!(parsed["get"], json!("function"));
        assert_eq!(parsed["clear"], json!("function"));
        assert_eq!(parsed["probe"], json!("function"));
        assert_eq!(parsed["api"], json!("object"));
        assert_eq!(parsed["apiSet"], json!("function"));
        assert_eq!(parsed["apiGet"], json!("function"));
        assert_eq!(parsed["apiClear"], json!("function"));
        assert_eq!(parsed["apiProbe"], json!("function"));
    }

    /// 插件侧公开 API 必须直接收发对象，不需要自己拼 JSON 字符串。
    #[cfg(feature = "host-fronting")]
    #[test]
    fn public_fronting_api_uses_plain_objects() {
        with_serialized_state(|| {
            let script = r#"
                (() => {
                  const set = fronting.setHosts({
                    "e-hentai.org": ["172.66.132.196"]
                  });
                  const get = fronting.getHosts();
                  const clear = fronting.clearHosts();
                  return JSON.stringify({ set, get, clear });
                })()
            "#;
            let result = crate::tests::run_async_script(script).expect("script should run");
            let parsed: Value = serde_json::from_str(&result).expect("result should be JSON");
            assert_eq!(parsed["set"]["ok"], json!(true));
            assert_eq!(parsed["set"]["ips"], json!(1));
            assert_eq!(
                parsed["get"]["hosts"]["e-hentai.org"][0]["ip"],
                json!("172.66.132.196")
            );
            assert_eq!(parsed["clear"]["ok"], json!(true));
        });
    }

    /// 公开 API 的探测入口同样返回 Promise，并复用普通请求的取消通道。
    #[cfg(feature = "host-fronting")]
    #[test]
    fn public_probe_api_returns_parsed_result() {
        let script = r#"
            (async () => {
              const result = await fronting.probe({ host: "not a domain" });
              const ac = new AbortController();
              ac.abort();
              const canceled = await fronting.probe(
                { host: "example.com" },
                { signal: ac.signal },
              );
              return JSON.stringify({ result, canceled });
            })()
        "#;
        let result = crate::tests::run_async_script(script).expect("script should run");
        let parsed: Value = serde_json::from_str(&result).expect("result should be JSON");
        assert_eq!(parsed["result"]["ok"], json!(false));
        assert_eq!(parsed["result"]["error"], json!("invalid-host"));
        assert_eq!(parsed["canceled"]["ok"], json!(false));
        assert_eq!(parsed["canceled"]["canceled"], json!(true));
        assert_eq!(parsed["canceled"]["error"], json!("request-was-canceled"));
    }

    /// 默认构建（feature 关闭）不得暴露内部函数，但 `fronting` 对象仍要在，
    /// 且统一返回 `fronting-unsupported`，插件不需要做能力探测。
    #[cfg(not(feature = "host-fronting"))]
    #[test]
    fn globals_are_absent_without_feature() {
        let script = r#"
            (async () => {
              const set = fronting.setHosts({ "e-hentai.org": ["172.66.132.196"] });
              const get = fronting.getHosts();
              const clear = fronting.clearHosts();
              const probe = await fronting.probe({ host: "e-hentai.org" });
              return JSON.stringify({
                internal: {
                  set: typeof __http_set_front_hosts,
                  get: typeof __http_get_front_hosts,
                  clear: typeof __http_clear_front_hosts,
                  probe: typeof __http_probe_front_hosts,
                },
                api: typeof fronting,
                set,
                get,
                clear,
                probe,
              });
            })()
        "#;
        let result = crate::tests::run_async_script(script).expect("script should run");
        let parsed: Value = serde_json::from_str(&result).expect("result should be JSON");
        assert_eq!(parsed["internal"]["set"], json!("undefined"));
        assert_eq!(parsed["internal"]["get"], json!("undefined"));
        assert_eq!(parsed["internal"]["clear"], json!("undefined"));
        assert_eq!(parsed["internal"]["probe"], json!("undefined"));
        assert_eq!(parsed["api"], json!("object"));
        assert_eq!(parsed["set"]["error"], json!("fronting-unsupported"));
        assert_eq!(parsed["get"]["error"], json!("fronting-unsupported"));
        assert_eq!(parsed["clear"]["error"], json!("fronting-unsupported"));
        assert_eq!(parsed["probe"]["error"], json!("fronting-unsupported"));
    }
}
