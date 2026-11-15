use ::http::Extensions;
use reqwest_middleware::ClientWithMiddleware;
use std::sync::LazyLock;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HttpClientConfig {
    pub use_http_proxy: bool,
    pub use_socks5_proxy: bool,
    pub http_proxy: Option<String>,
    pub socks5_proxy: Option<String>,
    pub disable_tls_verify: bool,
    pub allow_private_network: bool,
    /// 是否启用 DoH（DNS over HTTPS）。开启且 `doh_providers` 非空时，
    /// 普通 HTTP 客户端与 ECH 都会用 DoH 解析，**与是否配置代理无关**。
    pub doh_enabled: bool,
    /// DoH 端点列表（完整 URL，例如 `https://doh.pub/dns-query`）。
    /// 查询时全部并发，第一个有效答案胜出。
    pub doh_providers: Vec<String>,
}

static HTTP_REQUESTS_BLOCKED: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);

pub fn set_http_requests_blocked(blocked: bool) {
    HTTP_REQUESTS_BLOCKED.store(blocked, Ordering::Release);
}

pub fn is_http_requests_blocked() -> bool {
    HTTP_REQUESTS_BLOCKED.load(Ordering::Acquire)
}

#[derive(Debug, Clone, Copy, Default)]
pub struct HttpRequestBlockMiddleware;

#[async_trait::async_trait]
impl reqwest_middleware::Middleware for HttpRequestBlockMiddleware {
    async fn handle(
        &self,
        request: reqwest::Request,
        extensions: &mut Extensions,
        next: reqwest_middleware::Next<'_>,
    ) -> reqwest_middleware::Result<reqwest::Response> {
        if is_http_requests_blocked() {
            return Err(reqwest_middleware::Error::Middleware(anyhow!(crate::tr!(
                "http-requests-blocked"
            ))));
        }

        next.run(request, extensions).await
    }
}

pub fn wrap_http_client(client: Client) -> ClientWithMiddleware {
    reqwest_middleware::ClientBuilder::new(client)
        .with(HttpRequestBlockMiddleware)
        .build()
}

impl Default for HttpClientConfig {
    fn default() -> Self {
        Self {
            use_http_proxy: true,
            use_socks5_proxy: true,
            http_proxy: None,
            socks5_proxy: None,
            disable_tls_verify: false,
            allow_private_network: false,
            doh_enabled: true,
            doh_providers: super::doh::DEFAULT_DOH_PROVIDERS
                .iter()
                .map(|url| (*url).to_string())
                .collect(),
        }
    }
}

pub(crate) struct HttpClientState {
    config: HttpClientConfig,
}

impl Default for HttpClientState {
    fn default() -> Self {
        Self {
            config: HttpClientConfig::default(),
        }
    }
}

static HTTP_PROMISE_CANCEL_SENDERS: LazyLock<Mutex<HashMap<u64, oneshot::Sender<()>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn http_promise_cancel_senders() -> &'static Mutex<HashMap<u64, oneshot::Sender<()>>> {
    &HTTP_PROMISE_CANCEL_SENDERS
}

/// 分配一个全局 HTTP 请求 id（普通请求与前置探测共用同一 id 空间）。
pub(crate) fn next_http_request_id() -> u64 {
    HTTP_REQ_ID.fetch_add(1, Ordering::Relaxed)
}

/// 注册一个取消通道。调用方负责在请求结束后调用 [`unregister_http_cancel`]。
pub(crate) fn register_http_cancel(id: u64) -> oneshot::Receiver<()> {
    let (cancel_tx, cancel_rx) = oneshot::channel::<()>();
    http_promise_cancel_senders()
        .lock()
        .expect(&crate::tr!("failed-to-lock-http-promise-cancel-senders"))
        .insert(id, cancel_tx);
    cancel_rx
}

/// 移除取消通道。请求成功、失败或被取消后都必须调用，避免 sender 泄漏。
pub(crate) fn unregister_http_cancel(id: u64) {
    http_promise_cancel_senders()
        .lock()
        .expect(&crate::tr!("failed-to-lock-http-promise-cancel-senders"))
        .remove(&id);
}

/// 当前挂起的 HTTP 取消 sender 数量（用于诊断/测试确认正常完成后被清理）。
pub fn http_promise_cancel_senders_len() -> usize {
    http_promise_cancel_senders()
        .lock()
        .map(|m| m.len())
        .unwrap_or(0)
}

/// 当前挂起的取消 sender 的请求 id。
///
/// 供测试断言「某个具体请求完成后 sender 被清掉」用——比较总数会被并行
/// 用例的在途请求干扰。
pub fn http_promise_cancel_senders_ids() -> Vec<u64> {
    http_promise_cancel_senders()
        .lock()
        .map(|m| m.keys().copied().collect())
        .unwrap_or_default()
}

/// runtime -> 在途 HTTP 请求信号量。
///
/// 用按插件分开的信号量而不是一个全局信号量：配额按插件隔离，一个插件把配额
/// 用满只会让它自己的新请求排队，不会挤占别的插件。
static HTTP_IO_SEMS: LazyLock<Mutex<HashMap<String, Arc<Semaphore>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// 取某个插件的在途请求信号量，没有就建一个。
pub(crate) fn http_io_sem(runtime: &str) -> Arc<Semaphore> {
    let mut sems = match HTTP_IO_SEMS.lock() {
        Ok(sems) => sems,
        Err(poisoned) => poisoned.into_inner(),
    };
    Arc::clone(
        sems.entry(runtime.to_string())
            .or_insert_with(|| Arc::new(Semaphore::new(HTTP_PER_PLUGIN_MAX_IN_FLIGHT))),
    )
}

/// 回收某个插件的信号量（runtime 销毁时调用）。
pub(crate) fn release_http_io_sem(runtime: &str) {
    if let Ok(mut sems) = HTTP_IO_SEMS.lock() {
        sems.remove(runtime);
    }
}

/// 所有插件当前可用配额之和，供 `__runtime_stats()` 展示。
pub(crate) fn http_io_available_permits() -> usize {
    match HTTP_IO_SEMS.lock() {
        Ok(sems) => sems.values().map(|sem| sem.available_permits()).sum(),
        Err(poisoned) => poisoned
            .into_inner()
            .values()
            .map(|sem| sem.available_permits())
            .sum(),
    }
}

