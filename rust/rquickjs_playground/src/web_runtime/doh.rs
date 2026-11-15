//! DoH（DNS over HTTPS）解析：给 reqwest 提供自定义 [`Resolve`]，并给 ECH 提供
//! `HTTPS`(type 65) 查询。
//!
//! # 端点由用户配置
//!
//! 端点列表在 `HttpClientConfig::doh_providers`（完整 URL，例如
//! `https://doh.pub/dns-query`），开关是 `HttpClientConfig::doh_enabled`。
//! 开启且有端点时**无条件**挂到 HTTP 客户端上，与是否配置代理无关；
//! DoH 请求本身复用同一份代理配置（走代理时由代理出网）。
//!
//! 墙内 UDP/53 会被污染（`picaapi.picacomic.com` 会解析到 `174.37.154.236`
//! 这类假 IP），而 Cloudflare / Google 的 DoH 端点（`1.1.1.1`、`dns.google`）
//! 本身又被黑洞。默认端点按「国内可达 → 境外干净」排列：
//!
//! ```text
//! doh.pub（腾讯，JSON 干净）┐
//! Digitale Gesellschaft     ├─ 同时发，第一个有效答案胜出
//! Applied Privacy           ┘
//! 全灭 → 系统解析（getaddrinfo）
//! ```
//!
//! # JSON 优先，RFC 8484 兜底
//!
//! 每个端点先按 JSON API 查询（`Accept: application/dns-json`）。腾讯
//! `doh.pub` 只有 JSON 路径是干净的，同一服务的 RFC 8484 路径会被投毒；
//! 而 Digitale Gesellschaft / Applied Privacy 只讲 RFC 8484。所以策略是
//! **JSON 有结果就用，没有（或端点不支持 JSON）再回退 wireformat**：
//!
//! - JSON 返回 `Status=0` 且有对应记录 → 直接用；
//! - JSON 返回 `Status=0` 但没有对应记录 → 回退 wireformat 再确认一次；
//! - JSON 请求失败 / 解析失败 / `Status=2` → 该端点 10 分钟内直接走 wireformat；
//! - `HTTPS`(type 65) 没有 JSON 表示（`doh.pub` 直接回 `UrlParameterError`），
//!   只走 wireformat。
//!
//! # 三条硬约束（都是踩过的坑）
//!
//! 1. **DoH 失败必须回落系统解析**：DoH 只是「更好的 DNS」，不是必需品。
//!    查不到就退回 `getaddrinfo`，不能让 DoH 挂掉把整个网络打死。
//! 2. **必须熔断**：单个端点连续失败 [`DOH_FAILURE_THRESHOLD`] 次后
//!    [`DOH_COOLDOWN`] 内直接跳过它，否则每个请求都要白等一次超时。
//! 3. **必须缓存**：A/AAAA 与 `HTTPS` RR 都带正/负缓存，绝不能让 DoH
//!    阻塞请求路径（之前 8s × 2 端点直接把 10s 的 axios 超时耗光）。
//!
//! # 与代理的关系
//!
//! 旧实现用 hickory 的 DoH，它不吃 reqwest 的代理配置，所以配了代理时干脆
//! 不挂 DoH。现在 DoH 查询走自己的 reqwest 客户端，代理配置直接复用，
//! 因此「开了代理也照样用 DoH」不会出现连接黑洞；代理本身用 IP:端口时
//! 也不存在引导解析死循环。

