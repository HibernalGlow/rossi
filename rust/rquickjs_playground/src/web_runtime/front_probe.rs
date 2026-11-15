//! 前置 IP 延迟探测。
//!
//! 插件侧入口是 `fronting.probe(payload, { signal })`（`js/35_fronting.js`），
//! 下面是它封装的内部实现 `__http_probe_front_hosts(JSON.stringify({...}))`。
//! 设计目标是 **不暴露原始 TCP/UDP**，只提供「给一个域名 + 一组 IP，量一下延迟」：
//!
//! - `host` 必须是合法域名（用于 `Host` 头 / SNI），不必先写进前置表；
//! - `ips` 可选：缺省测当前前置表里该 host 的全部 IP；显式传入时直接测这些 IP，
//!   **不要求先登记**，插件可以先测再决定写回哪几个；
//! - 只允许 `http`/`https`，端口固定 80/443，路径固定 `/`，方法固定 `HEAD`；
//! - 不发送任何自定义 header/body，不读取响应体；
//! - 返回每个 IP 的 `ttfbMs`（TCP + TLS + 服务端处理 + 首字节）、`avgMs`、
//!   采样明细与丢包率。
//!
//! 之所以不要求先登记：插件本来就能用 `fetch` 直接请求任意公网 IP，登记限制
//! 只是徒增一步「先写进表、测完再改表」的往返，并不能真的拦住什么。真正的
//! 约束是下面这些资源限制，以及保留地址段的拒绝。
//!
//! # 资源限制
//!
//! 配额**按插件（runtime）隔离**，插件之间互不影响：
//!
//! - 单插件并发 [`PROBE_PER_PLUGIN_CONCURRENCY`] 个采样；
//! - 单插件同时 [`PROBE_MAX_ACTIVE_BATCHES`] 个批次；
//! - 单插件批次令牌桶：容量 [`PROBE_BATCH_BUCKET_CAPACITY`]，每
//!   [`PROBE_BATCH_REFILL_PER_SEC`] 秒补一个，超限返回 `probe-rate-limited` + `retryAfterMs`。
//!
//! 刻意**不设全局并发上限**：探测是插件自己的行为，加全局闸门只会让「A 插件在探测」
//! 变成「B 插件探测失败」，凭空制造跨插件干扰。每个插件都被自己的并发与令牌桶
//! 限住了，总量随活跃插件数线性增长，不会失控。

use std::collections::HashMap;
use std::sync::{Arc, LazyLock, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Context as _, Result as AnyResult};
use reqwest::Client;
use reqwest::redirect::Policy;
use reqwest_middleware::ClientWithMiddleware;
use rquickjs::{Ctx, Promise, Value as QjsValue};
use serde::Deserialize;
use serde_json::json;
use tokio::sync::Semaphore;
use tokio::task::JoinSet;

use super::fronting::{front_host_ips, validate_probe_ip};
use super::http::{
    HttpClientConfig, apply_proxy_config, next_http_request_id, register_http_cancel,
    unregister_http_cancel, worker_http_config, wrap_http_client,
};

/// 单次探测最多测试多少个 IP。
const PROBE_MAX_IPS: usize = 32;
/// 默认并发数。
const PROBE_DEFAULT_CONCURRENCY: usize = 4;
/// 单次探测的最大并发数。与单插件并发配额对齐，避免出现「设了也用不上」的值。
const PROBE_MAX_CONCURRENCY: usize = PROBE_PER_PLUGIN_CONCURRENCY;
/// 默认单 IP 超时。
const PROBE_DEFAULT_TIMEOUT_MS: u64 = 3_000;
/// 单 IP 超时下限。
const PROBE_MIN_TIMEOUT_MS: u64 = 500;
/// 单 IP 超时上限。
const PROBE_MAX_TIMEOUT_MS: u64 = 10_000;
/// 默认采样次数。
const PROBE_DEFAULT_SAMPLES: usize = 1;
/// 单 IP 最大采样次数。
const PROBE_MAX_SAMPLES: usize = 3;
/// 连续失败多少次后放弃该 IP 的剩余采样。
///
/// 设 2 而不是 1：单次失败可能只是抖动，但连续两次失败基本可以判定不可用，
/// 继续采样只会白等 `timeout`。
const PROBE_MAX_CONSECUTIVE_FAILURES: usize = 2;
/// 整批探测的截止时间下限。
const PROBE_MIN_BATCH_MS: u64 = 15_000;
/// 整批探测的截止时间上限，避免参数组合把批次拖到分钟级。
const PROBE_MAX_BATCH_MS: u64 = 30_000;
/// 单个插件同时进行的探测采样数。
///
/// 这是唯一的并发闸门：按插件隔离，不设全局上限。
const PROBE_PER_PLUGIN_CONCURRENCY: usize = 4;
/// 每个插件同时进行的探测批次上限。
const PROBE_MAX_ACTIVE_BATCHES: usize = 2;
/// 每插件批次令牌桶容量（允许连续发起的批次数）。
const PROBE_BATCH_BUCKET_CAPACITY: f64 = 2.0;
/// 每插件批次令牌补充速率（每秒），即 5 秒补一个。
const PROBE_BATCH_REFILL_PER_SEC: f64 = 0.2;
/// 等待探测并发许可的最长时间。
const PROBE_PERMIT_WAIT_MS: u64 = 5_000;
/// 插件探测状态空闲多久后回收。
///
/// 不能「批次一结束就回收」：那样令牌桶会跟着重置，限频形同虚设。
const PROBE_STATE_IDLE_TTL: Duration = Duration::from_secs(120);

