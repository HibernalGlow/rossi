//! ECH（Encrypted Client Hello）直连。
//!
//! # 与域名前置的区别
//!
//! - **前置**（`fronting.rs`）：URL 改写成 IP、**不发 SNI**，靠 `Host` 头路由。
//!   适合不依赖 SNI 的站点（如 e-hentai 的 Cloudflare 边缘）。
//! - **ECH**（本模块）：URL 保持域名、SNI 加密，外层 SNI 是 ECHConfig 里的
//!   `public_name`（Cloudflare 一般是 `cloudflare-ech.com`），边缘解密后按真实
//!   域名路由。适合「必须看 SNI」的 Cloudflare 站点（如哔咔的分流线路）。
//!
//! # 插件怎么用
//!
//! 通过公开的 `fronting.setEchHosts` 登记域名：
//!
//! ```json
//! { "picaapi.part26.art": { "ips": ["104.21.86.93"], "ech": "<base64>" } }
//! ```
//!
//! - `ips` / `ech` 都可以省略：省略时宿主用 DoH（阿里云 AliDNS，见 `doh` 模块）
//!   查 `HTTPS`(type 65) 记录，从 `ipv4hint` / `ech` 参数补齐；
//! - `pin: true` 表示**只钉 IP、不做 ECH**：URL 保持域名、SNI 正常，只是把 DNS
//!   换成登记的真 IP。给「DNS 被投毒、但域名本身没被封」的域用（如
//!   `*.picacomic.com`）——这类域 Cloudflare 对无 SNI 的连接直接拒绝，
//!   所以用不了前置那套；
//! - IP 通过 `reqwest::ClientBuilder::resolve_to_addrs` 钉死，避免 DNS 污染；
//! - client 按「配置代际 + [`ECH_CLIENT_TTL`]」缓存：改代理立刻重建，
//!   系统代理变化最多 60s 后生效；ECHConfig 本身由 `doh` 模块缓存。
//!
//! 任何一步失败都返回 `None`，请求回退到普通链路——不会因为 ECH 拉不到就把请求打死。
//!
//! # 信任模型
//!
//! 与前置表一样按 runtime（插件）隔离；域名与 IP 在登记时校验（公网地址，
//! `allow_private_network` 打开时放行保留地址）。ECH 路径用 webpki 根证书校验，
//! 不跟随重定向，强制 HTTP/1.1（与前置客户端保持一致）。

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Context as _, Result as AnyResult, anyhow};
use base64::Engine as _;
use reqwest::redirect::Policy;
use reqwest_middleware::ClientWithMiddleware;
use rustls::client::{EchConfig, EchMode};
use rustls::crypto::aws_lc_rs::hpke;
use rustls::pki_types::EchConfigListBytes;
use serde_json::{Value, json};

use super::fronting::validate_probe_ip;
use super::http::{HttpClientConfig, apply_proxy_config, worker_http_config, wrap_http_client};

/// ECH client 的最长存活时间。
///
/// ECHConfig 本身可以缓存一小时（`doh` 模块里还有 5 分钟的正缓存兜着），但 client
/// 里固化了代理配置：应用内改代理会 bump 代际、立刻重建；系统代理（Clash）变化
/// 没有信号，靠这个 TTL 兜底。
const ECH_CLIENT_TTL: Duration = Duration::from_secs(60);
/// ECH client 的请求超时（与普通客户端一致，之前没设会一直挂到 JS 侧超时）。
const ECH_CLIENT_TIMEOUT: Duration = Duration::from_secs(30);
/// 单个域名最多钉几个 IP。
const ECH_MAX_IPS: usize = 8;

/// 单个域名的 ECH 状态。
struct EchEntry {
    /// 登记时给的 IP（可为空，空则用 DoH 的 `ipv4hint`）。
    ips: Vec<String>,
    /// ECHConfigList 原始字节（含 2 字节冗余长度前缀），可为空（空则用 DoH 补）。
    ech: Option<Vec<u8>>,
    /// ECHConfig 是否由插件显式提供（提供时宿主不覆盖，只按 TTL 重建 client）。
    ech_from_plugin: bool,
    /// 只钉 IP、不做 ECH（`pin: true`）：跳过 DoH，保留 SNI 走普通 TLS。
    pin_only: bool,
    /// 最近一次成功构建 client 的时间。
    fetched_at: Option<Instant>,
    /// 构建 client 时的 HTTP 配置代际（代理 / TLS / 内网策略一变就重建）。
    generation: u64,
    /// 用当前 ECHConfig + IP 构建好的 client。
    client: Option<ClientWithMiddleware>,
}