pub(crate) fn cleanup_stale_pending(
    pool: &mut HashMap<u64, PendingTask>,
    dropped_counter: &AtomicU64,
) {
    let now = Instant::now();
    let stale_items: Vec<(u64, PendingTaskMeta, u64)> = pool
        .iter()
        .filter_map(|(id, pending)| {
            if now.duration_since(pending.created_at) > PENDING_TASK_TTL {
                Some((
                    *id,
                    pending.meta.clone(),
                    now.duration_since(pending.created_at).as_millis() as u64,
                ))
            } else {
                None
            }
        })
        .collect();

    for (id, meta, elapsed_ms) in stale_items {
        if let Some(pending) = pool.remove(&id) {
            pending.task.abort();
            dropped_counter.fetch_add(1, Ordering::Relaxed);
            tracing::warn!(
                "cleanup stale pending task: kind={}, id={}, elapsed_ms={}, label={}",
                meta.kind,
                id,
                elapsed_ms,
                meta.label
            );
        }
    }
}

pub(crate) fn cleanup_stale_pending_abort(
    pool: &mut HashMap<u64, PendingAbortTask>,
    dropped_counter: &AtomicU64,
) {
    let now = Instant::now();
    let stale_items: Vec<(u64, PendingAbortTaskMeta, u64)> = pool
        .iter()
        .filter_map(|(id, pending)| {
            if now.duration_since(pending.created_at) > PENDING_TASK_TTL {
                Some((
                    *id,
                    pending.meta.clone(),
                    now.duration_since(pending.created_at).as_millis() as u64,
                ))
            } else {
                None
            }
        })
        .collect();

    for (id, meta, elapsed_ms) in stale_items {
        if let Some(pending) = pool.remove(&id) {
            pending.task.abort();
            dropped_counter.fetch_add(1, Ordering::Relaxed);
            tracing::warn!(
                "cleanup stale pending abort task: kind={}, id={}, elapsed_ms={}, label={}",
                meta.kind,
                id,
                elapsed_ms,
                meta.label
            );
        }
    }
}