/// 单个插件（runtime）的探测状态。
struct RuntimeProbeState {
    /// 正在进行的批次数。
    active_batches: usize,
    /// 插件级并发配额。
    sem: Arc<Semaphore>,
    /// 批次令牌桶：限制批次发起频率，防止插件背靠背刷探测。
    tokens: f64,
    last_refill: Instant,
    /// 最后一次有批次结束的时刻，用于回收空闲状态。
    last_activity: Instant,
}

impl RuntimeProbeState {
    fn new() -> Self {
        Self {
            active_batches: 0,
            sem: Arc::new(Semaphore::new(PROBE_PER_PLUGIN_CONCURRENCY)),
            tokens: PROBE_BATCH_BUCKET_CAPACITY,
            last_refill: Instant::now(),
            last_activity: Instant::now(),
        }
    }

    /// 按流逝时间补充令牌。
    fn refill(&mut self, now: Instant) {
        let elapsed = now
            .saturating_duration_since(self.last_refill)
            .as_secs_f64();
        if elapsed > 0.0 {
            self.tokens = (self.tokens + elapsed * PROBE_BATCH_REFILL_PER_SEC)
                .min(PROBE_BATCH_BUCKET_CAPACITY);
            self.last_refill = now;
        }
    }

    /// 按流逝时间补充令牌并尝试取一个。
    ///
    /// 成功返回 `Ok(())`；令牌不足返回 `Err(需要等待的毫秒数)`。
    fn try_take_token(&mut self) -> Result<(), u64> {
        self.refill(Instant::now());
        if self.tokens >= 1.0 {
            self.tokens -= 1.0;
            return Ok(());
        }
        let missing = 1.0 - self.tokens;
        let wait_ms = (missing / PROBE_BATCH_REFILL_PER_SEC * 1000.0).ceil() as u64;
        Err(wait_ms.max(1))
    }
}

static RUNTIME_PROBE_STATES: LazyLock<Mutex<HashMap<String, RuntimeProbeState>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// 批次准入结果。
enum ProbeAdmission {
    /// 准入成功，持有守卫期间占用一个批次槽位。
    Admitted(ActiveProbeGuard),
    /// 同时进行的批次太多。
    Busy,
    /// 批次发起太频繁，附带建议的重试间隔。
    RateLimited(u64),
}

/// 批次守卫：Drop 时归还槽位。
///
/// 守卫活到 `run_probe_batch` 结束，所以回收状态时不会有残留任务持有旧信号量。
/// 状态本身不在这里回收，而是由 `acquire` 按 [`PROBE_STATE_IDLE_TTL`] 清扫：
/// 批次一结束就回收会把令牌桶一起重置，限频就失效了。
struct ActiveProbeGuard {
    runtime: String,
    /// 插件级并发配额，交给批次内的采样共享。
    sem: Arc<Semaphore>,
}

impl ActiveProbeGuard {
    fn acquire(runtime: &str) -> ProbeAdmission {
        let mut states = match RUNTIME_PROBE_STATES.lock() {
            Ok(states) => states,
            Err(_) => return ProbeAdmission::Busy,
        };
        // 顺手清掉长期空闲的插件状态。插件数量有限，O(n) 扫描代价可忽略。
        let now = Instant::now();
        states.retain(|_, state| {
            state.active_batches > 0
                || now.saturating_duration_since(state.last_activity) < PROBE_STATE_IDLE_TTL
        });
        let state = states
            .entry(runtime.to_string())
            .or_insert_with(RuntimeProbeState::new);
        if state.active_batches >= PROBE_MAX_ACTIVE_BATCHES {
            return ProbeAdmission::Busy;
        }
        if let Err(retry_after_ms) = state.try_take_token() {
            return ProbeAdmission::RateLimited(retry_after_ms);
        }
        state.active_batches += 1;
        ProbeAdmission::Admitted(Self {
            runtime: runtime.to_string(),
            sem: Arc::clone(&state.sem),
        })
    }
}

