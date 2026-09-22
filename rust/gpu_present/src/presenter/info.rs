//! 只读的状态查询（句柄、代际、尺寸、诊断字符串）。

use super::*;

impl Presenter {
    /// 当前共享句柄（尺寸变化后句柄会变，要在 `ensure_target` 之后再取）。
    pub fn handle(&self) -> HANDLE {
        self.target
            .as_ref()
            .map(|t| t.handle)
            .unwrap_or(HANDLE(std::ptr::null_mut()))
    }

    /// 当前正在用的那一代的编号 —— C++ 侧要把它交给 `release_callback`
    /// 作为 `release_context`，回调里再原样传回来。
    pub fn generation(&self) -> u64 {
        self.target.as_ref().map(|t| t.generation).unwrap_or(0)
    }

    pub fn target_size(&self) -> (u32, u32) {
        self.target
            .as_ref()
            .map(|t| (t.width, t.height))
            .unwrap_or((0, 0))
    }

    /// 呈现时实际用的**解码宽度提示**。
    ///
    /// 探针要用同一个值重新解码一遍作为基准 —— 否则两边落在不同的降采样档位，
    /// 比出来的差异会来自降采样而不是来自 GPU 路径，那就白比了。
    pub fn decode_hint(&self) -> u32 {
        self.target
            .as_ref()
            .map(|t| t.width.min(MAX_EDGE))
            .unwrap_or(0)
    }

    /// 这一页在目标里被画在哪个矩形 `(x, y, w, h)`（同样的 letterbox 算式）。
    pub fn expected_draw_rect(&self) -> Option<(f32, f32, f32, f32)> {
        let target = self.target.as_ref()?;
        let page = self.page.as_ref()?;
        let scale = f64::min(
            target.width as f64 / page.width as f64,
            target.height as f64 / page.height as f64,
        );
        let draw_w = (page.width as f64 * scale).round().max(1.0) as f32;
        let draw_h = (page.height as f64 * scale).round().max(1.0) as f32;
        let x = ((target.width as f32 - draw_w) * 0.5).max(0.0);
        let y = ((target.height as f32 - draw_h) * 0.5).max(0.0);
        Some((x, y, draw_w, draw_h))
    }

    pub fn adapter_name(&self) -> &str {
        &self.adapter_name
    }

    /// 「直接对 wgpu 纹理调 `CreateSharedHandle`」的实测结论。
    ///
    /// 它不是断言也不是常量，是**启动时真跑了一次**的结果（见 [`probe_direct_share`]）。
    /// 探针把它打印出来：如果哪天驱动放开了这条路，这个字符串会变成"成功(意外)"，
    /// 那就是"可以去掉那次拷贝"的信号。
    pub fn direct_share_verdict(&self) -> &str {
        &self.direct_share
    }

    /// 最近一次呈现时实际解出的尺寸（降采样之后）。
    pub fn decoded_size(&self) -> (u32, u32) {
        (self.decoded_width, self.decoded_height)
    }

    /// 最近一次呈现时解码器报告的**原始**尺寸（降采样之前）。
    pub fn source_size(&self) -> (u32, u32) {
        (self.decoded_source_width, self.decoded_source_height)
    }

    pub fn decoded_width(&self) -> u32 {
        self.decoded_width
    }

    pub fn decoded_height(&self) -> u32 {
        self.decoded_height
    }

    pub fn source_width(&self) -> u32 {
        self.decoded_source_width
    }

    pub fn source_height(&self) -> u32 {
        self.decoded_source_height
    }

    pub fn set_error(&mut self, message: String) {
        self.last_error = message;
    }

    pub fn last_error(&self) -> &str {
        &self.last_error
    }

    pub fn last_timings(&self) -> PresentTimings {
        self.last
    }
}