fn header_truthy(value: &str) -> bool {
    matches!(
        value.trim().to_ascii_lowercase().as_str(),
        "1" | "true" | "yes" | "on"
    )
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HostFormDataPlan {
    kind: Option<String>,
    entries: Vec<HostFormDataEntry>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HostFormDataEntry {
    name: String,
    kind: String,
    value: Option<String>,
    data_b64: Option<String>,
    filename: Option<String>,
    content_type: Option<String>,
}

fn parse_host_formdata_plan(raw_json: &str) -> AnyResult<HostFormDataPlan> {
    let plan = serde_json::from_str::<HostFormDataPlan>(raw_json)
        .context(crate::tr!("failed-to-parse-host-formdata-plan-json"))?;
    if let Some(kind) = &plan.kind {
        if kind != "rquickjs-formdata-v1" {
            return Err(anyhow!(crate::tr!(
                "unsupported-formdata-plan-kind",
                kind = kind
            )));
        }
    }
    Ok(plan)
}

pub(crate) fn decode_host_base64(raw_b64: &str) -> AnyResult<Vec<u8>> {
    let raw = raw_b64.trim();
    BASE64_STANDARD
        .decode(raw)
        .or_else(|_| BASE64_URL_SAFE.decode(raw))
        .context(crate::tr!("failed-to-base64-decode-formdata-field"))
}

fn build_multipart_form(plan: HostFormDataPlan) -> AnyResult<MultipartForm> {
    let mut form = MultipartForm::new();
    for entry in plan.entries {
        if entry.kind.eq_ignore_ascii_case("text") {
            let value = entry
                .value
                .ok_or_else(|| anyhow!(crate::tr!("formdata-text-field-missing-value")))?;
            form = form.text(entry.name, value);
            continue;
        }

        if entry.kind.eq_ignore_ascii_case("binary") {
            let data_b64 = entry
                .data_b64
                .ok_or_else(|| anyhow!(crate::tr!("formdata-binary-field-missing-datab64")))?;
            let bytes = decode_host_base64(&data_b64)?;
            let mut part = MultipartPart::bytes(bytes);
            if let Some(filename) = entry.filename {
                part = part.file_name(filename);
            }
            if let Some(content_type) = entry
                .content_type
                .as_deref()
                .map(str::trim)
                .filter(|v| !v.is_empty())
            {
                part = part.mime_str(content_type).map_err(|e| {
                    anyhow!(crate::tr!(
                        "failed-to-set-formdata-part-content-type",
                        e = e
                    ))
                })?;
            }
            form = form.part(entry.name, part);
            continue;
        }

        return Err(anyhow!(crate::tr!(
            "unsupported-formdata-field-type",
            arg0 = entry.kind
        )));
    }
    Ok(form)
}

fn http_client_state_cell() -> &'static Mutex<HttpClientState> {
    HTTP_CLIENT_STATE.get_or_init(|| Mutex::new(HttpClientState::default()))
}

/// HTTP 配置代际：`configure_http_client` 每次更新 +1。
///
/// 线程本地缓存（[`WORKER_HTTP_CONFIG`]）靠它判断是否过期。没有它的话，
/// QJS runtime 线程在创建时拍下的配置会一直用下去，用户改代理 / 改内网策略
/// 后已加载的插件不生效，必须重建 runtime 才行。
static HTTP_CONFIG_GENERATION: AtomicU64 = AtomicU64::new(0);

pub fn configure_http_client(config: HttpClientConfig) -> AnyResult<()> {
    let mut state = http_client_state_cell()
        .lock()
        .map_err(|_| anyhow!(crate::tr!("http-client-state-lock-is-poisoned")))?;
    let doh_changed = state.config.doh_enabled != config.doh_enabled
        || state.config.doh_providers != config.doh_providers
        || state.config.use_http_proxy != config.use_http_proxy
        || state.config.http_proxy != config.http_proxy
        || state.config.use_socks5_proxy != config.use_socks5_proxy
        || state.config.socks5_proxy != config.socks5_proxy;
    state.config = config;
    drop(state);
    if doh_changed {
        // 端点 / 代理一变，旧答案的「干净程度」就不可信了。
        super::doh::reset_caches();
    }
    HTTP_CONFIG_GENERATION.fetch_add(1, Ordering::Release);
    Ok(())
}

pub fn current_http_client_config() -> HttpClientConfig {
    http_client_state_cell()
        .lock()
        .map(|g| g.config.clone())
        .unwrap_or_default()
}

/// 当前配置代际。
///
/// 自己缓存 client 的模块（ECH / 前置）用它判断配置是否变过：代际一变就重建，
/// 不需要监听任何设置项。
pub(crate) fn http_config_generation() -> u64 {
    HTTP_CONFIG_GENERATION.load(Ordering::Acquire)
}

thread_local! {
    /// 线程本地的 HTTP 配置：(拍下时的代际, 配置, 是否钉住)。
    ///
    /// `pinned = true` 表示调用方显式指定过配置（runtime 创建时快照，或把配置
    /// 带到 tokio 任务线程），后续全局变更不影响它。
    static WORKER_HTTP_CONFIG: std::cell::RefCell<Option<(u64, HttpClientConfig, bool)>> =
        const { std::cell::RefCell::new(None) };
}

/// 显式钉住当前线程的配置，后续全局变更不影响它。
///
/// 两个用途：runtime 创建时快照（默认行为），以及把配置从 QJS 线程带到
/// tokio 任务线程——任务内要的就是拍下的那份。
pub fn set_worker_http_config(config: HttpClientConfig) {
    let generation = HTTP_CONFIG_GENERATION.load(Ordering::Acquire);
    WORKER_HTTP_CONFIG.with(|c| *c.borrow_mut() = Some((generation, config, true)));
}

/// 取当前线程的配置。
///
/// 钉住时直接返回；否则按代际判断，过时就从全局重新拉一份。后者让
/// `configure_http_client` 之后已存在的 QJS runtime 线程也能看到新配置，
/// 不需要重建 runtime。
pub(crate) fn worker_http_config() -> HttpClientConfig {
    let generation = HTTP_CONFIG_GENERATION.load(Ordering::Acquire);
    WORKER_HTTP_CONFIG.with(|c| {
        let mut slot = c.borrow_mut();
        if let Some((cached, config, pinned)) = slot.as_ref()
            && (*pinned || *cached == generation)
        {
            return config.clone();
        }
        let config = current_http_client_config();
        *slot = Some((generation, config.clone(), false));
        config
    })
}

/// 缓存 client 的最长存活时间。
///
/// 应用内改代理会 bump 代际，立刻重建；系统代理（Clash 的「系统代理」开关）
/// 只改注册表、没有代际信号，靠 [`system_proxy_signature`] 兜底——开关一变，
/// 下一次请求立刻重建；环境变量等其它变化最多 60s 后生效。
const HTTP_CLIENT_TTL: Duration = Duration::from_secs(60);

/// 当前系统代理的签名（Windows 注册表 / macOS SystemConfiguration）。
///
/// reqwest 只在**建 client 时**读一次系统代理，之后不会变。把签名放进缓存键，
/// 用户切换 Clash 的「系统代理」后下一次请求就会重建 client，不用等 TTL。
/// 其它平台返回空串（reqwest 自己处理 env / 系统配置）。
///
/// 系统配置读取最多每秒一次：请求路径上只多一次 mutex 读，切换开关 1s 内生效。
pub(crate) fn system_proxy_signature() -> String {
    static CACHE: LazyLock<Mutex<Option<(Instant, String)>>> = LazyLock::new(|| Mutex::new(None));
    const TTL: Duration = Duration::from_secs(1);

    let mut cache = CACHE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some((at, signature)) = cache.as_ref()
        && at.elapsed() < TTL
    {
        return signature.clone();
    }
    let signature = read_system_proxy_signature();
    *cache = Some((Instant::now(), signature.clone()));
    signature
}

fn read_system_proxy_signature() -> String {
    #[cfg(windows)]
    {
        use windows_registry::CURRENT_USER;
        let Ok(settings) =
            CURRENT_USER.open(r"Software\Microsoft\Windows\CurrentVersion\Internet Settings")
        else {
            return String::new();
        };
        let enabled = settings.get_u32("ProxyEnable").unwrap_or(0);
        let server = settings.get_string("ProxyServer").unwrap_or_default();
        format!("{enabled}|{server}")
    }

    #[cfg(target_os = "macos")]
    {
        use system_configuration::core_foundation::base::CFType;
        use system_configuration::core_foundation::dictionary::CFDictionary;
        use system_configuration::core_foundation::number::CFNumber;
        use system_configuration::core_foundation::string::{CFString, CFStringRef};
        use system_configuration::dynamic_store::SCDynamicStoreBuilder;
        use system_configuration::sys::schema_definitions::{
            kSCPropNetProxiesHTTPEnable, kSCPropNetProxiesHTTPPort, kSCPropNetProxiesHTTPProxy,
            kSCPropNetProxiesHTTPSEnable, kSCPropNetProxiesHTTPSPort, kSCPropNetProxiesHTTPSProxy,
            kSCPropNetProxiesSOCKSEnable, kSCPropNetProxiesSOCKSPort, kSCPropNetProxiesSOCKSProxy,
        };

        fn read(
            proxies: &CFDictionary<CFString, CFType>,
            enabled_key: CFStringRef,
            host_key: CFStringRef,
            port_key: CFStringRef,
        ) -> String {
            let enabled = proxies
                .find(enabled_key)
                .and_then(|value| value.downcast::<CFNumber>())
                .and_then(|value| value.to_i32())
                .unwrap_or(0)
                == 1;
            if !enabled {
                return String::new();
            }
            let host = proxies
                .find(host_key)
                .and_then(|value| value.downcast::<CFString>())
                .map(|value| value.to_string())
                .unwrap_or_default();
            match proxies
                .find(port_key)
                .and_then(|value| value.downcast::<CFNumber>())
                .and_then(|value| value.to_i32())
            {
                Some(port) => format!("{host}:{port}"),
                None => host,
            }
        }

        let Some(store) = SCDynamicStoreBuilder::new("breeze-system-proxy").build() else {
            return String::new();
        };
        let Some(proxies) = store.get_proxies() else {
            return String::new();
        };
        format!(
            "http={}|https={}|socks={}",
            read(
                &proxies,
                unsafe { kSCPropNetProxiesHTTPEnable },
                unsafe { kSCPropNetProxiesHTTPProxy },
                unsafe { kSCPropNetProxiesHTTPPort },
            ),
            read(
                &proxies,
                unsafe { kSCPropNetProxiesHTTPSEnable },
                unsafe { kSCPropNetProxiesHTTPSProxy },
                unsafe { kSCPropNetProxiesHTTPSPort },
            ),
            read(
                &proxies,
                unsafe { kSCPropNetProxiesSOCKSEnable },
                unsafe { kSCPropNetProxiesSOCKSProxy },
                unsafe { kSCPropNetProxiesSOCKSPort },
            ),
        )
    }

    #[cfg(not(any(windows, target_os = "macos")))]
    {
        String::new()
    }
}

struct CachedHttpClient {
    generation: u64,
    system_proxy: String,
    built_at: Instant,
    client: ClientWithMiddleware,
}

static HTTP_CLIENT_CACHE: LazyLock<Mutex<Option<CachedHttpClient>>> =
    LazyLock::new(|| Mutex::new(None));

/// 取（必要时重建）普通请求用的 client。
///
/// 以前是每个请求都 `build()` 一次，好处是永远拿到最新配置，代价是每个请求
/// 都要重新建连（TCP + TLS 握手）。现在按「配置代际 + 系统代理签名 + 60s TTL」缓存：
/// - 应用内任何代理 / TLS / 内网策略变更 → 代际 +1 → 下一次请求重建；
/// - 系统代理开关变化 → 签名变化 → 下一次请求重建；
/// - 旧 client 被替换时 drop，连接池随之关闭，不会粘在旧代理上。
fn http_client() -> AnyResult<ClientWithMiddleware> {
    let config = current_http_client_config();
    let generation = http_config_generation();
    let system_proxy = system_proxy_signature();

    let mut cache = HTTP_CLIENT_CACHE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(cached) = cache.as_ref()
        && cached.generation == generation
        && cached.system_proxy == system_proxy
        && cached.built_at.elapsed() < HTTP_CLIENT_TTL
    {
        return Ok(cached.client.clone());
    }

    let client = build_http_client(&config)?;
    *cache = Some(CachedHttpClient {
        generation,
        system_proxy,
        built_at: Instant::now(),
        client: client.clone(),
    });
    Ok(client)
}

fn normalize_http_proxy_url(raw: &str) -> String {
    let value = raw.trim();
    if value.contains("://") {
        return value.to_string();
    }
    format!("http://{value}")
}

fn normalize_socks5_proxy_url(raw: &str) -> String {
    let value = raw.trim();
    if value.contains("://") {
        return value.to_string();
    }
    format!("socks5h://{value}")
}

/// 把当前代理配置应用到 `ClientBuilder`。
///
/// 规则：HTTP 代理优先；`use_http_proxy` 为真但没填地址时允许回落到 SOCKS5。
/// 普通客户端、DoH 查询客户端与域名前置客户端共用这份逻辑，避免行为不一致。
pub(crate) fn apply_proxy_config(
    builder: reqwest::ClientBuilder,
    config: &HttpClientConfig,
) -> AnyResult<reqwest::ClientBuilder> {
    if config.use_http_proxy {
        if let Some(proxy_raw) = config.http_proxy.as_deref() {
            let proxy_url = normalize_http_proxy_url(proxy_raw);
            let proxy = Proxy::all(&proxy_url).with_context(|| {
                crate::tr!("failed-to-parse-http-proxy-address", proxy_url = proxy_url)
            })?;
            return Ok(builder.proxy(proxy));
        }
    }
    if config.use_socks5_proxy {
        if let Some(proxy_raw) = config.socks5_proxy.as_deref() {
            let proxy_url = normalize_socks5_proxy_url(proxy_raw);
            let proxy = Proxy::all(&proxy_url).with_context(|| {
                crate::tr!(
                    "failed-to-parse-socks5-proxy-address",
                    proxy_url = proxy_url
                )
            })?;
            return Ok(builder.proxy(proxy));
        }
    }
    Ok(builder)
}

/// 创建 `reqwest::Client` 时的额外选项（超时 / 直连 / 重定向 / UA）。
#[derive(Debug, Clone, Default)]
pub struct BuildHttpClientOptions {
    pub no_proxy: bool,
    pub timeout: Option<Duration>,
    pub connect_timeout: Option<Duration>,
    pub follow_redirects: Option<bool>,
    pub user_agent: Option<String>,
    /// 只允许 HTTP/1.1。h2 下 hyper 不会把手工 `Host` 头发出去（只用 URI 推出的
    /// `:authority`），所以「连 IP + Host 写回域名」这类请求必须走 h1。
    pub http1_only: bool,
}

/// 按当前/指定全局配置创建 `reqwest::Client`。
pub fn build_http_client(config: &HttpClientConfig) -> AnyResult<ClientWithMiddleware> {
    build_http_client_ex(config, BuildHttpClientOptions::default())
}

/// 创建 HTTP 客户端（可覆盖直连、超时、重定向、UA）。
pub fn build_http_client_ex(
    config: &HttpClientConfig,
    options: BuildHttpClientOptions,
) -> AnyResult<ClientWithMiddleware> {
    let mut builder = Client::builder()
        .timeout(options.timeout.unwrap_or(Duration::from_secs(30)))
        // 复用连接能省掉每请求一次握手；空闲 10s 就断开，这样 Clash 切节点后
        // 最多粘 10s，不会一直走旧线路。
        .pool_max_idle_per_host(4)
        .pool_idle_timeout(Duration::from_secs(10));
    if let Some(connect_timeout) = options.connect_timeout {
        builder = builder.connect_timeout(connect_timeout);
    }
    if !options.follow_redirects.unwrap_or(true) {
        builder = builder.redirect(reqwest::redirect::Policy::none());
    }

    if options.no_proxy {
        builder = builder.no_proxy();
    } else {
        builder = apply_proxy_config(builder, config)?;
    }

    if config.disable_tls_verify {
        builder = builder.danger_accept_invalid_certs(true);
    }
    if let Some(ua) = options.user_agent.as_ref().filter(|s| !s.is_empty()) {
        builder = builder.user_agent(ua);
    }

    // DoH：用户开启且配置了端点时**无条件**挂上，与是否配置代理无关。
    // DoH 查询走自己的 reqwest 客户端（复用同一份代理配置），失败/熔断时
    // `DohResolver` 会自动回落系统解析。
    if let Some(resolver) = super::doh::DohResolver::from_config(config) {
        builder = builder.dns_resolver(resolver);
    }

    let client = builder
        .build()
        .context(crate::tr!("failed-to-create-http-client"))?;
    Ok(wrap_http_client(client))
}

pub fn http_request_promise(
    ctx: Ctx<'_>,
    method: String,
    url: String,
    headers_json: String,
    body: Option<String>,
    body_native_buffer_id: Option<u64>,
) -> rquickjs::Result<QjsValue<'_>> {
    let runtime = runtime_scope(&ctx);
    let id = next_http_request_id();
    let cancel_rx = register_http_cancel(id);

    // 实际 HTTP 请求放进独立 tokio 任务，由 tokio 的 I/O 驱动直接轮询，
    // 不经过 rquickjs 的 Spawner（那会被 JS 事件泵以固定节奏轮询，导致
    // 分块到达的大响应体逐块慢读）。JS 面只等一个 oneshot 结果。
    // 注意：任务跑在独立多线程 runtime 的线程上，那里没有 QJS worker 的
    // thread-local 配置，必须把当前 worker 配置带过去，否则内网拦截/代理
    // 设置会不一致。
    let work_cfg = worker_http_config();
    let cleanup_id = id;
    // 在途配额按插件隔离：先取本插件的信号量，再进异步任务。
    let sem = http_io_sem(&runtime);
    let work = async move {
        set_worker_http_config(work_cfg);
        let permit = match timeout(Duration::from_secs(15), sem.acquire_owned()).await {
            Ok(Ok(permit)) => permit,
            Ok(Err(_)) => {
                return json!({ "ok": false, "error": crate::tr!("http-concurrency-controller-unavailable") })
                    .to_string();
            }
            Err(_) => {
                return json!({ "ok": false, "error": crate::tr!("timed-out-waiting-for-http-concurrency-permit") })
                    .to_string();
            }
        };

        let result = tokio::select! {
            biased;
            _ = cancel_rx => {
                Ok(json!({
                    "ok": false,
                    "error": crate::tr!("request-was-canceled"),
                    "canceled": true
                })
                .to_string())
            }
            r = http_request_inner_async(runtime, method, url, headers_json, body, body_native_buffer_id) => r,
        };

        drop(permit);

        // 请求已结束（成功、失败或被取消），移除取消 sender，
        // 否则每个完成的请求都会在 http_promise_cancel_senders 里留下
        // 一个永远不会被删除的悬空 sender，长会话内存持续增长。
        unregister_http_cancel(cleanup_id);

        match result {
            Ok(payload) => payload,
            Err(error) => json!({ "ok": false, "error": format!("{error:#}") }).to_string(),
        }
    };
    let (result_tx, result_rx) = oneshot::channel::<String>();
    crate::global_runtime().spawn(async move {
        let _ = result_tx.send(work.await);
    });

    // JS 面只等一个 oneshot 结果，不再逐块轮询。
    let future = async move {
        result_rx.await.unwrap_or_else(|_| {
            json!({ "ok": false, "error": crate::tr!("request-execution-cancelled") }).to_string()
        })
    };

    let promise = Promise::wrap_future(&ctx, future)?;
    let obj = promise.into_inner();
    if let Err(e) = obj.set("__hostRequestId", id) {
        unregister_http_cancel(id);
        return Err(e);
    }
    Ok(obj.into_value())
}

