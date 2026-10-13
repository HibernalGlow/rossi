# 上游同步记录

## 2026-10-13

| 来源 | 先前内容基准 | 本次内容基准 |
|---|---|---|
| Breeze | `5853c2b4` | `68bebb2b83130c65ba3f6f709ca5413d2ae184d4` |
| mImageViewer | `8d95fffe`（v4.1.0） | `bb6ca0c665544da10b1acb061b590512acd0a4a4`（v4.6.0） |

本次按用户要求，重叠功能优先采用上游实现。Breeze 跟进 21 个提交，采用上游的
阅读设置组件、单本稀疏覆盖与 v12 迁移、章节分组、插件详情、图形验证码、自定义登录
标签、Freezed 状态及下载持续重试逻辑；QuickJS 原生二进制通道移除 JSON 兜底。
Rossi 独有的泳道弹窗、输入绑定、自适应背景、翻页预览、悬停、翻译和媒体控制保留在
独立扩展与薄适配中。下载队列的限流识别保留，操作内重试循环采用上游实现。

Flutter 配置跟到上游 3.47.6，Android minSdk 为 26，缺少签名密钥的 fork CI
采用上游的跳过逻辑。Rossi 包版本仍是 `0.1.0+1`，FRB 仍锁定 `2.12.0`，
代码生成脚本按项目锁定版本安装生成器，避免生成器与运行库不匹配。

mImageViewer 的 gitlink 与源码移植已同步；范围、跨平台差异和未接入功能见
[移植模块同步说明](local-core-vendored-modules.md)。不引入上游 Windows 应用的
UI、转换缓存或未具备消费者的 EPUB/LibRaw 链。

验证：统一代码生成完成；本地核心 462 项、QuickJS 原生通道 31 项、Flutter 相关
回归与 RAR 首卷识别 6 项通过；ObjectBox 旧实体/属性 UID 保留。静态分析没有 error，已有 warning/info
尚存。本机 Flutter 为 3.47.4（Dart 3.13.3），尚未验证 3.47.6 和各平台完整安装包。

## 下次同步

Breeze 在 GitButler 中作为内容提交集成，不新增上游 merge parent。因此 Git 的
`merge-base` 不能代替上表的内容基准；下次三方合并必须以 `68bebb2b` 为 base，
避免重复应用上次变更。不要覆盖 Rossi 独有接口或其他工作分支。

mImageViewer 更新 gitlink 后运行 `python3 script/sync_vendored_modules.py`，
检查所有 `PORTS` 差异并更新 `pinned_at`；同时人工审查未登记的 `path_key`、
`thumb_loader`、`catalog`、`fast_resize` 与显示几何切片。
