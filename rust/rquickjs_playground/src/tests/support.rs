use crate::web_runtime::{HttpClientConfig, current_http_client_config};

/// 测试要访问本地服务，给 runtime 一份放行内网的配置。
///
/// 刻意**不**修改全局配置：历史上多个用例靠临时改全局来放行内网，并行执行时
/// 会互相干扰导致偶发失败。现在改成每个 runtime 自带一份配置。
pub fn private_network_http_config() -> HttpClientConfig {
    let mut config = current_http_client_config();
    config.allow_private_network = true;
    config
}

fn run_with(script: &str, name: &str, fs: bool) -> Result<String, Box<dyn std::error::Error>> {
    let runtime = crate::host_runtime::AsyncHostRuntime::builder(name)
        .filesystem(fs)
        .http_config_override(Some(private_network_http_config()))
        .build()?;
    let task = runtime.spawn(script)?;
    task.wait().map_err(|e| e.into())
}

pub fn run_async_script(script: &str) -> Result<String, Box<dyn std::error::Error>> {
    run_with(script, "test-web-runtime", false)
}

pub fn run_async_script_with_fs(script: &str) -> Result<String, Box<dyn std::error::Error>> {
    run_with(script, "test-web-runtime-fs", true)
}