pub fn http_request_cancel(id: u64) -> String {
    let sender = http_promise_cancel_senders()
        .lock()
        .expect(&crate::tr!("failed-to-lock-http-promise-cancel-senders"))
        .remove(&id);
    let existed = if let Some(tx) = sender {
        let _ = tx.send(());
        HTTP_EVENT_CANCELED.fetch_add(1, Ordering::Relaxed);
        true
    } else {
        false
    };
    json!({ "ok": true, "canceled": existed }).to_string()
}

/// 为什么 HTTP 必须跑在多线程 runtime 上：QJS worker 用的是 current_thread
/// 单线程 runtime，它的事件循环（pump_jobs）以固定节奏轮询 JS 任务，HTTP
/// 响应体分块到达时无法被及时驱动（实测每块 ~50-80ms），几 MB 的 body 会拖到
/// 数秒甚至超时。这里把请求派发到进程级全局多线程 runtime（[`crate::global_runtime`]），
/// body 读取由 tokio 的 I/O 直接驱动，和直连一致。

async fn http_request_inner_async(
    runtime: String,
    method: String,
    url: String,
    headers_json: String,
    body: Option<String>,
    body_native_buffer_id: Option<u64>,
) -> AnyResult<String> {
    let method =
        Method::from_bytes(method.as_bytes()).context(crate::tr!("failed-to-parse-http-method"))?;

    // ECH：URL 保持域名、SNI 加密（外层是 ECHConfig 的 public_name）。
    // 命中 ECH 表时用专用 client，并跳过 DNS 校验——IP 在登记时已校验，
    // 而这里的 DNS 查询本身可能被污染（前置路径也是同样的处理）。
    let ech_client = super::ech::ech_client_for(&runtime, &url).await;

    // 域名前置：命中前置表的请求会被改写成「连真实 IP + 不发 SNI + 带 Host 头」。
    // 必须在校验目标之前完成改写，否则会先对墙内解析不到的域名做一次 DNS 查询。
    // feature 关闭时该调用被编译成直接返回 None，热路径没有额外开销。
    let front_target = if ech_client.is_some() {
        None
    } else {
        resolve_front_target(&runtime, &url)?
    };
    let request_url = match &front_target {
        Some(target) => super::fronting::front_url_with_ip(&url, &target.ip)?,
        None => url.clone(),
    };

    if ech_client.is_none() {
        ensure_http_target_allowed(&request_url).await?;
    }
    let mut headers_map = Map::new();
    let headers_value: Value = serde_json::from_str(&headers_json)
        .context(crate::tr!("failed-to-parse-http-headers-json"))?;
    let client = match &ech_client {
        Some(client) => client.clone(),
        None => match &front_target {
            Some(_) => super::fronting::cached_front_client(&worker_http_config())?,
            None => http_client()?,
        },
    };
    let mut formdata_body = false;
    let mut plain_headers: Vec<(String, String)> = Vec::new();

    let mut builder = client.request(method, &request_url);

    if let Value::Object(obj) = headers_value {
        for (key, value) in obj {
            if let Some(v) = value.as_str() {
                if key.eq_ignore_ascii_case(HTTP_FORMDATA_BODY_HEADER) {
                    formdata_body = header_truthy(v);
                    continue;
                }
                if key.eq_ignore_ascii_case(HTTP_HTTP1_ONLY_HEADER) {
                    continue;
                }
                plain_headers.push((key, v.to_string()));
            }
        }
    }

    // 调用方是否已经显式带了 `Host` 头。必须在这里先算：`plain_headers`
    // 下面的 `for` 循环会按值消费掉它，之后就不能再借用了。
    let has_host_header = plain_headers
        .iter()
        .any(|(key, _)| key.eq_ignore_ascii_case("host"));

    for (key, value) in plain_headers {
        if formdata_body && key.eq_ignore_ascii_case("content-type") {
            continue;
        }
        builder = builder.header(&key, value);
    }

    // 前置请求必须带 `Host` 头（域名），否则服务端不知道该路由到哪个站点。
    // 只有调用方没有显式设置时才注入，尊重调用方。
    if let Some(target) = &front_target {
        if !has_host_header {
            let host_value = front_host_header_value(&target.host, &request_url);
            builder = builder.header("Host", host_value);
        }
    }

    if formdata_body {
        let raw_plan =
            body.ok_or_else(|| anyhow!(crate::tr!("formdata-request-missing-body-payload")))?;
        let plan = parse_host_formdata_plan(&raw_plan)?;
        let form = build_multipart_form(plan)?;
        builder = builder.multipart(form);
    } else if let Some(native_buffer_id) = body_native_buffer_id {
        let bytes = native_buffer_take_raw(native_buffer_id).ok_or_else(|| {
            anyhow!(crate::tr!(
                "request-body-nativebufferid-does-not-exist",
                native_buffer_id = native_buffer_id
            ))
        })?;
        builder = builder.body(bytes);
    } else if let Some(content) = body {
        builder = builder.body(content);
    }

    // 计时起点放在 `send()` 之前：`ttfbMs` 因此包含 TCP 建连 + TLS 握手 +
    // 服务端处理 + 首字节，与 `fronting.probe` 的 `ttfbMs` 同义。
    let request_started = Instant::now();

    // 连接级失败才把 IP 标记为不健康：4xx/5xx 说明这个 IP 活着，
    // 只是请求被站点拒绝（风控 / 限流），换 IP 也未必有用。
    // ECH 失败时用普通链路再试一次：ECH 只是「更好的握手」，不该让请求直接死掉。
    // `try_clone` 对流式 body（multipart）返回 None，这时没有回退，行为与之前一致。
    let request = builder
        .build()
        .context(crate::tr!("failed-to-send-http-request"))?;
    let ech_fallback = if ech_client.is_some() {
        request.try_clone()
    } else {
        None
    };
    let response = match client.execute(request).await {
        Ok(response) => response,
        Err(error) => {
            if let Some(target) = &front_target {
                super::fronting::mark_front_host_unhealthy(&runtime, &target.ip);
            }
            let Some(fallback) = ech_fallback else {
                return Err(error).context(crate::tr!("failed-to-send-http-request"));
            };
            // ECH 的 TLS 抖动（如 InvalidContentType）重建一次大概率就好，
            // 丢掉缓存让下一次请求重新拉 ECHConfig / 换 hint IP。
            super::ech::invalidate_ech_client(&runtime, &url);
            tracing::debug!("ech: request failed, retrying over the plain path: {error}");
            http_client()?
                .execute(fallback)
                .await
                .context(crate::tr!("failed-to-send-http-request"))?
        }
    };
    let ttfb = request_started.elapsed();
    // 实际 TCP 对端的 IP：未前置时是 DNS 解析结果，走代理时是代理地址，
    // 前置时就是表里的那个 IP。必须在 `bytes()` 消费掉 response 之前取。
    // 非 TCP 传输（unix socket / 命名管道）拿不到，为 None。
    let peer_ip = response
        .remote_addr()
        .map(|addr| addr.ip().to_string())
        .unwrap_or_default();
    let status = response.status();
    // 回报给 JS 的 URL 始终是原始域名 URL：插件要按域名做缓存 / 去重 /
    // 重定向判定，不应该看到直连 IP。实际 IP 另附在 frontHost / frontIp 字段里。
    let final_url = match &front_target {
        Some(_) => url.clone(),
        None => response.url().to_string(),
    };

    for (name, value) in response.headers() {
        let value_text = value
            .to_str()
            .context(crate::tr!("failed-to-parse-http-response-headers"))?
            .to_string();
        headers_map.insert(name.to_string(), Value::String(value_text));
    }

    // body 计时只算「收到响应头 → body 读完」，不含建连与首字节，
    // 所以 `offloadedBytes / bodyMs` 就是这次请求的实际吞吐，不受 RTT 干扰。
    let body_started = Instant::now();
    let body_bytes = response
        .bytes()
        .await
        .context(crate::tr!("failed-to-read-http-response-body-bytes"))?
        .to_vec();
    let body_elapsed = body_started.elapsed();

    let native_buffer_id = NATIVE_BUF_ID.fetch_add(1, Ordering::Relaxed);
    let body_len = body_bytes.len();

    {
        let mut pool = native_pool()
            .lock()
            .expect(&crate::tr!("failed-to-lock-native-buffer-pool"));
        pool.insert(
            native_buffer_id,
            NativeBufferEntry::with_http_response(
                body_bytes,
                NativeBufferHttpResponse {
                    status_code: status.as_u16(),
                    body_length: body_len as u64,
                },
            ),
        );
    }

    let mut payload = json!({
        "ok": true,
        "status": status.as_u16(),
        "statusText": status.canonical_reason().unwrap_or(""),
        "url": final_url,
        "headers": headers_map,
        "body": "",
        "offloaded": true,
        "nativeBufferId": native_buffer_id,
        "offloadedBytes": body_len,
        // TCP 对端 IP。未前置时就是域名解析到的地址，插件可以用它观察
        // DNS 实际选中的 IP；走代理时是代理地址，不能当成目标 IP 用。
        "peerIp": peer_ip,
        // 计时信息交给插件自行判断：宿主只测量，不做优选决策。
        // `ttfbMs` 含建连/握手/首字节；`bodyMs` 只含 body 传输；
        // 吞吐 ≈ offloadedBytes / bodyMs（小响应会被 RTT 主导，插件应自己设门槛）。
        "ttfbMs": ttfb.as_millis() as u64,
        "bodyMs": body_elapsed.as_millis() as u64
    });
    // 调试信息：本次请求是否走了域名前置，以及实际连的哪个 IP。
    if let Some(target) = &front_target {
        if let Some(obj) = payload.as_object_mut() {
            obj.insert("frontHost".to_string(), Value::String(target.host.clone()));
            obj.insert("frontIp".to_string(), Value::String(target.ip.clone()));
        }
    }
    Ok(payload.to_string())
}

