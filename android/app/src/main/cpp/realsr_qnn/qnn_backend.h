// Ported from HaoweiLi97/mihon_img_upscale (Apache License 2.0).
// Upstream files: app/src/main/cpp/{qnn_backend,spatial_qnn_runtime}.{h,cpp},
// periodic_texture_guard.h, monochrome_guard.h, qnn_context_bridge.cpp.
// Local deviations are marked with `ROSSI:` comments and registered in
// docs/upstream-sync.md.

#ifndef ROSSI_QNN_BACKEND_H
#define ROSSI_QNN_BACKEND_H

#include <atomic>
#include <cstdint>
#include <string>
#include "periodic_texture_guard.h"

namespace qnn_backend {

bool is_runtime_loadable();
int architecture();
bool initialize(const std::string &context_path, int padding);
bool is_initialized();
// ROSSI: 上下文元数据推导出的输出倍率（tile 输出边长 / 输入边长）。
// 上游由 ncnn 对象侧记账；Rossi 没有 ncnn 对象，输出位图的分配尺寸从这里取。
int scale();
int process_rgba(const uint8_t *input, int width, int height, int input_stride,
                 uint8_t *output, int output_stride,
                 periodic_texture_guard::Analysis &texture_analysis,
                 std::atomic<int> *progress,
                 const std::atomic<bool> *should_abort);
void shutdown();

} // namespace qnn_backend

#endif // ROSSI_QNN_BACKEND_H
