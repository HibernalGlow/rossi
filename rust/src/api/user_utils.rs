pub fn setup_default_user_utils() {
    setup_backtrace();
}

fn setup_backtrace() {
    if std::env::var("RUST_BACKTRACE").is_err_and(|e| e == std::env::VarError::NotPresent) {
        unsafe { std::env::set_var("RUST_BACKTRACE", "1") };
    } else {
        tracing::debug!("Skip setup RUST_BACKTRACE because there is already environment variable");
    }
}

pub(crate) fn setup_log_to_console(enabled: bool) {
    static INIT: std::sync::Once = std::sync::Once::new();
    INIT.call_once(|| {
        if !enabled {
            return;
        }
        #[allow(unused_imports)]
        use tracing_subscriber::{EnvFilter, fmt, prelude::*};

        use crate::api::logger::BoxedFormatter;

        let filter = EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| EnvFilter::new(default_log_level(enabled)));

        #[cfg(target_os = "android")]
        {
            use tracing_logcat::{LogcatMakeWriter, LogcatTag};

            let writer = LogcatMakeWriter::new(LogcatTag::Fixed("windcore".to_owned()))
                .expect("Failed to initialize logcat writer");

            init_subscriber(
                tracing_subscriber::registry().with(filter).with(
                    fmt::layer()
                        .with_writer(writer)
                        .event_format(BoxedFormatter { with_ansi: false }),
                ),
                "Android",
            );

            tracing::info!("Tracing initialized (Android)");
            return;
        }

        #[cfg(any(target_os = "ios", target_os = "macos"))]
        {
            init_subscriber(
                tracing_subscriber::registry()
                    .with(filter)
                    .with(fmt::layer().event_format(BoxedFormatter { with_ansi: true })),
                "iOS/macOS",
            );
            tracing::info!("Tracing initialized (iOS/macOS)");
            return;
        }

        #[cfg(target_family = "wasm")]
        {
            init_subscriber(
                tracing_subscriber::registry()
                    .with(filter)
                    .with(fmt::layer().event_format(BoxedFormatter { with_ansi: false })),
                "WASM",
            );
            tracing::info!("Tracing initialized (WASM)");
            return;
        }

        #[cfg(all(
            not(target_family = "wasm"),
            not(target_os = "android"),
            not(target_os = "ios"),
            not(target_os = "macos")
        ))]
        {
            use crate::api::logger::ChunkedStdoutMakeWriter;

            // Windows 上 `flutter run` 通过异步管道抓子进程 stdout/stderr，
            // Rust std 对异步 handle 的同步写在返回 PENDING 时直接 rtabort
            // ("I/O error: operation failed to complete synchronously", #81357)。
            // `BoxedFormatter` 把整个 7 行盒子拼成一个字符串一次 `write!`，
            // 巨型单行（base64 dataURL）下单次 `NtWriteFile` 远超管道缓冲，
            // 风暴时必 abort。Dart 侧 `logger` 是逐行小写入所以从不触发。
            // 本 writer 输出字节与原来完全一致（格式、内容一字不落），
            // 只是业务线程把整盒推入队列就返回，唯一的后台写线程按 4KB
            // 分块写 stdout，每块都能同步完成（见 ChunkedStdoutMakeWriter）。
            init_subscriber(
                tracing_subscriber::registry().with(filter).with(
                    fmt::layer()
                        .with_writer(ChunkedStdoutMakeWriter {})
                        .event_format(BoxedFormatter { with_ansi: true }),
                ),
                "Desktop",
            );
            tracing::info!("Tracing initialized (Desktop)");
        }
    });
}

fn init_subscriber<S>(subscriber: S, platform: &str)
where
    S: tracing::Subscriber + Send + Sync + 'static,
    for<'a> S: tracing_subscriber::registry::LookupSpan<'a>,
{
    use tracing_log::LogTracer;
    use tracing_subscriber::{fmt, prelude::*};

    use crate::api::logger::LogHttpMakeWriter;

    let subscriber = subscriber.with(
        fmt::layer()
            .with_writer(LogHttpMakeWriter {})
            .with_ansi(false),
    );

    tracing::dispatcher::set_global_default(subscriber.into())
        .unwrap_or_else(|_| panic!("Failed to initialize tracing subscriber ({platform})"));

    // 第三方 crate 走 `log` 门面时（rustls 的 "Not resuming" / "Using ciphersuite" /
    // "Sending warning alert"、html5ever / selectors 等），`tracing-log` 会把它们统一
    // 转发成 metadata target = "log" 的 tracing 事件，`EnvFilter` 无法按 crate 名过滤。
    // 本项目自己的代码只用 `tracing`，所以 `log` 记录全是第三方的；DEBUG 级别几乎
    // 全是噪音，默认在 LogTracer 层掐掉（保留 INFO/WARN/ERROR，rustls 的 ECH、
    // 证书告警仍在）。显式设置 RUST_LOG 时交回 EnvFilter 自行决定，方便排查 TLS。
    let log_max_level = if std::env::var_os("RUST_LOG").is_some() {
        log::LevelFilter::Trace
    } else {
        log::LevelFilter::Info
    };

    LogTracer::builder()
        .with_max_level(log_max_level)
        .ignore_crate("html5ever")
        .ignore_crate("selectors")
        .init()
        .unwrap_or_else(|_| panic!("Failed to initialize log tracer ({platform})"));
}

fn default_log_level(enabled: bool) -> String {
    if enabled {
        // hickory（DoH/DNS 解析栈）在 debug 级别会刷出海量 `querying:` /
        // `connecting` / DNSSEC 校验日志，对排查业务问题没有帮助，默认整栈静音。
        concat!(
            "debug,hyper_util=warn,reqwest=warn,h2=warn,",
            "hickory_net=off,hickory_proto=off,hickory_resolver=off"
        )
        .to_string()
    } else {
        "warn,hickory_net=off,hickory_proto=off,hickory_resolver=off".to_string()
    }
}