/// 构造 `Host` 头的值。
///
/// 端口非默认时必须带上端口号（与浏览器行为一致）：
/// `example.com` -> `example.com`，`example.com:8443` -> `example.com:8443`。
/// `Url::port()` 对默认端口返回 `None`，所以这里不需要再判断 scheme。
fn front_host_header_value(host: &str, request_url: &str) -> String {
    match reqwest::Url::parse(request_url)
        .ok()
        .and_then(|parsed| parsed.port())
    {
        Some(port) => format!("{host}:{port}"),
        None => host.to_string(),
    }
}

/// 解析本次请求的域名前置目标。
///
/// `host-fronting` 关闭时直接返回 `None`，避免在每次请求的热路径上做
/// URL 解析与全局状态加锁。
#[cfg(feature = "host-fronting")]
fn resolve_front_target(
    runtime: &str,
    url: &str,
) -> AnyResult<Option<super::fronting::FrontTarget>> {
    super::fronting::resolve_front_target(runtime, url)
}

#[cfg(not(feature = "host-fronting"))]
fn resolve_front_target(
    _runtime: &str,
    _url: &str,
) -> AnyResult<Option<super::fronting::FrontTarget>> {
    Ok(None)
}

async fn ensure_http_target_allowed(url: &str) -> AnyResult<()> {
    let config = worker_http_config();
    if config.allow_private_network {
        return Ok(());
    }

    let parsed =
        reqwest::Url::parse(url).with_context(|| crate::tr!("failed-to-parse-url", url = url))?;
    let host = parsed
        .host_str()
        .ok_or_else(|| anyhow!(crate::tr!("url-missing-host", url = url)))?
        .trim();

    if host.eq_ignore_ascii_case("localhost") || host.to_ascii_lowercase().ends_with(".localhost") {
        return Err(anyhow!(crate::tr!("blocked-intranet-request", host = host)));
    }

    if let Ok(ip) = host.parse::<IpAddr>() {
        if is_private_or_local_ip(ip) {
            return Err(anyhow!(crate::tr!("blocked-intranet-request", host = host)));
        }
        return Ok(());
    }

    let port = parsed.port_or_known_default().unwrap_or(80);
    let resolved = lookup_host((host, port))
        .await
        .with_context(|| crate::tr!("failed-to-parse-domain", host = host))?;
    for socket in resolved {
        if is_private_or_local_ip(socket.ip()) {
            return Err(anyhow!(crate::tr!("blocked-intranet-request", host = host)));
        }
    }

    Ok(())
}