impl Drop for ActiveProbeGuard {
    fn drop(&mut self) {
        let mut states = match RUNTIME_PROBE_STATES.lock() {
            Ok(states) => states,
            Err(_) => return,
        };
        if let Some(state) = states.get_mut(&self.runtime) {
            state.active_batches = state.active_batches.saturating_sub(1);
            state.last_activity = Instant::now();
        }
    }
}

#[derive(Debug, Deserialize)]
struct ProbeRequest {
    host: String,
    #[serde(default)]
    ips: Option<Vec<String>>,
    #[serde(default)]
    scheme: Option<String>,
    #[serde(default, rename = "timeoutMs", alias = "timeout_ms")]
    timeout_ms: Option<u64>,
    #[serde(default)]
    concurrency: Option<usize>,
    #[serde(default)]
    samples: Option<usize>,
}

#[derive(Debug, Default, serde::Serialize)]
struct ProbeResult {
    ip: String,
    ok: bool,
    status: Option<u16>,
    /// 最快一次采样的耗时（毫秒）。
    #[serde(rename = "ttfbMs")]
    ttfb_ms: Option<u64>,
    /// 成功采样的平均耗时（毫秒）。
    #[serde(rename = "avgMs")]
    avg_ms: Option<u64>,
    #[serde(rename = "samplesMs")]
    samples_ms: Vec<u64>,
    /// 实际发出的采样次数。
    #[serde(rename = "samplesSent")]
    samples_sent: usize,
    /// 成功的采样次数。
    #[serde(rename = "samplesReceived")]
    samples_received: usize,
    /// 丢包率，0.0 ~ 1.0，保留两位小数。
    #[serde(rename = "lossRate")]
    loss_rate: f64,
    error: Option<String>,
}

impl ProbeResult {
    fn new(ip: String) -> Self {
        Self {
            ip,
            ..Default::default()
        }
    }

    /// 构造一个「没发出任何采样就失败」的结果。
    fn failed(ip: String, error: &str) -> Self {
        Self {
            ip,
            error: Some(error.to_string()),
            ..Default::default()
        }
    }

    /// 补齐派生字段（`ok` / `ttfbMs` / `avgMs` / `lossRate`）。
    fn finish(mut self) -> Self {
        self.samples_received = self.samples_ms.len();
        self.ok = self.samples_received > 0;
        self.ttfb_ms = self.samples_ms.iter().min().copied();
        self.avg_ms = if self.samples_ms.is_empty() {
            None
        } else {
            let total: u64 = self.samples_ms.iter().sum();
            Some(total / self.samples_ms.len() as u64)
        };
        self.loss_rate = if self.samples_sent == 0 {
            0.0
        } else {
            let lost = self.samples_sent.saturating_sub(self.samples_received);
            let rate = lost as f64 / self.samples_sent as f64;
            (rate * 100.0).round() / 100.0
        };
        if self.ok {
            self.error = None;
        }
        self
    }
}

fn probe_error(error: &str) -> String {
    json!({ "ok": false, "error": error }).to_string()
}

fn probe_error_with_ip(error: &str, ip: &str) -> String {
    json!({ "ok": false, "error": error, "ip": ip }).to_string()
}

/// 规范化并校验探测用的 host。
///
/// 只接受普通域名：拒绝 IP 字面量、端口、路径、空白、单标签主机和 `localhost`。
fn normalize_probe_host(raw: &str) -> Option<String> {
    let host = raw.trim().trim_end_matches('.').to_ascii_lowercase();
    if host.is_empty() || host.len() > 253 || !host.is_ascii() {
        return None;
    }
    if host.contains('/') || host.contains(':') || host.contains(char::is_whitespace) {
        return None;
    }
    match url::Host::parse(&host) {
        Ok(url::Host::Domain(domain)) => {
            if domain == "localhost" || !domain.contains('.') {
                return None;
            }
            for label in domain.split('.') {
                if label.is_empty()
                    || label.len() > 63
                    || label.starts_with('-')
                    || label.ends_with('-')
                {
                    return None;
                }
            }
            Some(domain)
        }
        _ => None,
    }
}

fn probe_client_cache_key(config: &HttpClientConfig) -> String {
    format!(
        "{}|{}|{}|{}|{}",
        config.use_http_proxy,
        config.use_socks5_proxy,
        config.http_proxy.as_deref().unwrap_or(""),
        config.socks5_proxy.as_deref().unwrap_or(""),
        super::http::system_proxy_signature()
    )
}

/// 探测专用客户端。
///
/// 与前置客户端一致：HTTP/1.1、不跟随重定向、跳过证书校验、复用代理配置。
/// 额外关闭连接池，保证每个采样都是新的 TCP/TLS 连接，测到的是冷启动延迟。
fn build_probe_client(config: &HttpClientConfig) -> AnyResult<ClientWithMiddleware> {
    let mut builder = Client::builder()
        .http1_only()
        .redirect(Policy::none())
        .danger_accept_invalid_certs(true)
        .pool_max_idle_per_host(0);
    builder = apply_proxy_config(builder, config)?;
    let client = builder
        .build()
        .context(crate::tr!("failed-to-create-http-client"))?;
    Ok(wrap_http_client(client))
}