use std::collections::{HashMap, HashSet};
use std::future::Future;
use std::net::{IpAddr, SocketAddr};
use std::sync::atomic::{AtomicU16, AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, LazyLock, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use futures_util::stream::{FuturesUnordered, StreamExt};
use hickory_proto::op::{Message, MessageType, OpCode, Query, ResponseCode};
use hickory_proto::rr::rdata::svcb::{SvcParamKey, SvcParamValue};
use hickory_proto::rr::rdata::{A, AAAA};
use hickory_proto::rr::{Name, RData, RecordType};
use reqwest::Client;
use reqwest::dns::{Addrs, Name as DnsName, Resolve, Resolving};
use serde::Deserialize;
use tokio::time::timeout;
use url::Url;

use super::http::{HttpClientConfig, apply_proxy_config};

/// 默认端点：腾讯（JSON 干净、墙内最快）+ 两家瑞士隐私解析器（RFC 8484）。
pub const DEFAULT_DOH_PROVIDERS: &[&str] = &[
    "https://doh.pub/dns-query",
    "https://dns.digitale-gesellschaft.ch/dns-query",
    "https://doh.applied-privacy.net/query",
];

/// 单个端点的查询超时（也是并发抢答时的等待上限）。
const DOH_QUERY_TIMEOUT: Duration = Duration::from_millis(2000);
/// 整轮并发的总预算：超过这个时间就当全部端点失败，回落系统解析。
const DOH_RACE_TIMEOUT: Duration = Duration::from_millis(2500);
/// 单个端点连续失败多少次后熔断。
const DOH_FAILURE_THRESHOLD: u32 = 3;
/// 熔断后多久再试一次。
const DOH_COOLDOWN: Duration = Duration::from_secs(60);
/// JSON 路径失败后，多久内直接走 wireformat（避免每次查询都白试一次）。
const DOH_JSON_COOLDOWN: Duration = Duration::from_secs(600);

/// `HTTPS` RR 正缓存（Cloudflare 的 TTL 是 300s）。
const HTTPS_RR_POSITIVE_TTL: Duration = Duration::from_secs(300);
/// `HTTPS` RR 负缓存：一家都没答上来时，60s 内不再重试。
const HTTPS_RR_NEGATIVE_TTL: Duration = Duration::from_secs(60);
/// `HTTPS` RR 空缓存：DNS 答了但没有 `ech`，10 分钟内不再问（换家也是同样答案）。
const HTTPS_RR_EMPTY_TTL: Duration = Duration::from_secs(600);
const HTTPS_RR_CACHE_LIMIT: usize = 256;

/// A/AAAA 正缓存 TTL 的上下限（尊重 DNS TTL，但别太短也别太长）。
const IP_CACHE_POSITIVE_MIN_SECS: u32 = 30;
const IP_CACHE_POSITIVE_MAX_SECS: u32 = 600;
/// A/AAAA 负缓存（查过但没有记录）。
const IP_CACHE_NEGATIVE_TTL: Duration = Duration::from_secs(30);
const IP_CACHE_LIMIT: usize = 512;

/// 已知 DoH 端点的引导 IP。
///
/// 用户填的是域名，解析这个域名本身又需要 DNS——墙内系统 DNS 可能被污染，
/// 所以对已知端点直接钉 IP（TLS 仍按域名校验）。未知端点走系统解析。
const DOH_BOOTSTRAP: &[(&str, &[&str])] = &[
    ("doh.pub", &["1.12.12.12", "120.53.53.53"]),
    ("dns.alidns.com", &["223.5.5.5", "223.6.6.6"]),
    ("dns.digitale-gesellschaft.ch", &["185.95.218.42"]),
    ("doh.applied-privacy.net", &["146.255.56.98"]),
    ("cloudflare-dns.com", &["1.1.1.1", "1.0.0.1"]),
    ("dns.google", &["8.8.8.8", "8.8.4.4"]),
];

/// 一次查询的结论。
#[derive(Debug)]
enum Lookup<T> {
    /// 拿到了需要的记录。
    Found(T),
    /// DNS 答了，但没有需要的记录。
    Empty,
    /// NXDOMAIN：确定不存在，换家也没用。
    NxDomain,
}

/// A/AAAA 的查询结果（`ttl` 取所有记录里的最小值）。
#[derive(Debug, Clone)]
struct DohIps {
    ips: Vec<IpAddr>,
    ttl: u32,
}

/// A/AAAA 查询类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
enum IpKind {
    A,
    Aaaa,
}

impl IpKind {
    fn record_type(self) -> RecordType {
        match self {
            Self::A => RecordType::A,
            Self::Aaaa => RecordType::AAAA,
        }
    }

    fn as_u16(self) -> u16 {
        match self {
            Self::A => 1,
            Self::Aaaa => 28,
        }
    }

    fn json_type(self) -> &'static str {
        match self {
            Self::A => "A",
            Self::Aaaa => "AAAA",
        }
    }
}

/// 单个端点的运行状态（熔断计数、JSON 可用性）。
///
/// 放在全局表里按 URL 复用：重建 HTTP 客户端（改代理、60s TTL）不应该把
/// 熔断状态清零，否则一个坏端点会被反复重试。
#[derive(Default)]
struct EndpointState {
    failures: AtomicU32,
    disabled_until_ms: AtomicU64,
    json_disabled_until_ms: AtomicU64,
}

static ENDPOINT_STATES: LazyLock<Mutex<HashMap<String, Arc<EndpointState>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn endpoint_state(key: &str) -> Arc<EndpointState> {
    let Ok(mut guard) = ENDPOINT_STATES.lock() else {
        return Arc::new(EndpointState::default());
    };
    if let Some(state) = guard.get(key) {
        return state.clone();
    }
    let state = Arc::new(EndpointState::default());
    guard.insert(key.to_string(), state.clone());
    state
}

/// 一个解析后的 DoH 端点。
#[derive(Clone)]
struct DohEndpoint {
    /// 日志里用的名字（域名）。
    label: String,
    /// 完整端点 URL（JSON 查询会在它后面追加 `name` / `type`）。
    url: Url,
    state: Arc<EndpointState>,
}

impl DohEndpoint {
    /// 当前是否允许尝试（熔断期内直接跳过）。
    fn usable(&self) -> bool {
        now_ms() >= self.state.disabled_until_ms.load(Ordering::Acquire)
    }

    /// JSON 路径是否处于冷却期。
    fn json_disabled(&self) -> bool {
        now_ms() < self.state.json_disabled_until_ms.load(Ordering::Acquire)
    }

    fn note_success(&self) {
        self.state.failures.store(0, Ordering::Release);
    }