fn is_private_or_local_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(ipv4) => is_private_or_local_ipv4(ipv4),
        IpAddr::V6(ipv6) => is_private_or_local_ipv6(ipv6),
    }
}

fn is_private_or_local_ipv4(ip: Ipv4Addr) -> bool {
    let [a, b, ..] = ip.octets();
    ip.is_loopback()
        || ip.is_private()
        || ip.is_link_local()
        || ip.is_unspecified()
        || (a == 100 && (64..=127).contains(&b))
}

/// IPv6 内网 / 保留地址判断。
///
/// 除了直接的本地地址段，还必须处理**把 IPv4 内嵌在 IPv6 里**的几种形式：
/// 它们的 `is_loopback` / `is_unique_local` 全部返回 false，不单独判断就能
/// 绕过内网拦截（`::ffff:127.0.0.1` 打到本机、`::ffff:169.254.169.254` 打到
/// 云元数据服务）。
pub(crate) fn is_private_or_local_ipv6(ip: Ipv6Addr) -> bool {
    // 本地段先判，避免被下面的内嵌分支提前返回。
    if ip.is_loopback()
        || ip.is_unspecified()
        || ip.is_unique_local()
        || ip.is_unicast_link_local()
        || ip.is_multicast()
    {
        return true;
    }
    // IPv4-mapped：::ffff:0:0/96
    if let Some(v4) = ip.to_ipv4_mapped() {
        return is_private_or_local_ipv4(v4);
    }
    // 6to4 / NAT64：IPv4 内嵌在地址里，同样要按 IPv4 规则判。
    if let Some(v4) = embedded_ipv4(ip) {
        return is_private_or_local_ipv4(v4);
    }
    false
}