fn cached_probe_client(config: &HttpClientConfig) -> AnyResult<ClientWithMiddleware> {
    static PROBE_CLIENT_CACHE: LazyLock<Mutex<HashMap<String, ClientWithMiddleware>>> =
        LazyLock::new(|| Mutex::new(HashMap::new()));
    let key = probe_client_cache_key(config);
    let mut guard = match PROBE_CLIENT_CACHE.lock() {
        Ok(guard) => guard,
        Err(_) => return build_probe_client(config),
    };
    if let Some(client) = guard.get(&key) {
        return Ok(client.clone());
    }
    let client = build_probe_client(config)?;
    guard.insert(key, client.clone());
    Ok(client)
}

fn classify_probe_error(error: &reqwest_middleware::Error) -> &'static str {
    if error.is_timeout() {
        "timeout"
    } else if error.is_connect() {
        "connect"
    } else if error.is_request() {
        "request"
    } else {
        "other"
    }
}

/// 一批探测的固定参数。
#[derive(Debug, Clone)]
struct ProbeBatchConfig {
    /// 探测协议，决定端口（https=443 / http=80）。
    scheme: &'static str,
    /// 还原到 `Host` 头的目标域名。
    host: String,
    /// 单次采样超时。
    timeout: Duration,
    /// 批次内并发。
    concurrency: usize,
    /// 单 IP 采样次数。
    samples: usize,
}

/// 探测单个 IP。`url` 由调用方构造（生产路径是 `scheme://ip/`，测试可直接传本地地址）。
///
/// 采样策略：连续失败 [`PROBE_MAX_CONSECUTIVE_FAILURES`] 次才放弃剩余采样，
/// 这样偶发抖动不会被误判成完全不可用，同时死 IP 也不会白等 `samples * timeout`。
async fn probe_one(
    client: ClientWithMiddleware,
    plugin_sem: Arc<Semaphore>,
    ip: String,
    url: String,
    config: &ProbeBatchConfig,
) -> ProbeResult {
    let mut result = ProbeResult::new(ip);
    let mut consecutive_failures = 0usize;

    for _ in 0..config.samples {
        // 并发配额按插件隔离，插件之间不互相排队。
        let plugin_permit = match tokio::time::timeout(
            Duration::from_millis(PROBE_PERMIT_WAIT_MS),
            plugin_sem.clone().acquire_owned(),
        )
        .await
        {
            Ok(Ok(permit)) => permit,
            _ => {
                // 拿不到配额是本机资源问题，不算网络丢包，也不消耗剩余采样。
                result.error = Some("busy".to_string());
                break;
            }
        };

        let started = Instant::now();
        let outcome = tokio::time::timeout(
            config.timeout,
            client.head(&url).header("Host", &config.host).send(),
        )
        .await;
        let elapsed = started.elapsed();
        drop(plugin_permit);

        result.samples_sent += 1;
        match outcome {
            Ok(Ok(response)) => {
                result.samples_ms.push(elapsed.as_millis() as u64);
                if result.status.is_none() {
                    result.status = Some(response.status().as_u16());
                }
                consecutive_failures = 0;
                // 不读 body。HEAD 响应通常没有 body；丢弃 response 即关闭连接。
            }
            Ok(Err(error)) => {
                consecutive_failures += 1;
                result.error = Some(classify_probe_error(&error).to_string());
            }
            Err(_) => {
                consecutive_failures += 1;
                result.error = Some("timeout".to_string());
            }
        }

        if consecutive_failures >= PROBE_MAX_CONSECUTIVE_FAILURES {
            break;
        }
    }

    result.finish()
}

/// 按 IP 数、并发、超时、采样次数推算整批截止时间。
///
/// 固定 15s 在「32 个 IP × 3s 超时 × 默认并发 4」下需要 24s，尾部 IP 会被
/// 误判成 `batch-timeout`，所以按需放大（下限 15s、上限 30s）。
fn batch_deadline(ips: usize, concurrency: usize, timeout: Duration, samples: usize) -> Duration {
    let waves = ips.div_ceil(concurrency.max(1)).max(1) as u32;
    let per_wave = timeout.saturating_mul(samples.max(1) as u32);
    let needed = per_wave.saturating_mul(waves) + Duration::from_secs(1);
    needed.clamp(
        Duration::from_millis(PROBE_MIN_BATCH_MS),
        Duration::from_millis(PROBE_MAX_BATCH_MS),
    )
}