    /// JSON 路径不可用（端点只讲 RFC 8484，或临时故障）：冷却期内直接走 wireformat。
    fn note_json_failure(&self, error: &str) {
        let until = now_ms() + DOH_JSON_COOLDOWN.as_millis() as u64;
        self.state
            .json_disabled_until_ms
            .store(until, Ordering::Release);
        tracing::debug!(
            "doh: {} JSON path unavailable ({error}), using wireformat for {}s",
            self.label,
            DOH_JSON_COOLDOWN.as_secs()
        );
    }

    fn note_failure(&self, error: &str) {
        let failures = self.state.failures.fetch_add(1, Ordering::AcqRel) + 1;
        if failures >= DOH_FAILURE_THRESHOLD {
            let until = now_ms() + DOH_COOLDOWN.as_millis() as u64;
            self.state.disabled_until_ms.store(until, Ordering::Release);
            tracing::warn!(
                "doh: {} failed {failures} times in a row ({error}), skipping it for {}s",
                self.label,
                DOH_COOLDOWN.as_secs()
            );
        }
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as u64)
        .unwrap_or(0)
}

fn parse_endpoint(raw: &str) -> Option<DohEndpoint> {
    let raw = raw.trim();
    if raw.is_empty() {
        return None;
    }
    let mut url = Url::parse(raw).ok()?;
    if url.scheme() != "https" {
        tracing::debug!("doh: ignoring non-https endpoint {raw}");
        return None;
    }
    let label = url.host_str()?.to_ascii_lowercase();
    // 只填域名时补默认路径，省得用户记 RFC 8484 的约定。
    if url.path().is_empty() || url.path() == "/" {
        url.set_path("/dns-query");
    }
    let key = url.to_string();
    Some(DohEndpoint {
        label,
        url,
        state: endpoint_state(&key),
    })
}

fn build_endpoints(providers: &[String]) -> Vec<DohEndpoint> {
    let mut seen = HashSet::new();
    let mut endpoints = Vec::new();
    for raw in providers {
        let Some(endpoint) = parse_endpoint(raw) else {
            continue;
        };
        if !seen.insert(endpoint.url.to_string()) {
            continue;
        }
        endpoints.push(endpoint);
    }
    endpoints
}

/// 一次解析所需的全部东西：端点表 + 查询用的 HTTP 客户端。
struct DohPlan {
    endpoints: Arc<[DohEndpoint]>,
    client: Client,
}

impl DohPlan {
    fn from_config(config: &HttpClientConfig) -> Option<Self> {
        if !config.doh_enabled {
            return None;
        }
        let endpoints = build_endpoints(&config.doh_providers);
        if endpoints.is_empty() {
            return None;
        }
        let client = doh_client(config)?;
        Some(Self {
            endpoints: endpoints.into(),
            client,
        })
    }
}

/// DoH 查询客户端缓存（按代理配置区分）。
static DOH_CLIENT_CACHE: LazyLock<Mutex<HashMap<String, Client>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn doh_client(config: &HttpClientConfig) -> Option<Client> {
    let key = format!(
        "{}|{}|{}|{}|{}",
        config.use_http_proxy,
        config.http_proxy.as_deref().unwrap_or(""),
        config.use_socks5_proxy,
        config.socks5_proxy.as_deref().unwrap_or(""),
        // 系统代理开关一变就换键，避免 DoH 查询一直粘在旧的直连/代理状态上。
        super::http::system_proxy_signature()
    );
    if let Ok(cache) = DOH_CLIENT_CACHE.lock()
        && let Some(client) = cache.get(&key)
    {
        return Some(client.clone());
    }

    // DoH 自己永远校验证书：它的价值就是完整性，不能跟着 disable_tls_verify 关掉。
    let mut builder = Client::builder()
        .timeout(DOH_QUERY_TIMEOUT)
        .pool_max_idle_per_host(4)
        .pool_idle_timeout(Duration::from_secs(90))
        .user_agent(concat!("breeze-doh/", env!("CARGO_PKG_VERSION")));
    builder = match apply_proxy_config(builder, config) {
        Ok(builder) => builder,
        Err(error) => {
            tracing::warn!("doh: failed to apply proxy config: {error}");
            return None;
        }
    };
    for (host, ips) in DOH_BOOTSTRAP {
        let addrs: Vec<SocketAddr> = ips
            .iter()
            .filter_map(|ip| ip.parse::<IpAddr>().ok())
            .map(|ip| SocketAddr::new(ip, 0))
            .collect();
        if !addrs.is_empty() {
            builder = builder.resolve_to_addrs(host, &addrs);
        }
    }

    let client = match builder.build() {
        Ok(client) => client,
        Err(error) => {
            tracing::warn!("doh: failed to build query client: {error}");
            return None;
        }
    };
    if let Ok(mut cache) = DOH_CLIENT_CACHE.lock() {
        cache.insert(key, client.clone());
    }
    Some(client)
}

/// 配置变更时清掉解析缓存。
///
/// 端点列表 / 代理一变，旧答案的「干净程度」就不可信了；熔断状态保留，
/// 免得一个坏端点被反复重试。
pub(crate) fn reset_caches() {
    if let Ok(mut guard) = IP_CACHE.lock() {
        guard.clear();
    }
    if let Ok(mut guard) = HTTPS_RR_CACHE.lock() {
        guard.clear();
    }
    if let Ok(mut guard) = DOH_CLIENT_CACHE.lock() {
        guard.clear();
    }
}