/// 取出 6to4 / NAT64 地址里内嵌的 IPv4。
fn embedded_ipv4(ip: Ipv6Addr) -> Option<Ipv4Addr> {
    let segments = ip.segments();
    let octets = ip.octets();
    // 6to4：2002:AABB:CCDD::/48，AABB:CCDD 就是 IPv4 的前两段。
    if segments[0] == 0x2002 {
        return Some(Ipv4Addr::new(octets[2], octets[3], octets[4], octets[5]));
    }
    // NAT64：64:ff9b::/96，后 32 位是 IPv4。
    if segments[..6] == [0x0064, 0xff9b, 0, 0, 0, 0] {
        return Some(Ipv4Addr::new(
            octets[12], octets[13], octets[14], octets[15],
        ));
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn blocked_request_middleware_returns_before_io() {
        let previous = is_http_requests_blocked();
        set_http_requests_blocked(true);
        let client = build_http_client(&HttpClientConfig {
            use_http_proxy: false,
            use_socks5_proxy: false,
            ..Default::default()
        })
        .expect("middleware client should build without network I/O");
        let result = client.get("http://192.0.2.1/").send().await;
        set_http_requests_blocked(previous);

        let error = result.expect_err("blocked request should fail");
        assert!(error.is_middleware());
        assert!(error.to_string().contains("HTTP"));
    }

    /// DoH 与代理无关：开启且有端点就挂，关掉或清空端点就不挂。
    #[test]
    fn doh_resolver_follows_config_not_proxy() {
        let with_proxy = HttpClientConfig {
            use_http_proxy: true,
            http_proxy: Some("http://127.0.0.1:7890".to_string()),
            ..Default::default()
        };
        assert!(super::super::doh::DohResolver::from_config(&with_proxy).is_some());

        let disabled = HttpClientConfig {
            doh_enabled: false,
            ..Default::default()
        };
        assert!(super::super::doh::DohResolver::from_config(&disabled).is_none());

        let no_providers = HttpClientConfig {
            doh_providers: Vec::new(),
            ..Default::default()
        };
        assert!(super::super::doh::DohResolver::from_config(&no_providers).is_none());
    }

    /// 未钉住且代际过期的缓存要被丢弃，回落到全局配置。
    ///
    /// 这就是「用户改代理 / 改内网策略后已加载插件立刻生效」的机制。
    #[test]
    fn stale_unpinned_worker_config_is_refreshed() {
        let global = current_http_client_config();

        // 伪造一份「代际过期、未钉住」的缓存，内容故意和全局不同。
        WORKER_HTTP_CONFIG.with(|c| {
            let mut stale = global.clone();
            stale.allow_private_network = !global.allow_private_network;
            *c.borrow_mut() = Some((u64::MAX, stale, false));
        });

        assert_eq!(worker_http_config(), global);
    }

    /// 钉住的配置不受代际影响（测试靠这个语义：临时改全局后建 runtime，
    /// 再把全局恢复，runtime 仍用快照那份）。
    #[test]
    fn pinned_worker_config_ignores_stale_generation() {
        let mut pinned = current_http_client_config();
        pinned.allow_private_network = !pinned.allow_private_network;
        set_worker_http_config(pinned.clone());

        // 推进代际（不改全局，其他线程重读到的仍是同一份配置）。
        HTTP_CONFIG_GENERATION.fetch_add(1, Ordering::Release);

        assert_eq!(worker_http_config(), pinned);
    }

    /// IPv4 内嵌在 IPv6 里的形式必须按 IPv4 规则拦截，否则能绕过内网检查。
    #[test]
    fn ipv6_embedded_ipv4_forms_are_blocked() {
        for addr in [
            "::1",
            "::",
            "fc00::1",
            "fe80::1",
            "ff02::1",
            // IPv4-mapped ::ffff:0:0/96
            "::ffff:127.0.0.1",
            "::ffff:10.0.0.1",
            "::ffff:192.168.1.1",
            "::ffff:169.254.169.254",
            "::ffff:100.64.0.1",
            // 6to4 2002::/16
            "2002:7f00:0001::",
            "2002:0a00:0001::",
            "2002:a9fe:a9fe::",
            // NAT64 64:ff9b::/96
            "64:ff9b::7f00:1",
            "64:ff9b::a00:1",
            "64:ff9b::a9fe:a9fe",
        ] {
            let ip: Ipv6Addr = addr.parse().expect("test address should parse");
            assert!(is_private_or_local_ipv6(ip), "{addr} should be blocked");
        }
    }

    #[test]
    fn ipv6_public_addresses_are_allowed() {
        for addr in [
            "2606:4700:3032::6815:2dee",
            "2001:4860:4860::8888",
            // 6to4 包裹公网 IPv4 不算内网
            "2002:6814:200f::",
        ] {
            let ip: Ipv6Addr = addr.parse().expect("test address should parse");
            assert!(!is_private_or_local_ipv6(ip), "{addr} should be allowed");
        }
    }

    /// 响应负载必须带上计时与字节数，插件靠这些字段自己做 IP 优选。
    #[test]
    fn response_payload_carries_timing_and_size() {
        let (base_url, tx, handle) = crate::tests::spawn_test_server(1);
        let script = format!(
            r#"
              (async () => {{
                const raw = await __http_request_promise(
                  "GET", "{base_url}/echo", "{{}}", null, null
                );
                const data = JSON.parse(raw);
                return JSON.stringify({{
                  ok: data.ok,
                  bytes: data.offloadedBytes,
                  ttfbIsNumber: typeof data.ttfbMs === "number",
                  bodyIsNumber: typeof data.bodyMs === "number",
                  ttfbMs: data.ttfbMs,
                  bodyMs: data.bodyMs
                }});
              }})()
            "#
        );

        let result = crate::tests::run_async_script(&script).expect("script should run");
        let parsed: serde_json::Value =
            serde_json::from_str(&result).expect("result should be JSON");

        assert_eq!(parsed["ok"], serde_json::json!(true));
        assert_eq!(parsed["ttfbIsNumber"], serde_json::json!(true));
        assert_eq!(parsed["bodyIsNumber"], serde_json::json!(true));
        assert!(
            parsed["bytes"].as_u64().unwrap_or(0) > 0,
            "offloadedBytes should be the body size: {parsed:?}"
        );

        let _ = tx.send(());
        let _ = handle.join();
    }

    /// `fetch()` 得到的 Response 要能拿到宿主侧的测量信息（`hostMeta`）。
    #[test]
    fn response_host_meta_is_exposed_to_js() {
        let (base_url, tx, handle) = crate::tests::spawn_test_server(1);
        let script = format!(
            r#"
              (async () => {{
                const res = await fetch("{base_url}/echo");
                const bytes = (await res.arrayBuffer()).byteLength;
                const meta = res.hostMeta;
                return JSON.stringify({{
                  hasMeta: meta !== null && typeof meta === "object",
                  bytes: meta && meta.bytes,
                  bodyLength: bytes,
                  ttfbIsNumber: meta && typeof meta.ttfbMs === "number",
                  bodyIsNumber: meta && typeof meta.bodyMs === "number",
                  ip: meta && meta.ip,
                  host: meta && meta.host,
                  peerIp: meta && meta.peerIp
                }});
              }})()
            "#
        );

        let result = crate::tests::run_async_script(&script).expect("script should run");
        let parsed: serde_json::Value =
            serde_json::from_str(&result).expect("result should be JSON");

        assert_eq!(parsed["hasMeta"], serde_json::json!(true));
        assert_eq!(parsed["ttfbIsNumber"], serde_json::json!(true));
        assert_eq!(parsed["bodyIsNumber"], serde_json::json!(true));
        assert_eq!(
            parsed["bytes"].as_u64(),
            parsed["bodyLength"].as_u64(),
            "hostMeta.bytes should match the body length: {parsed:?}"
        );
        // 未走前置时没有前置 IP / 域名，但 TCP 对端 IP 必须能拿到。
        assert_eq!(parsed["ip"], serde_json::json!(null));
        assert_eq!(parsed["host"], serde_json::json!(null));
        assert_eq!(
            parsed["peerIp"],
            serde_json::json!("127.0.0.1"),
            "peerIp should be the resolved address of the test server: {parsed:?}"
        );

        let _ = tx.send(());
        let _ = handle.join();
    }

    /// 在途配额按插件隔离：占满 A 的许可不影响 B。
    #[test]
    fn http_io_sem_is_per_runtime() {
        let runtime_a = "test-http-quota-a";
        let runtime_b = "test-http-quota-b";
        release_http_io_sem(runtime_a);
        release_http_io_sem(runtime_b);

        let a = http_io_sem(runtime_a);
        let b = http_io_sem(runtime_b);
        assert_eq!(a.available_permits(), HTTP_PER_PLUGIN_MAX_IN_FLIGHT);
        assert_eq!(b.available_permits(), HTTP_PER_PLUGIN_MAX_IN_FLIGHT);

        // 同一个 runtime 拿到的是同一个信号量，否则配额形同虚设。
        let a_again = http_io_sem(runtime_a);
        assert!(Arc::ptr_eq(&a, &a_again));

        // 占用 A 的配额不影响 B。
        let permit = a
            .clone()
            .try_acquire_owned()
            .expect("A should have a permit");
        assert_eq!(a.available_permits(), HTTP_PER_PLUGIN_MAX_IN_FLIGHT - 1);
        assert_eq!(b.available_permits(), HTTP_PER_PLUGIN_MAX_IN_FLIGHT);
        drop(permit);

        // 回收后重建拿到的是全新配额。
        release_http_io_sem(runtime_a);
        let a_fresh = http_io_sem(runtime_a);
        assert!(!Arc::ptr_eq(&a, &a_fresh));
        assert_eq!(a_fresh.available_permits(), HTTP_PER_PLUGIN_MAX_IN_FLIGHT);

        release_http_io_sem(runtime_a);
        release_http_io_sem(runtime_b);
    }

    #[test]
    fn host_header_omits_default_port() {
        assert_eq!(
            front_host_header_value("e-hentai.org", "https://172.66.132.196/g/1/"),
            "e-hentai.org"
        );
        assert_eq!(
            front_host_header_value("e-hentai.org", "https://172.66.132.196:443/g/1/"),
            "e-hentai.org"
        );
    }

    #[test]
    fn host_header_includes_custom_port() {
        assert_eq!(
            front_host_header_value("e-hentai.org", "https://172.66.132.196:8443/g/1/"),
            "e-hentai.org:8443"
        );
    }

    #[test]
    fn host_header_falls_back_on_invalid_url() {
        assert_eq!(
            front_host_header_value("e-hentai.org", "not a url"),
            "e-hentai.org"
        );
    }
}
use super::*;