impl EchEntry {
    fn new(ips: Vec<String>, ech: Option<Vec<u8>>, pin_only: bool) -> Self {
        Self {
            ips,
            ech_from_plugin: ech.is_some(),
            pin_only,
            ech,
            fetched_at: None,
            generation: 0,
            client: None,
        }
    }

    fn is_fresh(&self, now: Instant, generation: u64) -> bool {
        self.client.is_some()
            && self.generation == generation
            && self
                .fetched_at
                .map(|at| now.duration_since(at) < ECH_CLIENT_TTL)
                .unwrap_or(false)
    }
}

/// 按 runtime（插件）隔离的 ECH 表。
static ECH_STATES: LazyLock<Mutex<HashMap<String, HashMap<String, EchEntry>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// 是否有任何插件登记过 ECH 域名；为空时热路径只做一次原子读。
static ECH_ACTIVE: AtomicBool = AtomicBool::new(false);

fn states() -> &'static Mutex<HashMap<String, HashMap<String, EchEntry>>> {
    &ECH_STATES
}

/// 规范化并校验 ECH 域名：只接受普通域名（拒绝 IP、端口、路径、空白）。
fn normalize_ech_host(raw: &str) -> Option<String> {
    let host = raw
        .trim()
        .trim_start_matches("https://")
        .trim_start_matches("http://")
        .trim_end_matches('/')
        .to_ascii_lowercase();
    if host.is_empty() || host.len() > 253 || !host.is_ascii() {
        return None;
    }
    if host.contains('/') || host.contains(':') || host.contains(char::is_whitespace) {
        return None;
    }
    if host.parse::<std::net::IpAddr>().is_ok() {
        return None;
    }
    if !host.contains('.') || host == "localhost" {
        return None;
    }
    Some(host)
}

/// 校验并去重 IP 列表。
fn normalize_ech_ips(raw: &[String], allow_private_network: bool) -> (Vec<String>, usize) {
    let mut ips = Vec::new();
    let mut rejected = 0usize;
    for candidate in raw {
        match validate_probe_ip(candidate, allow_private_network) {
            Some(ip) => {
                if !ips.contains(&ip) {
                    ips.push(ip);
                }
            }
            None => rejected += 1,
        }
    }
    ips.truncate(ECH_MAX_IPS);
    (ips, rejected)
}

/// 下发 ECH 域名表。`payload` 是 JSON 字符串：
///
/// - `{ "host": { "ips": ["1.2.3.4"], "ech": "<base64>" } }`
/// - 简写 `{ "host": ["1.2.3.4"] }`
///
/// 传空对象等于关闭 ECH。
pub fn set_ech_hosts(runtime: &str, payload: String) -> String {
    let parsed: Value = match serde_json::from_str(&payload) {
        Ok(value) => value,
        Err(error) => {
            return json!({
                "ok": false,
                "error": crate::tr!("failed-to-parse-front-hosts-json", e = error.to_string()),
            })
            .to_string();
        }
    };

    let allow_private_network = worker_http_config().allow_private_network;
    let mut table: HashMap<String, EchEntry> = HashMap::new();
    let mut rejected = 0usize;

    if let Value::Object(entries) = parsed {
        for (raw_host, raw_value) in entries {
            let Some(host) = normalize_ech_host(&raw_host) else {
                rejected += 1;
                continue;
            };

            let (raw_ips, ech_b64, pin_only) = match raw_value {
                Value::Array(items) => (
                    items
                        .iter()
                        .filter_map(|item| item.as_str().map(str::to_string))
                        .collect::<Vec<_>>(),
                    None,
                    false,
                ),
                Value::Object(fields) => {
                    let ips = fields
                        .get("ips")
                        .and_then(Value::as_array)
                        .map(|items| {
                            items
                                .iter()
                                .filter_map(|item| item.as_str().map(str::to_string))
                                .collect::<Vec<_>>()
                        })
                        .unwrap_or_default();
                    let ech = fields
                        .get("ech")
                        .and_then(Value::as_str)
                        .map(str::trim)
                        .filter(|value| !value.is_empty())
                        .map(str::to_string);
                    let pin = fields.get("pin").and_then(Value::as_bool).unwrap_or(false);
                    (ips, ech, pin)
                }
                Value::Null => (Vec::new(), None, false),
                _ => {
                    rejected += 1;
                    continue;
                }
            };

            let (ips, ip_rejected) = normalize_ech_ips(&raw_ips, allow_private_network);
            rejected += ip_rejected;

            // ECHConfig 给了就先解码校验；解不开直接拒绝该条，避免每次请求都失败。
            let ech = match ech_b64 {
                Some(value) => match base64::engine::general_purpose::STANDARD.decode(value.trim())
                {
                    Ok(bytes) if !bytes.is_empty() => Some(bytes),
                    _ => {
                        rejected += 1;
                        continue;
                    }
                },
                None => None,
            };

            table.insert(host, EchEntry::new(ips, ech, pin_only));
        }
    }

    let host_count = table.len();
    let ip_count: usize = table.values().map(|entry| entry.ips.len()).sum();

    let mut guard = match states().lock() {
        Ok(guard) => guard,
        Err(_) => {
            return json!({ "ok": false, "error": crate::tr!("front-host-state-lock-is-poisoned") })
                .to_string();
        }
    };
    if table.is_empty() {
        guard.remove(runtime);
    } else {
        // 幂等：插件每次 init 都会重登记一遍，条目没变就沿用已建好的 client，
        // 否则每次 init 都会把连接池丢掉、下次请求重新握手。
        //
        // 注意「空 = 没意见」：插件登记 `{}` 之后，宿主会用 DoH 把 ips / ech 填进
        // 条目里；下一次 init 插件还是发 `{}`，如果直接比 `old.ips == entry.ips`
        // 就会永远不相等，等于每次 init 都重建。所以空值不参与比较。
        if let Some(previous) = guard.get(runtime) {
            for (host, entry) in table.iter_mut() {
                if let Some(old) = previous.get(host)
                    && (entry.ips.is_empty() || entry.ips == old.ips)
                    && (entry.ech.is_none() || entry.ech == old.ech)
                    && old.pin_only == entry.pin_only
                {
                    entry.client = old.client.clone();
                    entry.fetched_at = old.fetched_at;
                    entry.generation = old.generation;
                }
            }
        }
        guard.insert(runtime.to_string(), table);
    }
    ECH_ACTIVE.store(!guard.is_empty(), Ordering::Release);

    json!({
        "ok": true,
        "hosts": host_count,
        "ips": ip_count,
        "rejected": rejected,
        "allowPrivateNetwork": allow_private_network,
    })
    .to_string()
}