// ---------------------------------------------------------------------------
// 并发抢答
// ---------------------------------------------------------------------------

/// 所有端点并发查，谁先答用谁。
///
/// 结构化并发：所有查询都在**当前任务**里跑（`FuturesUnordered`），谁先答就返回，
/// 剩下的随它一起 drop 掉——同步取消，没有 `spawn` / `abort` 的时序问题。
///
/// 闭包返回 `Ok(Lookup::Found(v))` 表示拿到结果，`Ok(Lookup::Empty)` 表示
/// 「答了但没有需要的记录」，`Ok(Lookup::NxDomain)` 表示确定不存在。
async fn race_providers<T, F, Fut>(endpoints: &[DohEndpoint], query: F) -> Option<T>
where
    F: Fn(DohEndpoint) -> Fut,
    Fut: Future<Output = Result<Lookup<T>, String>>,
{
    let mut pending = FuturesUnordered::new();
    for endpoint in endpoints {
        if !endpoint.usable() {
            continue;
        }
        let endpoint = endpoint.clone();
        let future = query(endpoint.clone());
        pending.push(async move { (endpoint, future.await) });
    }
    if pending.is_empty() {
        return None;
    }

    let deadline = Instant::now() + DOH_RACE_TIMEOUT;
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            break;
        }
        match timeout(remaining, pending.next()).await {
            Ok(Some((endpoint, Ok(Lookup::Found(value))))) => {
                endpoint.note_success();
                return Some(value);
            }
            Ok(Some((endpoint, Ok(Lookup::Empty)))) => {
                // 有 DNS 响应但没我们要的记录：链路是通的，继续等其它端点。
                endpoint.note_success();
            }
            Ok(Some((endpoint, Ok(Lookup::NxDomain)))) => {
                // NXDOMAIN 是确定答案，换家也没用。
                endpoint.note_success();
                return None;
            }
            Ok(Some((endpoint, Err(error)))) => endpoint.note_failure(&error),
            // 所有端点都结束了。
            Ok(None) => break,
            // 整体超时。
            Err(_) => break,
        }
    }
    None
}

// ---------------------------------------------------------------------------
// A / AAAA
// ---------------------------------------------------------------------------

/// A/AAAA 缓存项。
struct IpCacheEntry {
    expires_at: Instant,
    value: DohIps,
}

static IP_CACHE: LazyLock<Mutex<HashMap<(String, IpKind), IpCacheEntry>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn ip_cache_get(host: &str, kind: IpKind) -> Option<DohIps> {
    let guard = IP_CACHE.lock().ok()?;
    let entry = guard.get(&(host.to_string(), kind))?;
    (entry.expires_at > Instant::now()).then(|| entry.value.clone())
}

fn ip_cache_put(host: &str, kind: IpKind, value: &DohIps, ttl: Duration) {
    let Ok(mut guard) = IP_CACHE.lock() else {
        return;
    };
    if guard.len() >= IP_CACHE_LIMIT {
        let now = Instant::now();
        guard.retain(|_, entry| entry.expires_at > now);
    }
    guard.insert(
        (host.to_string(), kind),
        IpCacheEntry {
            expires_at: Instant::now() + ttl,
            value: value.clone(),
        },
    );
}

fn ip_cache_put_empty(host: &str, kind: IpKind, ttl: Duration) {
    ip_cache_put(
        host,
        kind,
        &DohIps {
            ips: Vec::new(),
            ttl: 0,
        },
        ttl,
    );
}

/// 解析域名的 A/AAAA，带缓存。
async fn resolve_ips(plan: &DohPlan, host: &str) -> Option<DohIps> {
    let host = host.trim().trim_end_matches('.').to_ascii_lowercase();
    if host.is_empty() {
        return None;
    }

    let cached_a = ip_cache_get(&host, IpKind::A);
    let cached_aaaa = ip_cache_get(&host, IpKind::Aaaa);
    let mut cached_ips: Vec<IpAddr> = cached_a
        .iter()
        .chain(cached_aaaa.iter())
        .flat_map(|entry| entry.ips.iter().copied())
        .collect();
    if !cached_ips.is_empty() {
        cached_ips.sort();
        cached_ips.dedup();
        return Some(DohIps {
            ips: cached_ips,
            ttl: 0,
        });
    }
    // 两边都有负缓存：确定没有 A/AAAA，别再问了。
    if cached_a.is_some() && cached_aaaa.is_some() {
        return None;
    }

    let query = |endpoint: DohEndpoint| {
        let host = host.clone();
        let client = plan.client.clone();
        async move { query_ips_on(&endpoint, &host, &client).await }
    };
    match race_providers(&plan.endpoints, query).await {
        Some(found) => {
            let ttl = Duration::from_secs(
                found
                    .ttl
                    .clamp(IP_CACHE_POSITIVE_MIN_SECS, IP_CACHE_POSITIVE_MAX_SECS)
                    as u64,
            );
            ip_cache_put(&host, IpKind::A, &found, ttl);
            ip_cache_put(&host, IpKind::Aaaa, &found, ttl);
            Some(found)
        }
        None => {
            ip_cache_put_empty(&host, IpKind::A, IP_CACHE_NEGATIVE_TTL);
            ip_cache_put_empty(&host, IpKind::Aaaa, IP_CACHE_NEGATIVE_TTL);
            None
        }
    }
}

