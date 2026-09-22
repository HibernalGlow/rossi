//! 诊断快照 `stats_json`（Flutter 侧的调试面板读它）。

use super::*;

impl Presenter {
    /// 诊断快照（JSON）。
    ///
    /// 用 JSON 而不是固定结构体，是为了让 C++ 侧不必跟着改字段定义 ——
    /// 它原样透传给 Dart，Dart 侧按 key 取。代价是"字段名即接口"，改名前要 grep。
    pub fn stats_json(&self) -> String {
        let (width, height) = self.target_size();
        let timings = self.last;

        // 缓存统计要先取出来：`format!` 的参数位里写不了语句。
        let (hits, misses, cache_bytes, decoded, stale, evicted, in_flight) = self
            .cache
            .lock()
            .map(|c| {
                (
                    c.hits,
                    c.misses,
                    c.bytes() as u64,
                    c.prefetched,
                    c.stale,
                    c.evicted,
                    c.in_flight.map(|i| i as i64).unwrap_or(-1),
                )
            })
            .unwrap_or((0, 0, 0, 0, 0, 0, -1));
        let prefetch_on = self.prefetch_enabled();

        format!(
            concat!(
                "{{",
                "\"backend\":\"wgpu/dx12\",",
                "\"adapter\":\"{}\",",
                "\"adapterMatched\":{},",
                "\"adapterLuid\":\"{:#x}\",",
                "\"targetLuid\":\"{:#x}\",",
                "\"directShareOfWgpuTexture\":\"{}\",",
                "\"copyPath\":\"GPU->GPU CopyResource\",",
                "\"initMs\":{:.1},",
                "\"initDeviceMs\":{:.1},",
                "\"initPipelineMs\":{:.1},",
                "\"initRestMs\":{:.1},",
                "\"width\":{},",
                "\"height\":{},",
                "\"presents\":{},",
                "\"recreates\":{},",
                "\"retired\":{},",
                "\"releasedTotal\":{},",
                "\"generation\":{},",
                "\"handle\":{},",
                "\"pageCount\":{},",
                // `pageIndex` 与 `currentIndex` 同值并存：mac 侧历史上只发
                // `currentIndex`，Windows 只发 `pageIndex`，而 Dart 的
                // `_presenterUsesEnhanced` 只读 `currentIndex` —— 于是 Windows 上
                // 永远"无法核对"替换是否生效。补齐 `currentIndex` 修掉这个漂移。
                "\"pageIndex\":{},",
                "\"currentIndex\":{},",
                "\"usedEnhanced\":{},",
                "\"enhancedPages\":{},",
                "\"enhancedInjected\":{},",
                "\"decodedWidth\":{},",
                "\"decodedHeight\":{},",
                "\"sourceWidth\":{},",
                "\"sourceHeight\":{},",
                "\"decodeMs\":{:.1},",
                "\"uploadMs\":{:.1},",
                "\"submitMs\":{:.1},",
                "\"totalMs\":{:.1},",
                "\"cacheHit\":{},",
                "\"cacheHits\":{},",
                "\"cacheMisses\":{},",
                "\"cacheBytes\":{},",
                "\"prefetchEnabled\":{},",
                "\"prefetchDecoded\":{},",
                "\"prefetchStale\":{},",
                "\"prefetchEvicted\":{},",
                "\"prefetchInFlight\":{},",
                "\"error\":\"{}\"",
                "}}"
            ),
            escape(&self.adapter_name),
            self.adapter_matched,
            self.adapter_luid,
            self.target_luid,
            escape(&self.direct_share),
            self.init_ms,
            self.init_device_ms,
            self.init_pipeline_ms,
            self.init_rest_ms,
            width,
            height,
            self.presents,
            self.recreates,
            self.retired.len(),
            self.released_total,
            self.generation(),
            self.handle().0 as usize,
            self.page_count(),
            self.page_index.map(|i| i as i64).unwrap_or(-1),
            self.page_index.map(|i| i as i64).unwrap_or(-1),
            enhance::used_enhanced_flag(self.last_used_enhanced),
            self.enhanced.len(),
            self.enhanced.injected(),
            self.decoded_width,
            self.decoded_height,
            self.decoded_source_width,
            self.decoded_source_height,
            timings.decode_ms,
            timings.upload_ms,
            timings.submit_ms,
            timings.total_ms,
            self.last_cache_hit,
            hits,
            misses,
            cache_bytes,
            prefetch_on,
            decoded,
            stale,
            evicted,
            in_flight,
            escape(&self.last_error),
        )
    }
}
