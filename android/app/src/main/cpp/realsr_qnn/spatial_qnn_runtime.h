// Ported from HaoweiLi97/mihon_img_upscale (Apache License 2.0).
// Upstream files: app/src/main/cpp/{qnn_backend,spatial_qnn_runtime}.{h,cpp},
// periodic_texture_guard.h, monochrome_guard.h, qnn_context_bridge.cpp.
// Local deviations are marked with `ROSSI:` comments and registered in
// docs/upstream-sync.md.

#ifndef ROSSI_SPATIAL_QNN_RUNTIME_H
#define ROSSI_SPATIAL_QNN_RUNTIME_H

#include <cstdint>
#include <string>
#include <vector>

namespace spatial_qnn {

struct TensorData {
  std::string name;
  std::vector<uint32_t> dimensions;
  std::vector<float> values;
};

class Runtime {
public:
  Runtime();
  ~Runtime();
  Runtime(const Runtime &) = delete;
  Runtime &operator=(const Runtime &) = delete;

  bool initialize();
  bool compile_dlc(const std::string &dlc_path,
                   const std::string &binary_path);
  bool load(const std::string &binary_path);
  bool execute(const std::vector<TensorData> &inputs,
               std::vector<TensorData> &outputs);
  bool execute_to_files(const std::vector<TensorData> &inputs,
                        const std::string &output_directory);
  void unload_graph();
  void reset();

  const std::vector<TensorData> &input_metadata() const;
  const std::vector<TensorData> &output_metadata() const;
  const std::string &error() const;

  static std::string safe_tensor_filename(const std::string &name);

private:
  class Impl;
  Impl *impl_;
};

} // namespace spatial_qnn

#endif