/// 在单个端点上同时查 A 与 AAAA，合并结果。
async fn query_ips_on(
    endpoint: &DohEndpoint,
    host: &str,
    client: &Client,
) -> Result<Lookup<DohIps>, String> {
    let (a, aaaa) = tokio::join!(
        query_ip_kind(endpoint, host, IpKind::A, client),
        query_ip_kind(endpoint, host, IpKind::Aaaa, client),
    );

    let mut ips = Vec::new();
    let mut ttl = u32::MAX;
    let mut saw_empty = false;
    let mut saw_nxdomain = false;
    let mut first_error: Option<String> = None;

    for outcome in [a, aaaa] {
        match outcome {
            Ok(Lookup::Found(found)) => {
                ips.extend(found.ips);
                ttl = ttl.min(found.ttl);
            }
            Ok(Lookup::Empty) => saw_empty = true,
            Ok(Lookup::NxDomain) => saw_nxdomain = true,
            Err(error) => {
                if first_error.is_none() {
                    first_error = Some(error);
                }
            }
        }
    }

    if !ips.is_empty() {
        ips.sort();
        ips.dedup();
        return Ok(Lookup::Found(DohIps {
            ips,
            ttl: if ttl == u32::MAX { 0 } else { ttl },
        }));
    }
    if saw_nxdomain {
        return Ok(Lookup::NxDomain);
    }
    if saw_empty {
        return Ok(Lookup::Empty);
    }
    Err(first_error.unwrap_or_else(|| "no answer".to_string()))
}

/// 查一种记录：JSON 优先，没结果再回退 RFC 8484。
async fn query_ip_kind(
    endpoint: &DohEndpoint,
    host: &str,
    kind: IpKind,
    client: &Client,
) -> Result<Lookup<DohIps>, String> {
    if !endpoint.json_disabled() {
        match query_ips_json(client, endpoint, host, kind).await {
            Ok(Lookup::Found(found)) => return Ok(Lookup::Found(found)),
            Ok(Lookup::NxDomain) => return Ok(Lookup::NxDomain),
            // JSON 答了但没有这条记录（例如类型不支持）：回退 wireformat 再确认。
            Ok(Lookup::Empty) => {}
            Err(error) => endpoint.note_json_failure(&error),
        }
    }

    match query_wire_message(client, endpoint, host, kind.record_type()).await? {
        Lookup::Found(message) => {
            let found = message_ips(&message, kind);
            if found.ips.is_empty() {
                Ok(Lookup::Empty)
            } else {
                Ok(Lookup::Found(found))
            }
        }
        Lookup::NxDomain => Ok(Lookup::NxDomain),
        Lookup::Empty => Ok(Lookup::Empty),
    }
}

#[derive(Deserialize)]
struct JsonDnsResponse {
    #[serde(rename = "Status")]
    status: u16,
    #[serde(rename = "Answer", default)]
    answer: Vec<JsonDnsAnswer>,
}

#[derive(Deserialize)]
struct JsonDnsAnswer {
    #[serde(rename = "type")]
    record_type: u16,
    #[serde(rename = "TTL", default)]
    ttl: u32,
    data: String,
}

/// JSON API（Google / 腾讯 DNSPod 的 `application/dns-json`）。
async fn query_ips_json(
    client: &Client,
    endpoint: &DohEndpoint,
    host: &str,
    kind: IpKind,
) -> Result<Lookup<DohIps>, String> {
    let mut url = endpoint.url.clone();
    url.query_pairs_mut()
        .append_pair("name", host)
        .append_pair("type", kind.json_type());

    let response = client
        .get(url)
        .header(reqwest::header::ACCEPT, "application/dns-json")
        .send()
        .await
        .map_err(|error| format!("json request failed: {error}"))?;
    if !response.status().is_success() {
        return Err(format!("json http status {}", response.status()));
    }
    let body = response
        .text()
        .await
        .map_err(|error| format!("json body failed: {error}"))?;
    parse_json_ips(&body, kind)
}

fn parse_json_ips(body: &str, kind: IpKind) -> Result<Lookup<DohIps>, String> {
    let parsed: JsonDnsResponse =
        serde_json::from_str(body).map_err(|error| format!("json decode failed: {error}"))?;
    match parsed.status {
        0 => {
            let mut ips = Vec::new();
            let mut ttl = u32::MAX;
            for answer in &parsed.answer {
                if answer.record_type != kind.as_u16() {
                    continue;
                }
                let Ok(ip) = answer.data.trim().parse::<IpAddr>() else {
                    continue;
                };
                ips.push(ip);
                ttl = ttl.min(answer.ttl);
            }
            if ips.is_empty() {
                Ok(Lookup::Empty)
            } else {
                Ok(Lookup::Found(DohIps {
                    ips,
                    ttl: if ttl == u32::MAX { 0 } else { ttl },
                }))
            }
        }
        3 => Ok(Lookup::NxDomain),
        status => Err(format!("json status {status}")),
    }
}