async fn run_probe_batch(
    client: ClientWithMiddleware,
    plugin_sem: Arc<Semaphore>,
    ips: Vec<String>,
    config: ProbeBatchConfig,
) -> Vec<ProbeResult> {
    let sem = Arc::new(Semaphore::new(config.concurrency));
    let mut set = JoinSet::new();

    for ip in ips.iter().cloned() {
        let client = client.clone();
        let plugin_sem = Arc::clone(&plugin_sem);
        let config = config.clone();
        let sem = Arc::clone(&sem);
        // IPv6 字面量必须加方括号，否则 URL 解析会把第一个 `:` 之后当端口。
        let url = if ip.contains(':') {
            format!("{}://[{ip}]/", config.scheme)
        } else {
            format!("{}://{ip}/", config.scheme)
        };
        set.spawn(async move {
            let _permit = match sem.acquire_owned().await {
                Ok(permit) => permit,
                Err(_) => return ProbeResult::failed(ip, "busy"),
            };
            probe_one(client, plugin_sem, ip, url, &config).await
        });
    }

    let deadline = Instant::now()
        + batch_deadline(
            ips.len(),
            config.concurrency,
            config.timeout,
            config.samples,
        );
    let mut results = Vec::new();
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            set.abort_all();
            break;
        }
        match tokio::time::timeout(remaining, set.join_next()).await {
            Ok(Some(Ok(result))) => results.push(result),
            Ok(Some(Err(_))) => {}
            Ok(None) => break,
            Err(_) => {
                set.abort_all();
                break;
            }
        }
    }
    while set.join_next().await.is_some() {}
    results
}

async fn run_probe(payload: String, runtime: String, config: HttpClientConfig) -> String {
    let request: ProbeRequest = match serde_json::from_str(&payload) {
        Ok(request) => request,
        Err(_) => return probe_error("invalid-json"),
    };

    let host = match normalize_probe_host(&request.host) {
        Some(host) => host,
        None => return probe_error("invalid-host"),
    };

    let scheme = match request
        .scheme
        .as_deref()
        .unwrap_or("https")
        .trim()
        .to_ascii_lowercase()
        .as_str()
    {
        "https" => "https",
        "http" => "http",
        _ => return probe_error("invalid-scheme"),
    };

    let timeout_ms = request
        .timeout_ms
        .unwrap_or(PROBE_DEFAULT_TIMEOUT_MS)
        .clamp(PROBE_MIN_TIMEOUT_MS, PROBE_MAX_TIMEOUT_MS);
    let concurrency = request
        .concurrency
        .unwrap_or(PROBE_DEFAULT_CONCURRENCY)
        .clamp(1, PROBE_MAX_CONCURRENCY);
    let samples = request
        .samples
        .unwrap_or(PROBE_DEFAULT_SAMPLES)
        .clamp(1, PROBE_MAX_SAMPLES);

    let ips = match request.ips {
        Some(raw_ips) => {
            let mut selected: Vec<String> = Vec::new();
            for raw in raw_ips {
                let ip = match validate_probe_ip(&raw, config.allow_private_network) {
                    Some(ip) => ip,
                    None => return probe_error_with_ip("invalid-ip", raw.trim()),
                };
                if !selected.iter().any(|candidate| candidate == &ip) {
                    selected.push(ip);
                }
            }
            selected
        }
        // 没传 `ips` 时退回到前置表：这是「测一下我登记的那些 IP」的常见用法。
        None => match front_host_ips(&runtime, &host) {
            Some(ips) if !ips.is_empty() => ips,
            _ => return probe_error("host-not-registered"),
        },
    };

    if ips.is_empty() {
        return probe_error("no-ips");
    }
    if ips.len() > PROBE_MAX_IPS {
        return probe_error("too-many-ips");
    }

    let guard = match ActiveProbeGuard::acquire(&runtime) {
        ProbeAdmission::Admitted(guard) => guard,
        ProbeAdmission::Busy => return probe_error("probe-busy"),
        ProbeAdmission::RateLimited(retry_after_ms) => {
            return json!({
                "ok": false,
                "error": "probe-rate-limited",
                "retryAfterMs": retry_after_ms,
            })
            .to_string();
        }
    };

    let client = match cached_probe_client(&config) {
        Ok(client) => client,
        Err(error) => {
            tracing::warn!("front probe: failed to build client: {error:#}");
            return probe_error("client-build-failed");
        }
    };

    let results = run_probe_batch(
        client,
        Arc::clone(&guard.sem),
        ips.clone(),
        ProbeBatchConfig {
            scheme,
            host: host.clone(),
            timeout: Duration::from_millis(timeout_ms),
            concurrency,
            samples,
        },
    )
    .await;

    let mut by_ip: HashMap<String, ProbeResult> = results
        .into_iter()
        .map(|result| (result.ip.clone(), result))
        .collect();
    let ordered: Vec<ProbeResult> = ips
        .into_iter()
        .map(|ip| {
            by_ip
                .remove(&ip)
                .unwrap_or_else(|| ProbeResult::failed(ip, "batch-timeout"))
        })
        .collect();

    json!({
        "ok": true,
        "host": host,
        "scheme": scheme,
        "results": ordered,
    })
    .to_string()
}

