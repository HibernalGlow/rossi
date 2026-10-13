//! mImageViewer AI 尺寸策略的直接源码复用；不包含推理/会话管理。
//! Copyright (c) 2026 SANO Taku (Mikage Sawatari), MIT.
include!(concat!(env!("OUT_DIR"), "/ai_size_limit.rs"));

// Rossi 默认预算；保留现有配置入口。
impl Default for AiProcessSizeLimit {
    fn default() -> Self {
        Self::square(4096)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn asymmetric_limits_are_orientation_independent_and_exclusive() {
        for limit in [
            AiProcessSizeLimit {
                long_edge_px: 4096,
                short_edge_px: 2048,
            },
            AiProcessSizeLimit {
                long_edge_px: 2048,
                short_edge_px: 4096,
            },
        ] {
            for (w, h) in [(4095, 2047), (2047, 4095), (2720, 1920)] {
                assert!(should_process_rect(w, h, limit));
            }
            for (w, h) in [(4096, 2047), (2047, 4096), (4095, 2048), (3000, 3000)] {
                assert!(!should_process_rect(w, h, limit));
            }
        }
    }
}
