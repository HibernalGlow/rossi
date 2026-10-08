# fork 上的补丁：让无头 CLI 能接任意 OpenAI 兼容端点

分支 `ci/koharu-cli`（`HibernalGlow/koharu`），基线 = 上游 `0.83.5`。改动全部压在**挂载点**级别，
上游函数体没有重写，方便日后 merge。

## 上游的限制（为什么要打）

- `crates/koharu-pipeline/src/bin/run.rs` 把 `provider: Provider::Local` **写死**，且用
  `Config::memory(ProvidersConfig::default())`（**不读** `~/.koharu/config.toml`）⇒
  `--llm` 只能取编译期钉死表里的 id，连绝对路径都报 `unknown local translator '<值>'`。
- `openai_compatible::translate` 的 `response_format` 只发 `{"type":"json_schema",…strict…}`；
  DeepSeek 这类端点回 400 `This response_format type is unavailable now`。

## 改了什么

| 文件 | 改动 |
|---|---|
| `crates/koharu-pipeline/src/bin/run/endpoint.rs` | **新文件**：后端选择（local / openai-compatible）、providers 构造、`--response-format` 的 CLI 枚举与映射 |
| `crates/koharu-pipeline/src/bin/run.rs` | `#[path = "run/endpoint.rs"] mod endpoint;` + 四个参数（`--provider/--base-url/--vision/--response-format`）+ 两处替换 |
| `crates/koharu-translator/src/remote/openai_compatible.rs` | `OpenAiCompatibleConfig` 增 `response_format` 字段（默认 `JsonSchema`，与上游等价）；请求里那一档按配置生成，`None` 时字段整个不发 |
| `crates/koharu-translator/src/remote/mod.rs` / `src/lib.rs` | 各 +1 行 re-export |
| `crates/koharu-secrets/src/lib.rs` | `get()` 增加**环境变量优先**：`KOHARU_SECRET_<KEY大写去横杠>`（如 `KOHARU_SECRET_OPENAI_COMPATIBLE`），无头运行不必写钥匙串 |
| `crates/koharu-renderer/src/config.rs` | `TypesettingConfig` 增 `min_font_size`（默认 = 上游常量 9.0）与 `font_size`（默认 `None` = 上游行为）|
| `crates/koharu-renderer/src/renderer.rs` | `Traversal` 带这两个值；`TextNodeDescriptor` 的 `font_size` / `minimum_font_size` / `auto_fit` 三行接线，其中 `font_size` **按 `is_bubble` 分流**（只给框外文字）|
| `.github/workflows/koharu-cli-run.yml` | 矩阵扩到 macos-14 / ubuntu-24.04-arm / windows-latest，产物 `koharu-run-<target>.tar.gz` |

## 排版那两个旋钮（为什么必须自己加）

- 上游只有 `min_font_size` 语义的那一档（硬编码常量 `MINIMUM_FONT_SIZE = 9.0`），且
  `text_renderer.rs` 的 `automatic_maximum()` 对**非气泡文字**直接返回 `24.0`；
  又因为 `minimum = descriptor.minimum_font_size.min(maximum)`，**下限被上限掐死** ⇒
  框外那类字无论把下限抬到多高都不会变大（27 页实测 56 / 200 两轮，1:1 裁切像素一致）。
- 所以真正的杠杆是「强制字号」，但它对气泡是负收益（21 页实测 64 把字撑到画面上），
  故按 `is_bubble` 分流：气泡保留上游自动适配，框外文字吃 `font_size`。
- 这两个字段都走 `~/.koharu/config.toml` 的 `[typesetting]`，**热重载、不加命令行参数**；
  默认值与上游逐字等价，不写配置就等于没改。


## 两个编译期的坑（都实测）

- **bin 的 crate root 在 `src/bin/` 下**：`mod endpoint;` 默认找 `src/bin/endpoint.rs`（E0583）。
  放 `src/bin/run/endpoint.rs` 是为了不让 cargo 把它当独立 bin ⇒ 必须 `#[path = "run/endpoint.rs"]`。
- `koharu-pipeline` 没有直接依赖 `serde_json`，所以端点那段**用字段赋值 + 类型推导**（`Some(url.parse()?)`）
  构造配置，不引入新依赖。

## 怎么和上游同步

- 只在这一个文件里做了「同一处替换」，上游改 run.rs 时冲突面就是那几行；
- `--response-format` 的默认值刻意保持 `json-schema`（= 上游行为），所以不传参数的调用与上游逐字等价；
- 新能力全部由新文件 `endpoint.rs` 承载；要回退删掉 `#[path] mod` + 参数即可。