/// 读回当前 ECH 表（不含 client）。
pub fn get_ech_hosts(runtime: &str) -> String {
    let guard = match states().lock() {
        Ok(guard) => guard,
        Err(_) => {
            return json!({ "ok": false, "error": crate::tr!("front-host-state-lock-is-poisoned") })
                .to_string();
        }
    };
    let Some(table) = guard.get(runtime) else {
        return json!({ "ok": true, "hosts": {} }).to_string();
    };

    let now = Instant::now();
    let generation = super::http::http_config_generation();
    let hosts: serde_json::Map<String, Value> = table
        .iter()
        .map(|(host, entry)| {
            (
                host.clone(),
                json!({
                    "ips": entry.ips,
                    "ech": entry.ech.is_some(),
                    "pin": entry.pin_only,
                    "fresh": entry.is_fresh(now, generation),
                }),
            )
        })
        .collect();

    json!({ "ok": true, "hosts": Value::Object(hosts) }).to_string()
}

/// 清空当前插件的 ECH 表。
pub fn clear_ech_hosts(runtime: &str) -> String {
    if let Ok(mut guard) = states().lock() {
        guard.remove(runtime);
        ECH_ACTIVE.store(!guard.is_empty(), Ordering::Release);
    }
    json!({ "ok": true }).to_string()
}