/// RFC 8484 wireformat 查询，返回解析后的 DNS 响应。
async fn query_wire_message(
    client: &Client,
    endpoint: &DohEndpoint,
    host: &str,
    record_type: RecordType,
) -> Result<Lookup<Message>, String> {
    let name = Name::from_ascii(host).map_err(|error| format!("invalid host: {error}"))?;
    let mut message = Message::new(next_query_id(), MessageType::Query, OpCode::Query);
    message.metadata.recursion_desired = true;
    message.add_query(Query::query(name, record_type));
    let body = message
        .to_vec()
        .map_err(|error| format!("encode query failed: {error}"))?;

    let response = client
        .post(endpoint.url.clone())
        .header(reqwest::header::CONTENT_TYPE, "application/dns-message")
        .header(reqwest::header::ACCEPT, "application/dns-message")
        .body(body)
        .send()
        .await
        .map_err(|error| format!("wire request failed: {error}"))?;
    if !response.status().is_success() {
        return Err(format!("wire http status {}", response.status()));
    }
    let body = response
        .bytes()
        .await
        .map_err(|error| format!("wire body failed: {error}"))?;
    let message =
        Message::from_vec(&body).map_err(|error| format!("decode response failed: {error}"))?;
    match message.metadata.response_code {
        ResponseCode::NoError => Ok(Lookup::Found(message)),
        ResponseCode::NXDomain => Ok(Lookup::NxDomain),
        code => Err(format!("wire response code {code:?}")),
    }
}

fn next_query_id() -> u16 {
    static QUERY_ID: AtomicU16 = AtomicU16::new(1);
    QUERY_ID.fetch_add(1, Ordering::Relaxed)
}

fn message_ips(message: &Message, kind: IpKind) -> DohIps {
    let mut ips = Vec::new();
    let mut ttl = u32::MAX;
    for record in &message.answers {
        match (kind, &record.data) {
            (IpKind::A, RData::A(A(ip))) => {
                ips.push(IpAddr::V4(*ip));
                ttl = ttl.min(record.ttl);
            }
            (IpKind::Aaaa, RData::AAAA(AAAA(ip))) => {
                ips.push(IpAddr::V6(*ip));
                ttl = ttl.min(record.ttl);
            }
            _ => {}
        }
    }
    DohIps {
        ips,
        ttl: if ttl == u32::MAX { 0 } else { ttl },
    }
}

// ---------------------------------------------------------------------------
// reqwest 解析器
// ---------------------------------------------------------------------------

/// reqwest 的自定义解析器：先 DoH，全失败回落系统解析。
#[derive(Clone)]
pub(crate) struct DohResolver {
    plan: Arc<DohPlan>,
}

impl DohResolver {
    /// 按配置构建解析器；未开启或没有可用端点时返回 `None`。
    pub(crate) fn from_config(config: &HttpClientConfig) -> Option<Self> {
        DohPlan::from_config(config).map(|plan| Self {
            plan: Arc::new(plan),
        })
    }
}

impl Resolve for DohResolver {
    fn resolve(&self, name: DnsName) -> Resolving {
        let host = name.as_str().to_string();
        let plan = self.plan.clone();
        Box::pin(async move {
            if let Some(found) = resolve_ips(&plan, &host).await {
                let addrs: Vec<SocketAddr> = found
                    .ips
                    .into_iter()
                    .map(|ip| SocketAddr::new(ip, 0))
                    .collect();
                return Ok(Box::new(addrs.into_iter()) as Addrs);
            }

            // 回落系统解析：内网域名、hosts 里写死的域名、DoH 不可用时都靠它。
            let addrs: Vec<SocketAddr> =
                tokio::net::lookup_host((host.as_str(), 0)).await?.collect();
            Ok(Box::new(addrs.into_iter()) as Addrs)
        })
    }
}

// ---------------------------------------------------------------------------
// HTTPS RR（ECH 引导）
// ---------------------------------------------------------------------------

/// `HTTPS` RR 的查询结论。
#[derive(Debug)]
enum HttpsRrLookup {
    /// 拿到了 ECHConfig 与 ipv4hint。
    Found(Vec<u8>, Vec<String>),
    /// DNS 答了，但没有 `ech`（域名没配 ECH，或者被中间设备裁剪）。
    Answered,
}

/// HTTPS RR 缓存项。`value` 为 `None` 表示负缓存（查过但没拿到）。
struct HttpsRrCacheEntry {
    expires_at: Instant,
    value: Option<(Vec<u8>, Vec<String>)>,
}

static HTTPS_RR_CACHE: LazyLock<Mutex<HashMap<String, HttpsRrCacheEntry>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn cache_get(host: &str) -> Option<Option<(Vec<u8>, Vec<String>)>> {
    let guard = HTTPS_RR_CACHE.lock().ok()?;
    let entry = guard.get(host)?;
    if entry.expires_at <= Instant::now() {
        return None;
    }
    Some(entry.value.clone())
}

