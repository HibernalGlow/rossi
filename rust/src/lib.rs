pub mod api;
pub mod compressed;

/// 全局 HTTP 客户端配置是进程级共享状态。
///
/// 读写它的测试必须串行，否则会出现「A 用例临时设了个死代理，B 用例正巧
/// 在这期间建客户端」这种随机失败。相关用例统一先拿这把锁。
#[cfg(test)]
pub(crate) static HTTP_CONFIG_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
pub mod decode;
mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
pub mod memory;
pub mod qjs;

#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_zephyr_breeze_MainActivity_initRustlsPlatformVerifier(
    mut env: jni::JNIEnv<'_>,
    _: jni::objects::JClass<'_>,
    context: jni::objects::JObject<'_>,
) {
    let _ = env.with_env(|env| {
        rustls_platform_verifier::android::init_with_env(env, context)?;
        Ok::<(), jni::errors::Error>(())
    });
}