/// 命中 ECH 表时返回专用 client；未登记 / 构建失败返回 `None`。
pub(crate) async fn ech_client_for(runtime: &str, url: &str) -> Option<ClientWithMiddleware> {
    if !ECH_ACTIVE.load(Ordering::Acquire) {
        return None;
    }
    let host = reqwest::Url::parse(url)
        .ok()?
        .host_str()?
        .to_ascii_lowercase();
    let config = worker_http_config();

    let generation = super::http::http_config_generation();
    let (mut ips, mut ech, ech_from_plugin, pin_only) = {
        let guard = states().lock().ok()?;
        let entry = guard.get(runtime)?.get(&host)?;
        if entry.is_fresh(Instant::now(), generation) {
            return entry.client.clone();
        }
        (
            entry.ips.clone(),
            entry.ech.clone(),
            entry.ech_from_plugin,
            entry.pin_only,
        )
    };

    // 只钉 IP（`pin: true`）：不查 DoH、不做 ECH，保留 SNI 走普通 TLS。
    // 给「DNS 被投毒但域名本身可用」的场景用（如 *.picacomic.com）。
    if pin_only {
        if ips.is_empty() {
            tracing::debug!("ech: pinned host {host} has no ips");
            return None;
        }
        let client = match build_pinned_client(&host, &ips, &config) {
            Ok(client) => client,
            Err(error) => {
                tracing::warn!("ech: failed to build pinned client for {host}: {error:#}");
                return None;
            }
        };
        if let Ok(mut guard) = states().lock()
            && let Some(entry) = guard
                .get_mut(runtime)
                .and_then(|table| table.get_mut(&host))
        {
            entry.fetched_at = Some(Instant::now());
            entry.generation = generation;
            entry.client = Some(client.clone());
        }
        return Some(client);
    }

    // 缺 ECHConfig / 缺 IP / 缓存过期时用 DoH 补。`doh::lookup_https_rr` 自带正负缓存，
    // 命中缓存时只是一次 mutex 读；查不到会立刻返回，不会把请求卡在这里。
    // 插件显式给过 ECHConfig 时不覆盖它，只补 IP。
    // DoH 走自己的 reqwest 客户端并复用当前代理配置，所以开了代理也照常查询。
    let need_ech = !ech_from_plugin;
    let need_ips = ips.is_empty();
    if need_ech || need_ips {
        if let Some((doh_ech, doh_ips)) = super::doh::lookup_https_rr(&host, &config).await {
            if need_ech {
                ech = Some(doh_ech);
            }
            if need_ips {
                let (normalized, _) = normalize_ech_ips(&doh_ips, config.allow_private_network);
                ips = normalized;
            }
        }
    }

    let ech = ech?;
    tracing::debug!(
        "ech: building client for {host} ips={:?} from_plugin={ech_from_plugin}",
        ips
    );
    let client = match build_ech_client(&host, &ips, &ech, &config) {
        Ok(client) => client,
        Err(error) => {
            tracing::warn!("ech: failed to build client for {host}: {error:#}");
            return None;
        }
    };

    if let Ok(mut guard) = states().lock() {
        if let Some(entry) = guard
            .get_mut(runtime)
            .and_then(|table| table.get_mut(&host))
        {
            entry.ech = Some(ech);
            if entry.ips.is_empty() {
                entry.ips = ips;
            }
            entry.fetched_at = Some(Instant::now());
            entry.generation = generation;
            entry.client = Some(client.clone());
        }
    }
    Some(client)
}

/// 请求失败时丢掉缓存的 client，下一次重新拉 ECHConfig / 换 IP 重建。
///
/// `InvalidContentType` 这类 TLS 抖动通常是某次连接被中间设备打断；重建后
/// 大概率换到另一条 hint IP 或新的连接，重试即可恢复。
pub(crate) fn invalidate_ech_client(runtime: &str, url: &str) {
    let Some(host) = reqwest::Url::parse(url)
        .ok()
        .and_then(|parsed| parsed.host_str().map(str::to_ascii_lowercase))
    else {
        return;
    };
    if let Ok(mut guard) = states().lock() {
        if let Some(entry) = guard
            .get_mut(runtime)
            .and_then(|table| table.get_mut(&host))
        {
            entry.client = None;
            entry.fetched_at = None;
            tracing::debug!("ech: invalidated client for {host}");
        }
    }
}

/// 用 ECHConfig + 钉死的 IP 构建 reqwest client。
fn build_ech_client(
    host: &str,
    ips: &[String],
    ech: &[u8],
    config: &HttpClientConfig,
) -> AnyResult<ClientWithMiddleware> {
    let ech = EchConfig::new(
        EchConfigListBytes::from(ech.to_vec()),
        hpke::ALL_SUPPORTED_SUITES,
    )
    .map_err(|error| anyhow!("invalid ech config: {error}"))?;

    let mut roots = rustls::RootCertStore::empty();
    roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());

    // `with_ech` 只挂在 `WantsVersions` 上，必须用 builder_with_provider 起链；
    // provider 与 reqwest 的 `rustls` feature 一致（aws-lc-rs），避免进程默认 provider 冲突。
    let provider = std::sync::Arc::new(rustls::crypto::aws_lc_rs::default_provider());
    let mut tls = rustls::ClientConfig::builder_with_provider(provider)
        .with_ech(EchMode::Enable(ech))
        .map_err(|error| anyhow!("enable ech failed: {error}"))?
        .with_root_certificates(roots)
        .with_no_client_auth();
    tls.alpn_protocols = vec![b"http/1.1".to_vec()];

    let mut builder = reqwest::Client::builder()
        .timeout(ECH_CLIENT_TIMEOUT)
        .http1_only()
        .redirect(Policy::none())
        // 复用连接：每个请求少一次 TCP + TLS(ECH) 握手（实测 1.2s → 0.5s）。
        // 空闲 10s 断开，Clash 切节点后最多粘 10s。
        .pool_max_idle_per_host(4)
        .pool_idle_timeout(Duration::from_secs(10));

    let addrs: Vec<SocketAddr> = ips
        .iter()
        .filter_map(|ip| format!("{ip}:443").parse::<SocketAddr>().ok())
        .collect();
    if !addrs.is_empty() {
        builder = builder.resolve_to_addrs(host, &addrs);
    }

    builder = apply_proxy_config(builder, config)?;
    // 注意：`tls_backend_preconfigured` 内部会自己包一层 `Some`，这里传裸 ClientConfig。
    builder = builder.tls_backend_preconfigured(tls);

    let client = builder.build().context("build ech client failed")?;
    Ok(wrap_http_client(client))
}