fn cache_put(host: &str, ttl: Duration, value: Option<(Vec<u8>, Vec<String>)>) {
    let Ok(mut guard) = HTTPS_RR_CACHE.lock() else {
        return;
    };
    if guard.len() >= HTTPS_RR_CACHE_LIMIT {
        let now = Instant::now();
        guard.retain(|_, entry| entry.expires_at > now);
    }
    guard.insert(
        host.to_string(),
        HttpsRrCacheEntry {
            expires_at: Instant::now() + ttl,
            value,
        },
    );
}

/// 查 `HTTPS`(type 65) 记录，返回 `(ECHConfigList 原始字节, ipv4hint)`。
///
/// 带正/负缓存，请求路径上可以直接调用：命中缓存时只是一次 mutex 读。
/// 端点来自 `config`，与普通 HTTP 请求共用同一份用户配置。
pub(crate) async fn lookup_https_rr(
    host: &str,
    config: &HttpClientConfig,
) -> Option<(Vec<u8>, Vec<String>)> {
    let host = host.trim().trim_end_matches('.').to_ascii_lowercase();
    if host.is_empty() {
        return None;
    }
    if let Some(cached) = cache_get(&host) {
        return cached;
    }

    let plan = DohPlan::from_config(config)?;
    let query = |endpoint: DohEndpoint| {
        let host = host.clone();
        let client = plan.client.clone();
        async move { query_https_on(&endpoint, &host, &client).await }
    };
    let (ttl, value) = match race_providers(&plan.endpoints, query).await {
        Some(HttpsRrLookup::Found(ech, ips)) => (HTTPS_RR_POSITIVE_TTL, Some((ech, ips))),
        // 有 DNS 响应但没 ech：换家也是同样答案，缓存久一点，别每次请求都重查。
        Some(HttpsRrLookup::Answered) => (HTTPS_RR_EMPTY_TTL, None),
        None => (HTTPS_RR_NEGATIVE_TTL, None),
    };
    cache_put(&host, ttl, value.clone());
    value
}

/// `HTTPS` RR 只走 wireformat：JSON API 没有 SVCB 的稳定文本表示
/// （`doh.pub` 对 `type=HTTPS` 直接返回 `UrlParameterError`）。
async fn query_https_on(
    endpoint: &DohEndpoint,
    host: &str,
    client: &Client,
) -> Result<Lookup<HttpsRrLookup>, String> {
    match query_wire_message(client, endpoint, host, RecordType::HTTPS).await? {
        Lookup::NxDomain => Ok(Lookup::NxDomain),
        Lookup::Empty => Ok(Lookup::Empty),
        Lookup::Found(message) => {
            let found = message
                .answers
                .iter()
                .find_map(|record| extract_https_params(&record.data));
            Ok(Lookup::Found(match found {
                Some((ech, ips)) => HttpsRrLookup::Found(ech, ips),
                None => HttpsRrLookup::Answered,
            }))
        }
    }
}

/// 从 `HTTPS` RR 里取 `ech=` 与 `ipv4hint=`。
///
/// 只认 ServiceMode（`svc_priority > 0`）；AliasMode（priority 0）没有参数。
fn extract_https_params(rdata: &RData) -> Option<(Vec<u8>, Vec<String>)> {
    let RData::HTTPS(https) = rdata else {
        return None;
    };
    if https.svc_priority == 0 {
        return None;
    }

    let mut ech = None;
    let mut ips = Vec::new();
    for (key, value) in &https.svc_params {
        match (key, value) {
            (SvcParamKey::EchConfigList, SvcParamValue::EchConfigList(list)) => {
                // 含 2 字节冗余长度前缀，正好是 `rustls::pki_types::EchConfigListBytes` 要的格式。
                ech = Some(list.0.clone());
            }
            (SvcParamKey::Ipv4Hint, SvcParamValue::Ipv4Hint(hints)) => {
                ips.extend(hints.0.iter().map(|A(ip)| ip.to_string()));
            }
            _ => {}
        }
    }
    ech.map(|ech| (ech, ips))
}

#[cfg(test)]
mod tests {
    use super::*;
    use hickory_proto::rr::Name;
    use hickory_proto::rr::rdata::HTTPS;
    use hickory_proto::rr::rdata::svcb::{EchConfigList, IpHint, SVCB};
    use std::net::Ipv4Addr;

    fn https_rdata(priority: u16, params: Vec<(SvcParamKey, SvcParamValue)>) -> RData {
        RData::HTTPS(HTTPS(SVCB::new(priority, Name::root(), params)))
    }

    #[test]
    fn extracts_ech_and_ipv4_hint() {
        let rdata = https_rdata(
            1,
            vec![
                (
                    SvcParamKey::EchConfigList,
                    SvcParamValue::EchConfigList(EchConfigList(vec![0xfe, 0x0d, 0x00, 0x01])),
                ),
                (
                    SvcParamKey::Ipv4Hint,
                    SvcParamValue::Ipv4Hint(IpHint(vec![
                        A(Ipv4Addr::new(104, 21, 86, 93)),
                        A(Ipv4Addr::new(172, 67, 217, 104)),
                    ])),
                ),
            ],
        );
        let (ech, ips) = extract_https_params(&rdata).expect("should extract");
        assert_eq!(ech, vec![0xfe, 0x0d, 0x00, 0x01]);
        assert_eq!(ips, vec!["104.21.86.93", "172.67.217.104"]);
    }