/// JS 入口：`__http_probe_front_hosts(payloadJson)`，返回 Promise<string>。
///
/// Promise 上带 `__hostRequestId`，可复用 `__http_request_cancel(id)` 取消。
pub fn probe_front_hosts(ctx: Ctx<'_>, payload: String) -> rquickjs::Result<QjsValue<'_>> {
    let runtime = super::runtime_scope(&ctx);
    let id = next_http_request_id();
    let cancel_rx = register_http_cancel(id);
    let work_cfg = worker_http_config();
    let cleanup_id = id;

    let work = async move {
        let result = tokio::select! {
            biased;
            _ = cancel_rx => {
                json!({
                    "ok": false,
                    "canceled": true,
                    "error": "request-was-canceled"
                })
                .to_string()
            }
            result = run_probe(payload, runtime, work_cfg) => result,
        };
        unregister_http_cancel(cleanup_id);
        result
    };

    let (result_tx, result_rx) = tokio::sync::oneshot::channel::<String>();
    crate::global_runtime().spawn(async move {
        let _ = result_tx.send(work.await);
    });

    let future = async move {
        result_rx
            .await
            .unwrap_or_else(|_| probe_error("request-execution-cancelled"))
    };

    let promise = Promise::wrap_future(&ctx, future)?;
    let obj = promise.into_inner();
    if let Err(error) = obj.set("__hostRequestId", id) {
        unregister_http_cancel(id);
        return Err(error);
    }
    Ok(obj.into_value())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    /// 每个用例用独立的 runtime 名，天然隔离，不需要全局锁。
    fn runtime_for(case: &str) -> String {
        format!("probe-test-{case}")
    }

    fn register_host(runtime: &str, host: &str, ips: &[&str]) {
        crate::web_runtime::fronting::set_front_hosts(runtime, json!({ host: ips }).to_string());
    }

    #[test]
    fn normalize_host_accepts_domains() {
        assert_eq!(
            normalize_probe_host("E-Hentai.org."),
            Some("e-hentai.org".to_string())
        );
        assert_eq!(
            normalize_probe_host("s.exhentai.org"),
            Some("s.exhentai.org".to_string())
        );
    }

    #[test]
    fn normalize_host_rejects_ip_and_localhost() {
        for host in [
            "1.2.3.4",
            "::1",
            "localhost",
            "example.com:443",
            "https://example.com",
            "",
            "example",
        ] {
            assert!(
                normalize_probe_host(host).is_none(),
                "{host} should be rejected"
            );
        }
    }

    /// 批截止必须随工作量放大，否则默认参数下尾部 IP 会被误判成 batch-timeout。
    #[test]
    fn batch_deadline_scales_with_workload() {
        // 32 IP / 并发 4 / 3s / 1 次采样 = 8 波 × 3s = 24s，超过旧的固定 15s。
        assert_eq!(
            batch_deadline(32, 4, Duration::from_secs(3), 1),
            Duration::from_secs(25)
        );
        // 小批量仍保底 15s。
        assert_eq!(
            batch_deadline(2, 4, Duration::from_secs(3), 1),
            Duration::from_millis(PROBE_MIN_BATCH_MS)
        );
        // 极端参数组合被 30s 上限截断。
        assert_eq!(
            batch_deadline(32, 1, Duration::from_secs(10), 3),
            Duration::from_millis(PROBE_MAX_BATCH_MS)
        );
    }

    /// 批次槽位先于令牌桶生效；槽位空出来后令牌桶继续限频。
    #[test]
    fn rate_limit_returns_retry_after() {
        let runtime = runtime_for("rate-limit");
        let first = ActiveProbeGuard::acquire(&runtime);
        let second = ActiveProbeGuard::acquire(&runtime);
        assert!(matches!(first, ProbeAdmission::Admitted(_)));
        assert!(matches!(second, ProbeAdmission::Admitted(_)));

        // 槽位已满，这里先撞到批次上限。
        assert!(matches!(
            ActiveProbeGuard::acquire(&runtime),
            ProbeAdmission::Busy
        ));

        drop(first);
        drop(second);

        // 槽位空出来了，但两个令牌已经用完。
        match ActiveProbeGuard::acquire(&runtime) {
            ProbeAdmission::RateLimited(retry_after_ms) => {
                assert!(retry_after_ms > 0, "retryAfterMs should be positive");
                assert!(
                    retry_after_ms <= 5_000,
                    "retryAfterMs should not exceed one refill interval"
                );
            }
            _ => panic!("should be rate limited after draining the bucket"),
        }
    }

    /// 空闲状态会被清扫，但令牌桶不能在批次结束时跟着重置。
    #[test]
    fn stale_states_are_swept_on_acquire() {
        let stale = runtime_for("stale");
        let fresh = runtime_for("fresh");

        drop(ActiveProbeGuard::acquire(&stale));
        assert!(
            RUNTIME_PROBE_STATES.lock().unwrap().contains_key(&stale),
            "state should survive a finished batch so the bucket keeps throttling"
        );

        if let Some(state) = RUNTIME_PROBE_STATES.lock().unwrap().get_mut(&stale) {
            state.last_activity = Instant::now() - PROBE_STATE_IDLE_TTL - Duration::from_secs(1);
        }

        let guard = ActiveProbeGuard::acquire(&fresh);
        assert!(
            !RUNTIME_PROBE_STATES.lock().unwrap().contains_key(&stale),
            "idle state should be swept on the next acquire"
        );
        drop(guard);
    }

    #[test]
    fn active_batch_limit_is_per_runtime() {
        let runtime_a = runtime_for("batches-a");
        let runtime_b = runtime_for("batches-b");
        let a1 = ActiveProbeGuard::acquire(&runtime_a);
        let a2 = ActiveProbeGuard::acquire(&runtime_a);
        assert!(matches!(a1, ProbeAdmission::Admitted(_)));
        assert!(matches!(a2, ProbeAdmission::Admitted(_)));

        // A 占满自己的批次槽位不应该影响 B。
        let b1 = ActiveProbeGuard::acquire(&runtime_b);
        assert!(matches!(b1, ProbeAdmission::Admitted(_)));

        drop(a1);
        drop(a2);
        drop(b1);
    }

    /// 并发配额按插件隔离：A 占满自己的许可不影响 B。
    ///
    /// 这条用例锁住「不设全局并发上限」这个决定——如果哪天又加回全局闸门，
    /// B 在 A 吃满配额时就拿不到许可，这里会失败。
    #[tokio::test]
    async fn concurrency_quota_is_per_runtime() {
        let runtime_a = runtime_for("concurrency-a");
        let runtime_b = runtime_for("concurrency-b");
        let a = match ActiveProbeGuard::acquire(&runtime_a) {
            ProbeAdmission::Admitted(guard) => guard,
            _ => panic!("A 应该被准入"),
        };
        let b = match ActiveProbeGuard::acquire(&runtime_b) {
            ProbeAdmission::Admitted(guard) => guard,
            _ => panic!("B 应该被准入"),
        };

        // A 把自己的配额全部拿走。
        let mut held = Vec::new();
        for _ in 0..PROBE_PER_PLUGIN_CONCURRENCY {
            held.push(a.sem.clone().acquire_owned().await.expect("A permit"));
        }
        assert_eq!(a.sem.available_permits(), 0);

        // B 的配额完全不受影响。
        assert_eq!(b.sem.available_permits(), PROBE_PER_PLUGIN_CONCURRENCY);
        let permit = b.sem.clone().acquire_owned().await.expect("B permit");
        drop(permit);

        drop(held);
        drop(a);
        drop(b);
    }

    #[tokio::test]
    async fn rejects_unregistered_host() {
        let runtime = runtime_for("unregistered");
        crate::web_runtime::fronting::clear_front_hosts(&runtime);
        let result = run_probe(
            json!({ "host": "example.com" }).to_string(),
            runtime,
            HttpClientConfig::default(),
        )
        .await;
        let parsed: Value = serde_json::from_str(&result).expect("probe result should be JSON");
        assert_eq!(parsed["ok"], json!(false));
        assert_eq!(parsed["error"], json!("host-not-registered"));
    }

    /// 显式传入的 IP 不要求先写进前置表（插件可以「先测再写回」）。
    ///
    /// 用本机地址 + `allow_private_network` 避免真的外连：连接会被立刻拒绝，
    /// 但批次本身正常跑完，足以证明校验环节放行了未登记的 IP。
    #[tokio::test]
    async fn accepts_ip_not_in_table() {
        let runtime = runtime_for("ip-not-registered");
        crate::web_runtime::fronting::clear_front_hosts(&runtime);
        register_host(&runtime, "e-hentai.org", &["172.66.132.196"]);

        let config = HttpClientConfig {
            allow_private_network: true,
            ..HttpClientConfig::default()
        };
        let result = run_probe(
            json!({
                "host": "e-hentai.org",
                "ips": ["127.0.0.1"],
                "timeoutMs": 500,
            })
            .to_string(),
            runtime.clone(),
            config,
        )
        .await;
        let parsed: Value = serde_json::from_str(&result).expect("probe result should be JSON");
        assert_eq!(parsed["ok"], json!(true), "unexpected: {parsed}");
        assert_eq!(parsed["results"][0]["ip"], json!("127.0.0.1"));
        crate::web_runtime::fronting::clear_front_hosts(&runtime);
    }

    #[tokio::test]
    async fn rejects_invalid_scheme_and_reserved_ip() {
        let runtime = runtime_for("invalid-scheme");
        crate::web_runtime::fronting::clear_front_hosts(&runtime);
        register_host(&runtime, "e-hentai.org", &["172.66.132.196"]);

        let bad_scheme = run_probe(
            json!({ "host": "e-hentai.org", "scheme": "ftp" }).to_string(),
            runtime.clone(),
            HttpClientConfig::default(),
        )
        .await;
        let parsed: Value = serde_json::from_str(&bad_scheme).expect("result should be JSON");
        assert_eq!(parsed["error"], json!("invalid-scheme"));

        let reserved = run_probe(
            json!({ "host": "e-hentai.org", "ips": ["127.0.0.1"] }).to_string(),
            runtime.clone(),
            HttpClientConfig::default(),
        )
        .await;
        let parsed: Value = serde_json::from_str(&reserved).expect("result should be JSON");
        assert_eq!(parsed["error"], json!("invalid-ip"));

        crate::web_runtime::fronting::clear_front_hosts(&runtime);
    }

    #[tokio::test]
    async fn probe_is_runtime_scoped() {
        let runtime_a = runtime_for("scoped-a");
        let runtime_b = runtime_for("scoped-b");
        crate::web_runtime::fronting::clear_front_hosts(&runtime_a);
        crate::web_runtime::fronting::clear_front_hosts(&runtime_b);
        register_host(&runtime_a, "e-hentai.org", &["172.66.132.196"]);

        let result = run_probe(
            json!({ "host": "e-hentai.org" }).to_string(),
            runtime_b.clone(),
            HttpClientConfig::default(),
        )
        .await;
        let parsed: Value = serde_json::from_str(&result).expect("result should be JSON");
        assert_eq!(parsed["error"], json!("host-not-registered"));

        crate::web_runtime::fronting::clear_front_hosts(&runtime_a);
        crate::web_runtime::fronting::clear_front_hosts(&runtime_b);
    }

    #[test]
    fn js_api_returns_promise_with_request_id() {
        let runtime = runtime_for("js-api");
        crate::web_runtime::fronting::clear_front_hosts(&runtime);
        let script = r#"
            (async () => {
              const promise = __http_probe_front_hosts(JSON.stringify({ host: "example.com" }));
              const idType = typeof promise.__hostRequestId;
              const result = JSON.parse(await promise);
              return JSON.stringify({ idType, result });
            })()
        "#;
        let result = crate::tests::run_async_script(script).expect("script should run");
        let parsed: Value = serde_json::from_str(&result).expect("result should be JSON");
        assert_eq!(parsed["idType"], json!("number"));
        assert_eq!(parsed["result"]["ok"], json!(false));
        assert_eq!(parsed["result"]["error"], json!("host-not-registered"));
    }

    /// 采样统计：成功次数、最快值、平均值、丢包率都要一致。
    #[test]
    fn probe_result_derives_stats() {
        let mut result = ProbeResult::new("1.2.3.4".to_string());
        result.samples_sent = 3;
        result.samples_ms = vec![120, 80];
        let result = result.finish();
        assert!(result.ok);
        assert_eq!(result.ttfb_ms, Some(80));
        assert_eq!(result.avg_ms, Some(100));
        assert_eq!(result.samples_received, 2);
        assert_eq!(result.loss_rate, 0.33);
        assert!(result.error.is_none());
    }

    /// 全部失败时 `ok` 为 false，丢包率 1.0，错误原因保留。
    #[test]
    fn probe_result_all_failed() {
        let mut result = ProbeResult::new("1.2.3.4".to_string());
        result.samples_sent = 2;
        result.error = Some("timeout".to_string());
        let result = result.finish();
        assert!(!result.ok);
        assert_eq!(result.ttfb_ms, None);
        assert_eq!(result.avg_ms, None);
        assert_eq!(result.loss_rate, 1.0);
        assert_eq!(result.error.as_deref(), Some("timeout"));
    }

    #[tokio::test]
    async fn probes_local_test_server() {
        let (base_url, _tx, handle) = crate::tests::spawn_test_server(1);
        let client = cached_probe_client(&HttpClientConfig {
            use_http_proxy: false,
            use_socks5_proxy: false,
            ..Default::default()
        })
        .expect("probe client should build");
        let result = probe_one(
            client,
            Arc::new(Semaphore::new(PROBE_PER_PLUGIN_CONCURRENCY)),
            "127.0.0.1".to_string(),
            base_url,
            &ProbeBatchConfig {
                scheme: "http",
                host: "example.com".to_string(),
                timeout: Duration::from_secs(10),
                concurrency: 1,
                samples: 1,
            },
        )
        .await;
        assert!(result.ok, "probe should succeed: {result:?}");
        assert_eq!(result.status, Some(200));
        assert!(result.ttfb_ms.is_some());
        assert_eq!(result.samples_sent, 1);
        assert_eq!(result.samples_received, 1);
        assert_eq!(result.loss_rate, 0.0);
        handle.join().expect("test server should stop");
    }
}