/// 只钉 IP、保留 SNI 的普通 TLS 客户端（不做 ECH）。
///
/// 给「DNS 被投毒、但域名本身没被封」的场景用：URL 保持域名、SNI 正常，
/// 只是把 DNS 换成插件登记的真 IP。Cloudflare 对无 SNI 的连接直接回
/// `handshake failure`，所以不能复用前置那套（IP 直连 + Host 头）。
fn build_pinned_client(
    host: &str,
    ips: &[String],
    config: &HttpClientConfig,
) -> AnyResult<ClientWithMiddleware> {
    let mut roots = rustls::RootCertStore::empty();
    roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());

    let provider = std::sync::Arc::new(rustls::crypto::aws_lc_rs::default_provider());
    let mut tls = rustls::ClientConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .map_err(|error| anyhow!("pinned tls config failed: {error}"))?
        .with_root_certificates(roots)
        .with_no_client_auth();
    tls.alpn_protocols = vec![b"http/1.1".to_vec()];

    let mut builder = reqwest::Client::builder()
        .timeout(ECH_CLIENT_TIMEOUT)
        .http1_only()
        .redirect(Policy::none())
        .pool_max_idle_per_host(4)
        .pool_idle_timeout(Duration::from_secs(10));

    let addrs: Vec<SocketAddr> = ips
        .iter()
        .filter_map(|ip| format!("{ip}:443").parse::<SocketAddr>().ok())
        .collect();
    if !addrs.is_empty() {
        builder = builder.resolve_to_addrs(host, &addrs);
    }

    builder = apply_proxy_config(builder, config)?;
    builder = builder.tls_backend_preconfigured(tls);

    let client = builder.build().context("build pinned client failed")?;
    Ok(wrap_http_client(client))
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_RUNTIME: &str = "test-ech-runtime";

    fn with_serialized_state<T>(f: impl FnOnce() -> T) -> T {
        static LOCK: Mutex<()> = Mutex::new(());
        let _guard = LOCK.lock().unwrap_or_else(|error| error.into_inner());
        f()
    }

    #[test]
    fn normalizes_domains_and_rejects_ip_port_path() {
        assert_eq!(
            normalize_ech_host("https://PicaAPI.Part26.Art/"),
            Some("picaapi.part26.art".to_string())
        );
        for raw in [
            "1.2.3.4",
            "example.com:443",
            "example.com/path",
            "localhost",
            "example",
            "",
        ] {
            assert!(
                normalize_ech_host(raw).is_none(),
                "{raw} should be rejected"
            );
        }
    }

    #[test]
    fn set_get_clear_roundtrip() {
        with_serialized_state(|| {
            clear_ech_hosts(TEST_RUNTIME);
            let result = set_ech_hosts(
                TEST_RUNTIME,
                json!({
                    "picaapi.part26.art": ["104.21.86.93", "not-an-ip"],
                    "https://PicaAPI.Go2778.com/": { "ips": ["104.21.42.75"] },
                    "1.2.3.4": ["104.21.86.93"],
                })
                .to_string(),
            );
            let parsed: Value = serde_json::from_str(&result).expect("json");
            assert_eq!(parsed["ok"], json!(true));
            assert_eq!(parsed["hosts"], json!(2));
            assert_eq!(parsed["ips"], json!(2));
            // 非法 IP + 非法域名各计一次
            assert_eq!(parsed["rejected"], json!(2));

            let table: Value = serde_json::from_str(&get_ech_hosts(TEST_RUNTIME)).expect("json");
            assert_eq!(
                table["hosts"]["picaapi.part26.art"]["ips"],
                json!(["104.21.86.93"])
            );
            assert_eq!(table["hosts"]["picaapi.go2778.com"]["ech"], json!(false));

            clear_ech_hosts(TEST_RUNTIME);
            let cleared: Value = serde_json::from_str(&get_ech_hosts(TEST_RUNTIME)).expect("json");
            assert_eq!(cleared["hosts"], json!({}));
        });
    }

    /// 塞一个「已建好的 client」进表，模拟上次 init 之后的缓存状态。
    fn seed_cached_client(host: &str, generation: u64) {
        let mut guard = states().lock().expect("state lock");
        let entry = guard
            .get_mut(TEST_RUNTIME)
            .and_then(|table| table.get_mut(host))
            .expect("entry should exist");
        entry.client = Some(wrap_http_client(reqwest::Client::new()));
        entry.fetched_at = Some(Instant::now());
        entry.generation = generation;
    }

    fn cached_generation(host: &str) -> (bool, u64) {
        let guard = states().lock().expect("state lock");
        let entry = guard
            .get(TEST_RUNTIME)
            .and_then(|table| table.get(host))
            .expect("entry should exist");
        (entry.client.is_some(), entry.generation)
    }

    /// 插件每次 init 都会重登记一遍：表没变时必须沿用已建好的 client。
    #[test]
    fn re_registering_same_hosts_keeps_cached_client() {
        with_serialized_state(|| {
            clear_ech_hosts(TEST_RUNTIME);
            let payload = json!({ "picaapi.part26.art": ["104.21.86.93"] }).to_string();
            set_ech_hosts(TEST_RUNTIME, payload.clone());
            seed_cached_client("picaapi.part26.art", 7);

            set_ech_hosts(TEST_RUNTIME, payload);

            assert_eq!(cached_generation("picaapi.part26.art"), (true, 7));
            clear_ech_hosts(TEST_RUNTIME);
        });
    }

    /// 插件登记 `{}` 后宿主会用 DoH 把 ips / ech 填进条目；下一次 init 还是 `{}`，
    /// 不能因为「填过的值 ≠ 空值」就把 client 丢掉。
    #[test]
    fn re_registering_empty_entry_after_resolution_keeps_cached_client() {
        with_serialized_state(|| {
            clear_ech_hosts(TEST_RUNTIME);
            let payload = json!({ "picaapi.part26.art": {} }).to_string();
            set_ech_hosts(TEST_RUNTIME, payload.clone());

            // 模拟宿主用 DoH 补齐后的状态。
            {
                let mut guard = states().lock().expect("state lock");
                let entry = guard
                    .get_mut(TEST_RUNTIME)
                    .and_then(|table| table.get_mut("picaapi.part26.art"))
                    .expect("entry should exist");
                entry.ips = vec!["104.21.86.93".to_string()];
                entry.ech = Some(vec![0xfe, 0x0d]);
                entry.client = Some(wrap_http_client(reqwest::Client::new()));
                entry.fetched_at = Some(Instant::now());
                entry.generation = 7;
            }

            set_ech_hosts(TEST_RUNTIME, payload);

            assert_eq!(cached_generation("picaapi.part26.art"), (true, 7));
            clear_ech_hosts(TEST_RUNTIME);
        });
    }

    /// `pin: true`：只钉 IP、不查 DoH，直接建普通 TLS 客户端。
    #[test]
    fn pin_mode_builds_client_without_doh() {
        with_serialized_state(|| {
            clear_ech_hosts(TEST_RUNTIME);
            set_ech_hosts(
                TEST_RUNTIME,
                json!({
                    "img.picacomic.com": { "ips": ["172.66.173.71"], "pin": true },
                })
                .to_string(),
            );

            let table: Value = serde_json::from_str(&get_ech_hosts(TEST_RUNTIME)).expect("json");
            assert_eq!(table["hosts"]["img.picacomic.com"]["pin"], json!(true));

            let started = Instant::now();
            let client =
                futures_lite_block_on(ech_client_for(TEST_RUNTIME, "https://img.picacomic.com/"));
            let elapsed = started.elapsed();

            assert!(client.is_some(), "pin 模式应直接建好 client");
            assert!(
                elapsed < Duration::from_millis(200),
                "pin 模式不应查 DoH，实际 {elapsed:?}"
            );
            clear_ech_hosts(TEST_RUNTIME);
        });
    }

    /// `pin: true` 但没给 IP：无法建 client，回落普通链路。
    #[test]
    fn pin_mode_without_ips_falls_back() {
        with_serialized_state(|| {
            clear_ech_hosts(TEST_RUNTIME);
            set_ech_hosts(
                TEST_RUNTIME,
                json!({ "img.picacomic.com": { "pin": true } }).to_string(),
            );
            let client =
                futures_lite_block_on(ech_client_for(TEST_RUNTIME, "https://img.picacomic.com/"));
            assert!(client.is_none());
            clear_ech_hosts(TEST_RUNTIME);
        });
    }

    /// 联网冒烟：钉 IP 的域应能正常握手（Cloudflare 只认 SNI，不认无 SNI）。
    /// `cargo test -- --ignored --nocapture pinned_live_smoke`
    #[tokio::test]
    #[ignore]
    async fn pinned_live_smoke() {
        with_serialized_state(|| {
            clear_ech_hosts(TEST_RUNTIME);
            set_ech_hosts(
                TEST_RUNTIME,
                json!({
                    "img.picacomic.com": {
                        "ips": ["172.66.173.71", "104.20.42.9"],
                        "pin": true,
                    },
                })
                .to_string(),
            );
        });
        let client = ech_client_for(TEST_RUNTIME, "https://img.picacomic.com/")
            .await
            .expect("pinned client");
        let response = client
            .get("https://img.picacomic.com/")
            .send()
            .await
            .expect("request should complete");
        println!("img.picacomic.com -> {}", response.status());
        assert!(response.status().is_success());
        with_serialized_state(|| clear_ech_hosts(TEST_RUNTIME));
    }

    /// 走代理也照样查 DoH；查不到就回落普通链路，不能卡住请求。
    #[test]
    fn proxy_active_still_queries_doh_then_falls_back() {
        with_serialized_state(|| {
            clear_ech_hosts(TEST_RUNTIME);
            super::super::doh::reset_caches();
            set_ech_hosts(
                TEST_RUNTIME,
                json!({ "picaapi.part26.art": {} }).to_string(),
            );
            crate::web_runtime::set_worker_http_config(HttpClientConfig {
                use_http_proxy: true,
                // 不可达代理：DoH 查询会立刻连接失败，不会真的出网。
                http_proxy: Some("http://127.0.0.1:1".to_string()),
                ..Default::default()
            });

            let started = Instant::now();
            let client =
                futures_lite_block_on(ech_client_for(TEST_RUNTIME, "https://picaapi.part26.art/"));
            let elapsed = started.elapsed();

            crate::web_runtime::set_worker_http_config(HttpClientConfig::default());
            clear_ech_hosts(TEST_RUNTIME);

            assert!(client.is_none(), "缺 ECHConfig 时应回落普通链路");
            assert!(
                elapsed < Duration::from_secs(3),
                "DoH 查询失败后应快速回落，实际耗时 {elapsed:?}"
            );
        });
    }

    /// 条目变了（IP / ECHConfig 不同）就不能沿用旧 client。
    #[test]
    fn changing_host_entry_drops_cached_client() {
        with_serialized_state(|| {
            clear_ech_hosts(TEST_RUNTIME);
            set_ech_hosts(
                TEST_RUNTIME,
                json!({ "picaapi.part26.art": ["104.21.86.93"] }).to_string(),
            );
            seed_cached_client("picaapi.part26.art", 7);

            set_ech_hosts(
                TEST_RUNTIME,
                json!({ "picaapi.part26.art": ["172.67.217.104"] }).to_string(),
            );

            assert_eq!(cached_generation("picaapi.part26.art"), (false, 0));
            clear_ech_hosts(TEST_RUNTIME);
        });
    }

    #[test]
    fn rejects_invalid_ech_base64() {
        with_serialized_state(|| {
            clear_ech_hosts(TEST_RUNTIME);
            let result = set_ech_hosts(
                TEST_RUNTIME,
                json!({ "picaapi.part26.art": { "ech": "not base64!!" } }).to_string(),
            );
            let parsed: Value = serde_json::from_str(&result).expect("json");
            assert_eq!(parsed["ok"], json!(true));
            assert_eq!(parsed["hosts"], json!(0));
            assert_eq!(parsed["rejected"], json!(1));
            clear_ech_hosts(TEST_RUNTIME);
        });
    }

    #[test]
    fn ech_client_for_unknown_host_is_none() {
        with_serialized_state(|| {
            clear_ech_hosts(TEST_RUNTIME);
            let client =
                futures_lite_block_on(ech_client_for(TEST_RUNTIME, "https://example.com/"));
            assert!(client.is_none());
        });
    }

    /// 公开 API：`fronting.setEchHosts` / `getEchHosts` / `clearEchHosts` 走普通对象。
    #[cfg(feature = "host-fronting")]
    #[test]
    fn js_public_ech_api_roundtrip() {
        let script = r#"
            (() => {
              const set = fronting.setEchHosts({ "picaapi.part26.art": {} });
              const get = fronting.getEchHosts();
              const clear = fronting.clearEchHosts();
              return JSON.stringify({ set, get, clear });
            })()
        "#;
        let result = crate::tests::run_async_script(script).expect("script should run");
        let parsed: Value = serde_json::from_str(&result).expect("json");
        assert_eq!(parsed["set"]["ok"], json!(true));
        assert_eq!(parsed["set"]["hosts"], json!(1));
        assert_eq!(
            parsed["get"]["hosts"]["picaapi.part26.art"]["ech"],
            json!(false)
        );
        assert_eq!(parsed["clear"]["ok"], json!(true));
    }

    /// feature 关闭时公开 API 仍在，但统一返回 unsupported。
    #[cfg(not(feature = "host-fronting"))]
    #[test]
    fn js_public_ech_api_unsupported_without_feature() {
        let script = r#"
            (() => {
              const set = fronting.setEchHosts({ "picaapi.part26.art": {} });
              const get = fronting.getEchHosts();
              const clear = fronting.clearEchHosts();
              return JSON.stringify({ set, get, clear });
            })()
        "#;
        let result = crate::tests::run_async_script(script).expect("script should run");
        let parsed: Value = serde_json::from_str(&result).expect("json");
        assert_eq!(parsed["set"]["error"], json!("fronting-unsupported"));
        assert_eq!(parsed["get"]["error"], json!("fronting-unsupported"));
        assert_eq!(parsed["clear"]["error"], json!("fronting-unsupported"));
    }

    /// 全链路联网冒烟：JS 侧 `fronting.setEchHosts` + `fetch` 走 ECH。
    /// 手动跑：`cargo test --features host-fronting -- --ignored --nocapture js_ech_fetch_smoke`
    #[cfg(feature = "host-fronting")]
    #[test]
    #[ignore]
    fn js_ech_fetch_smoke() {
        let script = r#"
            (async () => {
              const set = fronting.setEchHosts({ "picaapi.part26.art": {} });
              const res = await fetch("https://picaapi.part26.art/");
              const body = await res.text();
              const meta = res.hostMeta;
              fronting.clearEchHosts();
              return JSON.stringify({ set, status: res.status, body, meta });
            })()
        "#;
        let result = crate::tests::run_async_script(script).expect("script should run");
        println!("{result}");
        let parsed: Value = serde_json::from_str(&result).expect("json");
        assert_eq!(parsed["set"]["ok"], json!(true));
        assert_eq!(parsed["status"], json!(400));
        assert!(
            parsed["body"]
                .as_str()
                .unwrap_or_default()
                .contains("\"code\"")
        );
    }

    /// 逐 IP 冒烟：每个 DoH hint 单独建 ECH client，连发 3 次，看是否有坏 IP。
    /// `cargo test --features host-fronting -- --ignored --nocapture ech_per_ip_smoke`
    #[tokio::test]
    #[ignore]
    async fn ech_per_ip_smoke() {
        let host = "picaapi.part26.art";
        let config = HttpClientConfig::default();
        let (ech, ips) = super::super::doh::lookup_https_rr(host, &config)
            .await
            .expect("doh");
        for ip in &ips {
            for round in 0..3 {
                let client = build_ech_client(host, std::slice::from_ref(ip), &ech, &config)
                    .expect("build client");
                let result = client.get(format!("https://{host}/")).send().await;
                match result {
                    Ok(response) => println!("{ip} round{round} -> {}", response.status()),
                    Err(error) => println!("{ip} round{round} -> ERR {error}"),
                }
            }
        }
    }

    /// 联网冒烟：DoH 拿 ECHConfig → 建 client → GET `/` 应拿到真 API 的 400 JSON。
    /// 默认忽略，手动跑：
    /// `cargo test --features host-fronting -- --ignored --nocapture ech_live_smoke`
    #[tokio::test]
    #[ignore]
    async fn ech_live_smoke() {
        let host = "picaapi.part26.art";
        let config = HttpClientConfig::default();
        let (ech, ips) = super::super::doh::lookup_https_rr(host, &config)
            .await
            .expect("doh should return ech");
        println!("ech_len={} ips={ips:?}", ech.len());
        let client = build_ech_client(host, &ips, &ech, &config).expect("build ech client");
        let response = client
            .get(format!("https://{host}/"))
            .send()
            .await
            .expect("request should complete");
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        println!("status={status} body={body}");
        assert!(body.contains("\"code\""), "unexpected body: {body}");
    }

    /// 小工具：测试里同步等一个 future（不引入额外依赖）。
    fn futures_lite_block_on<F: std::future::Future>(future: F) -> F::Output {
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("runtime")
            .block_on(future)
    }
}