    #[test]
    fn ignores_alias_mode_and_missing_ech() {
        assert!(extract_https_params(&https_rdata(0, vec![])).is_none());
        let no_ech = https_rdata(
            1,
            vec![(
                SvcParamKey::Ipv4Hint,
                SvcParamValue::Ipv4Hint(IpHint(vec![A(Ipv4Addr::new(1, 2, 3, 4))])),
            )],
        );
        assert!(extract_https_params(&no_ech).is_none());
    }

    #[test]
    fn parses_https_endpoint_and_defaults_path() {
        let endpoint = parse_endpoint("https://doh.pub").expect("endpoint should parse");
        assert_eq!(endpoint.url.as_str(), "https://doh.pub/dns-query");
        assert_eq!(endpoint.label, "doh.pub");
    }

    #[test]
    fn rejects_non_https_endpoints() {
        assert!(parse_endpoint("http://doh.pub/dns-query").is_none());
        assert!(parse_endpoint("doh.pub/dns-query").is_none());
        assert!(parse_endpoint("   ").is_none());
    }

    /// IP 形式（`https://1.12.12.12/dns-query`）不需要解析端点域名，能绕过污染。
    #[test]
    fn accepts_ip_style_endpoints() {
        let endpoint = parse_endpoint("https://1.12.12.12/dns-query").expect("ip endpoint");
        assert_eq!(endpoint.label, "1.12.12.12");
        assert_eq!(endpoint.url.as_str(), "https://1.12.12.12/dns-query");
    }

    #[test]
    fn default_providers_are_valid_https_endpoints() {
        for raw in DEFAULT_DOH_PROVIDERS {
            let endpoint = parse_endpoint(raw).unwrap_or_else(|| panic!("{raw} should parse"));
            assert_eq!(endpoint.url.scheme(), "https");
        }
    }

    #[test]
    fn dedupes_endpoints() {
        let providers = vec![
            "https://doh.pub/dns-query".to_string(),
            "https://doh.pub/dns-query".to_string(),
            "https://dns.google/dns-query".to_string(),
        ];
        assert_eq!(build_endpoints(&providers).len(), 2);
    }

    #[test]
    fn parses_json_answers() {
        let body = r#"{"Status":0,"Answer":[
            {"name":"www.google.com.","type":1,"TTL":104,"data":"142.251.154.119"},
            {"name":"www.google.com.","type":1,"TTL":104,"data":"142.251.157.119"},
            {"name":"www.google.com.","type":28,"TTL":104,"data":"2001:4860:482d:7700::"}
        ]}"#;

        let Lookup::Found(found) = parse_json_ips(body, IpKind::A).expect("parse A") else {
            panic!("expected A records");
        };
        assert_eq!(found.ips.len(), 2);
        assert_eq!(found.ttl, 104);

        let Lookup::Found(found) = parse_json_ips(body, IpKind::Aaaa).expect("parse AAAA") else {
            panic!("expected AAAA records");
        };
        assert_eq!(
            found.ips,
            vec!["2001:4860:482d:7700::".parse::<IpAddr>().unwrap()]
        );

        assert!(matches!(
            parse_json_ips(r#"{"Status":3}"#, IpKind::A).expect("nxdomain"),
            Lookup::NxDomain
        ));
        assert!(matches!(
            parse_json_ips(r#"{"Status":0}"#, IpKind::A).expect("empty"),
            Lookup::Empty
        ));
        // 腾讯对不支持的 type 返回 {"code":"UrlParameterError"}，必须当成 JSON 失败。
        assert!(parse_json_ips(r#"{"code":"UrlParameterError"}"#, IpKind::A).is_err());
    }

    /// 诊断用：逐端点打印结果（墙内 CF / Google 预期失败，不算测试失败）。
    /// `cargo test -- --ignored --nocapture doh_providers_live_smoke`
    #[tokio::test]
    #[ignore]
    async fn doh_providers_live_smoke() {
        let config = HttpClientConfig::default();
        let plan = DohPlan::from_config(&config).expect("plan");
        for endpoint in plan.endpoints.iter() {
            let result = query_ips_on(endpoint, "www.google.com", &plan.client).await;
            println!("{}: {result:?}", endpoint.label);
        }
    }

    /// 联网冒烟：默认端点并发 → 应能拿到 ECHConfig。
    /// `cargo test -- --ignored --nocapture doh_live_smoke`
    #[tokio::test]
    #[ignore]
    async fn doh_live_smoke() {
        let config = HttpClientConfig::default();
        let (ech, ips) = lookup_https_rr("picaapi.part26.art", &config)
            .await
            .expect("chain should return ech");
        println!("chain: ech_len={} ips={ips:?}", ech.len());
        assert!(ech.len() > 8);
        assert!(!ips.is_empty());
    }
}
