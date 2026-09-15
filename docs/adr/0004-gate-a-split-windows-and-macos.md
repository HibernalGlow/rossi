# Gate A 拆分为 A-W（已通过）与 A-M（待验，不阻塞）

Gate A 原本是一条「Windows 与 macOS 都必须性能稳定达标才能进 Phase 2」的门，但本机没有 macOS 机器，
它会把项目无限期卡在验证上。我们决定拆成两条：**Gate A-W 已通过**（Rust/wgpu → 自建共享纹理 →
Flutter 合成链，Windows / D3D12，像素零误差，70 s 浸泡 162–164 fps、内存平坦），
**Gate A-M 待验**，且**不阻塞 Phase 1–2**。

## Consequences

- `docs/gate-a/README.md` 的全部验收记录保留为「已知边界」，不因拆分而作废。
- Gate A-M 是显式技术债：Metal 路径、macOS 的 SR 后端选择、
  以及那组带宽数字（190 GB/s、4K 单页 0.348 ms）都需要在 A-M 里重测。
- 「Gate A 未通过」不再作为不开工的理由。
