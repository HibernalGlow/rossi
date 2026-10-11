use super::*;

/// 缓存页面结构（对齐 mImageViewer 双轨缓存设计）。
///
/// 拥有原图（raw_pixels）与 AI 超分图（enhanced_pixels）双轨，
/// 以及各自对应的视口尺寸预渲染帧。
pub(super) struct CachedPage {
    pub(super) index: usize,
    pub(super) epoch: u64,
    // 原图像素可被淘汰，但布局仍需要这页的宽高，不能沿用上一页的统计值。
    pub(super) source_size: Option<(u32, u32)>,
    pub(super) raw_pixels: Option<Arc<PagePixels>>,
    pub(super) enhanced_pixels: Option<Arc<PagePixels>>,
    pub(super) pre_rendered_raw: Vec<PreRenderedFrame>,
    pub(super) pre_rendered_enhanced: Vec<PreRenderedFrame>,

    /// 阅读背景「自适应取色」的调色板，**随原图像素一起算好存在这里**。
    ///
    /// # 为什么要存在页缓存里，而不是每次呈现时现算
    ///
    /// 现算一次也几乎不花钱（见 `ambient` 模块：采样量与图片尺寸无关，几十个字节），
    /// 但「每次翻页算一次」和「每页算一次」是两种量级 —— 前者在**翻页关键路径**上，
    /// 后者在预取线程上。这里选后者：插页缓存的就是预取线程。
    ///
    /// # 为什么不跟随超分轨重算
    ///
    /// 超分只改锐度与尺寸，不改颜色分布。拿超分图重采一遍是纯粹的浪费 ——
    /// 而且它落在 Dart 注入超分图那条路上，那条路已经在做几十 MB 的搬运了。
    pub(super) palette: Option<AmbientPalette>,
}

impl CachedPage {
    pub(super) fn new_raw(index: usize, epoch: u64, pixels: Option<Arc<PagePixels>>) -> Self {
        Self {
            index,
            epoch,
            source_size: pixels.as_ref().map(|p| (p.source_width, p.source_height)),
            // 采样点就在这里：像素已经在手上，取色是**顺手**做的，不是另开一趟活。
            palette: pixels.as_deref().map(sample_edge_palette),
            raw_pixels: pixels,
            enhanced_pixels: None,
            pre_rendered_raw: Vec::new(),
            pre_rendered_enhanced: Vec::new(),
        }
    }

    /// 兼容性访问原图像素
    #[allow(dead_code)]
    pub(super) fn pixels(&self) -> Option<Arc<PagePixels>> {
        self.raw_pixels.clone()
    }

    pub(super) fn find_frame_in(
        frames: &[PreRenderedFrame],
        target_w: u32,
        target_h: u32,
    ) -> Option<PreRenderedFrame> {
        if let Some(f) = frames
            .iter()
            .find(|f| f.target_w == target_w && f.target_h == target_h)
        {
            return Some(f.clone());
        }
        frames
            .iter()
            .find(|f| {
                (f.target_w as i64 - target_w as i64).abs() <= 3
                    && (f.target_h as i64 - target_h as i64).abs() <= 3
            })
            .cloned()
    }

    /// 级联解析视口预渲染帧（对齐 mImageViewer resolve_fs_display_tex 原版逻辑）：
    /// 1. 若 !bypass_enhanced 且存在 pre_rendered_enhanced，最优先命中！
    /// 2. 否则命中 pre_rendered_raw！
    pub(super) fn resolve_display_frame(
        &self,
        target_w: u32,
        target_h: u32,
        bypass_enhanced: bool,
    ) -> Option<PreRenderedFrame> {
        if !bypass_enhanced {
            if let Some(f) = Self::find_frame_in(&self.pre_rendered_enhanced, target_w, target_h) {
                return Some(f);
            }
            if self.enhanced_pixels.is_some() {
                // 严禁在超分大图就绪时透出旧的原图预渲染视口帧！返回 None 触发现场从 enhanced_pixels 重新抗锯齿降采样
                return None;
            }
        }
        Self::find_frame_in(&self.pre_rendered_raw, target_w, target_h)
    }

    /// 这一页在当前模式下**会不会**用超分轨呈现。
    ///
    /// 单独抽出来（而不是内联进 [resolve_display_pixels]）是因为它还要当**证据**用：
    /// 「本次呈现用的是哪一轨」要能被外部核对，而证据只有和判定共用同一条规则才可信
    /// —— 各自写一遍，将来规则一改（比如加"只在放大倍率够时才用超分图"）就会出现
    /// 「画面是原图、证据说超分」的假证据，那正是这个 bug 的原形。
    pub(super) fn prefers_enhanced(&self, bypass_enhanced: bool) -> bool {
        // 规则本身在 `enhance` 里，与 Windows 侧、与 `stats` 报出的证据同源。
        enhance::prefers_enhanced(self.enhanced_pixels.is_some(), bypass_enhanced)
    }

    /// 级联解析像素（对齐 mImageViewer 原版逻辑）：
    /// 1. 若 !bypass_enhanced 且存在 enhanced_pixels，最优先命中！
    /// 2. 否则命中 raw_pixels！
    pub(super) fn resolve_display_pixels(&self, bypass_enhanced: bool) -> Option<Arc<PagePixels>> {
        if self.prefers_enhanced(bypass_enhanced) {
            if let Some(ref enhanced) = self.enhanced_pixels {
                return Some(enhanced.clone());
            }
        }
        self.raw_pixels.clone()
    }

    #[allow(dead_code)]
    pub(super) fn add_frame(&mut self, frame: PreRenderedFrame) {
        self.add_raw_frame(frame);
    }

    pub(super) fn add_raw_frame(&mut self, frame: PreRenderedFrame) {
        self.pre_rendered_raw
            .retain(|f| !(f.target_w == frame.target_w && f.target_h == frame.target_h));
        self.pre_rendered_raw.push(frame);
        if self.pre_rendered_raw.len() > 3 {
            self.pre_rendered_raw.remove(0);
        }
    }

    pub(super) fn add_enhanced_frame(&mut self, frame: PreRenderedFrame) {
        self.pre_rendered_enhanced
            .retain(|f| !(f.target_w == frame.target_w && f.target_h == frame.target_h));
        self.pre_rendered_enhanced.push(frame);
        if self.pre_rendered_enhanced.len() > 3 {
            self.pre_rendered_enhanced.remove(0);
        }
    }
}

/// 只统计 PageCache 持有的像素；GPU 纹理和显示缓冲不包含在内。
struct CacheLimits {
    pages: usize,
    raw_pages: usize,
    bytes: usize,
}

impl Default for CacheLimits {
    fn default() -> Self {
        Self {
            pages: 16,
            raw_pages: 3,
            bytes: 1024 * 1024 * 1024,
        }
    }
}

#[derive(Default)]
pub(super) struct PageCache {
    pub(super) entries: VecDeque<CachedPage>,
    pub(super) hits: u64,
    pub(super) misses: u64,
    pub(super) prefetched: u64,
    pub(super) stale: u64,
    pub(super) evicted: u64,
    pub(super) in_flight: Option<usize>,
    pinned: Option<(usize, u64)>,
    limits: CacheLimits,
}

impl PageCache {
    pub(super) fn bytes(&self) -> usize {
        self.entries
            .iter()
            .map(|e| {
                let p_len = e.raw_pixels.as_ref().map(|p| p.rgba.len()).unwrap_or(0);
                let ep_len = e
                    .enhanced_pixels
                    .as_ref()
                    .map(|p| p.rgba.len())
                    .unwrap_or(0);
                let r_len: usize = e.pre_rendered_raw.iter().map(|f| f.bgra.len()).sum();
                let er_len: usize = e.pre_rendered_enhanced.iter().map(|f| f.bgra.len()).sum();
                p_len + ep_len + r_len + er_len
            })
            .sum()
    }

    /// 获取缓存页面（按级联规则解析像素与预渲染帧，不掏空缓存，移至 LRU 队列尾部）
    pub(super) fn get(
        &mut self,
        index: usize,
        epoch: u64,
        target_w: u32,
        target_h: u32,
        bypass_enhanced: bool,
    ) -> Option<(Option<Arc<PagePixels>>, Option<PreRenderedFrame>)> {
        let at = self
            .entries
            .iter()
            .position(|e| e.index == index && e.epoch == epoch)?;
        let entry = self.entries.remove(at)?;
        self.hits += 1;
        let frame = entry.resolve_display_frame(target_w, target_h, bypass_enhanced);
        let pixels = entry.resolve_display_pixels(bypass_enhanced);
        self.entries.push_back(entry);
        Some((pixels, frame))
    }

    /// 获取原图轨缓存，不参与超分轨选择。
    ///
    /// 邻页预取只负责准备原图。若这里复用普通的 [get]，超分图存在时会把
    /// enhanced_pixels 当成预取输入，随后又写回 raw 预渲染桶，导致两条轨相互污染，
    /// 并让预取线程反复重采样当前页。
    pub(super) fn get_raw(
        &mut self,
        index: usize,
        epoch: u64,
        target_w: u32,
        target_h: u32,
    ) -> Option<(Option<Arc<PagePixels>>, Option<PreRenderedFrame>)> {
        let at = self
            .entries
            .iter()
            .position(|e| e.index == index && e.epoch == epoch)?;
        let entry = self.entries.remove(at)?;
        self.hits += 1;
        let frame = CachedPage::find_frame_in(&entry.pre_rendered_raw, target_w, target_h);
        let pixels = entry.raw_pixels.clone();
        self.entries.push_back(entry);
        Some((pixels, frame))
    }

    pub(super) fn has(&self, index: usize, epoch: u64) -> bool {
        self.entries
            .iter()
            .any(|e| e.index == index && e.epoch == epoch)
    }

    /// 读某一页已采好的调色板。
    ///
    /// **只读**：不动 LRU 顺序，也不碰任何计数 —— 与 `get` / `get_raw` 是两回事。
    /// 它是**诊断/呈现的旁路**，不该因为被读了一次就把某一页挪到队尾，
    /// 那会让真正的预取淘汰顺序被读取行为带偏。
    pub(super) fn palette_for(&self, index: usize, epoch: u64) -> Option<AmbientPalette> {
        self.entries
            .iter()
            .find(|e| e.index == index && e.epoch == epoch)
            .and_then(|e| e.palette.clone())
    }

    /// 插入页面（按 `(index, epoch)` 去重：重复时替换旧条目并移到 LRU 尾部）。
    ///
    /// # 它写的是「原图轨」，但**不能顺手把「超分轨」抹掉**
    ///
    /// 三处调用写的都是原图：后台预取线程解完原图、`show_into_buffer` 的缓存未命中
    /// 与 in-flight 回填。而超分图是**另一条线程**异步填进**同一个 `(index, epoch)`
    /// 条目**的（Dart 侧超分跑完 → `set_enhanced_pixels`）。两边并发时会出现这个时序：
    ///
    /// 1. 预取线程选中第 7 页，`in_flight = Some(7)`，开始解原图（几百毫秒）；
    /// 2. 超分注入完成，页 7 条目带上 `enhanced_pixels` + `pre_rendered_enhanced`；
    /// 3. 预取线程解完，`insert(CachedPage::new_raw(7, …))`。
    ///
    /// 早先的实现是无条件 `retain` 掉旧条目再 push 新条目，第 3 步就把第 2 步刚注入的
    /// 超分轨**整条抹掉**：下一次 `show` 静默渲染回原图。后果还不止画面 ——
    /// Dart 侧已经按「注入成功」记了账（`_enhancedIndices`），这一页整场都不会再重试，
    /// 于是表现成「日志说超分成功、画面一直是原图」（虚报替换成功）。
    ///
    /// 所以替换时要把旧条目的超分轨**搬**到新条目上：`take` 而非 clone（超分大图
    /// 是几十 MB 的 `Arc`，视口帧也是几十 MB 的 BGRA，没必要复制）；新条目自带超分轨
    /// 时以新的为准。
    pub(super) fn insert(&mut self, mut page: CachedPage) {
        if let Some(at) = self
            .entries
            .iter()
            .position(|e| e.index == page.index && e.epoch == page.epoch)
        {
            if let Some(mut prev) = self.entries.remove(at) {
                page.source_size = page.source_size.or(prev.source_size);
                if page.enhanced_pixels.is_none() {
                    page.enhanced_pixels = prev.enhanced_pixels.take();
                }
                if page.pre_rendered_enhanced.is_empty() {
                    page.pre_rendered_enhanced = std::mem::take(&mut prev.pre_rendered_enhanced);
                }
                // 调色板只由原图像素决定，而重插的条目常常是「只带预渲染帧、没带像素」
                // （`add_pre_rendered_enhanced` / `set_enhanced_pixels` 那条路）。
                // 不搬的话，已经被采过的那一页会在重插之后变成"没有背景色"——
                // 界面上表现为背景在翻页时闪回默认底色。
                if page.palette.is_none() {
                    page.palette = prev.palette.take();
                }
            }
        }
        self.entries.push_back(page);
        self.prefetched += 1;

        self.enforce_limits();
    }

    pub(super) fn pin(&mut self, index: usize, epoch: u64) {
        self.pinned = Some((index, epoch));
        self.enforce_limits();
    }

    pub(super) fn clear(&mut self) {
        self.entries.clear();
        self.in_flight = None;
        self.pinned = None;
    }

    pub(super) fn budget_bytes(&self) -> usize {
        self.limits.bytes
    }

    pub(super) fn over_budget_bytes(&self) -> usize {
        self.bytes().saturating_sub(self.limits.bytes)
    }

    fn enforce_limits(&mut self) {
        let mut raw_count = self
            .entries
            .iter()
            .filter(|e| e.raw_pixels.is_some())
            .count();
        for entry in &mut self.entries {
            if raw_count <= self.limits.raw_pages {
                break;
            }
            if Some((entry.index, entry.epoch)) != self.pinned
                && entry.raw_pixels.is_some()
                && !entry.pre_rendered_raw.is_empty()
            {
                entry.raw_pixels = None;
                raw_count -= 1;
            }
        }
        // 当前页不能因后台增量被逐出。若当前页自身超过预算，只保留它并上报超额；
        // 清空超分轨会让 Dart 已确认的替换静默回退，因此不靠删除当前页硬凑上限。
        while self.entries.len() > self.limits.pages || self.bytes() > self.limits.bytes {
            let Some(at) = self
                .entries
                .iter()
                .position(|e| Some((e.index, e.epoch)) != self.pinned)
            else {
                break;
            };
            self.entries.remove(at);
            self.evicted += 1;
        }
    }

    /// 解码像素与本次视口帧一起入账，避免中间态淘汰导致后续回填找不到条目。
    pub(super) fn store_raw_render(
        &mut self,
        index: usize,
        epoch: u64,
        pixels: Arc<PagePixels>,
        frame: PreRenderedFrame,
    ) {
        if let Some(entry) = self
            .entries
            .iter_mut()
            .find(|e| e.index == index && e.epoch == epoch)
        {
            if entry.palette.is_none() {
                entry.palette = Some(sample_edge_palette(&pixels));
            }
            entry.source_size = Some((pixels.source_width, pixels.source_height));
            entry.raw_pixels = Some(pixels);
            entry.add_raw_frame(frame);
            self.enforce_limits();
        } else {
            let mut page = CachedPage::new_raw(index, epoch, Some(pixels));
            page.add_raw_frame(frame);
            self.insert(page);
        }
    }

    pub(super) fn store_enhanced_render(
        &mut self,
        index: usize,
        epoch: u64,
        pixels: Arc<PagePixels>,
        frame: Option<PreRenderedFrame>,
    ) -> bool {
        if let Some(entry) = self
            .entries
            .iter_mut()
            .find(|e| e.index == index && e.epoch == epoch)
        {
            entry.enhanced_pixels = Some(pixels);
            if let Some(frame) = frame {
                entry.add_enhanced_frame(frame);
            }
            if let Some(at) = self
                .entries
                .iter()
                .position(|e| e.index == index && e.epoch == epoch)
            {
                let entry = self.entries.remove(at).unwrap();
                self.entries.push_back(entry);
            }
            self.enforce_limits();
        } else {
            let mut page = CachedPage::new_raw(index, epoch, None);
            page.enhanced_pixels = Some(pixels);
            if let Some(frame) = frame {
                page.add_enhanced_frame(frame);
            }
            self.insert(page);
        }
        self.has(index, epoch)
    }

    /// 查找已缓存像素但尚未对当前视口尺寸（含容差）预渲染的页面，
    /// 并**说明这些像素来自哪一轨**。
    ///
    /// 返回的 `bool` 不能省：超分轨的像素必须回填进 `pre_rendered_enhanced`。
    /// 存错桶有两个后果，都属于"画面不是它该有的样子"：
    /// - **原图对比会显示超分图**：旁路态下 `resolve_display_frame` 会去翻
    ///   `pre_rendered_raw`，那里躺着一张由超分像素缩出来的帧；
    /// - **每 15 ms 重采样一次当前页**：`resolve_display_frame` 对超分轨有
    ///   「宁可现场重画、也不透出旧帧」的判据（`enhanced_pixels.is_some()` 时返回
    ///   `None`），所以存错桶之后预取线程每次轮询都认为"这一页还没预渲染"，
    ///   于是不停地重采样 —— 白白烧 CPU，还一直抢那个 resampler 锁。
    pub(super) fn get_unrendered_pixels(
        &self,
        index: usize,
        epoch: u64,
        target_w: u32,
        target_h: u32,
    ) -> Option<(Arc<PagePixels>, bool)> {
        let entry = self
            .entries
            .iter()
            .find(|e| e.index == index && e.epoch == epoch)?;
        if entry
            .resolve_display_frame(target_w, target_h, false)
            .is_some()
        {
            None
        } else {
            let enhanced = entry.prefers_enhanced(false);
            entry.resolve_display_pixels(false).map(|p| (p, enhanced))
        }
    }

    /// 追加或更新页面的原图预渲染视口帧
    pub(super) fn add_pre_rendered(&mut self, index: usize, epoch: u64, frame: PreRenderedFrame) {
        if let Some(entry) = self
            .entries
            .iter_mut()
            .find(|e| e.index == index && e.epoch == epoch)
        {
            entry.add_raw_frame(frame);
            self.enforce_limits();
        }
    }

    /// 追加或更新页面的超分增强预渲染视口帧
    pub(super) fn add_pre_rendered_enhanced(
        &mut self,
        index: usize,
        epoch: u64,
        frame: PreRenderedFrame,
    ) {
        if let Some(entry) = self
            .entries
            .iter_mut()
            .find(|e| e.index == index && e.epoch == epoch)
        {
            entry.add_enhanced_frame(frame);
            self.enforce_limits();
        } else {
            let mut page = CachedPage::new_raw(index, epoch, None);
            page.add_enhanced_frame(frame);
            self.insert(page);
        }
    }

    /// 回填原图像素
    pub(super) fn set_pixels(&mut self, index: usize, epoch: u64, pixels: Arc<PagePixels>) {
        if let Some(entry) = self
            .entries
            .iter_mut()
            .find(|e| e.index == index && e.epoch == epoch)
        {
            // 先补采再搬所有权：`raw_pixels` 那一行会把 `pixels` 移走。
            // 这里补的是「条目先被预渲染帧建出来、像素后到」的那条路
            // （`add_pre_rendered` → 预取线程回填），不补就等于这一页永远没有背景色。
            if entry.palette.is_none() {
                entry.palette = Some(sample_edge_palette(&pixels));
            }
            entry.source_size = Some((pixels.source_width, pixels.source_height));
            entry.raw_pixels = Some(pixels);
            self.enforce_limits();
        }
    }

    /// 回填超分增强像素
    pub(super) fn set_enhanced_pixels(
        &mut self,
        index: usize,
        epoch: u64,
        pixels: Arc<PagePixels>,
    ) {
        if let Some(entry) = self
            .entries
            .iter_mut()
            .find(|e| e.index == index && e.epoch == epoch)
        {
            entry.enhanced_pixels = Some(pixels);
            self.enforce_limits();
        } else {
            let mut page = CachedPage::new_raw(index, epoch, None);
            page.enhanced_pixels = Some(pixels);
            self.insert(page);
        }
    }

    /// 这一页当前会不会用超分轨呈现。没有这一页时 `false`。
    ///
    /// 呈现路径**不得**用它来反推"我刚渲染的那一帧是哪一轨"：缓存里的状态可以在
    /// 「解引用」与「回填」之间被超分注入改掉，回头问缓存会把"刚插入的超分轨"
    /// 当成"这一帧的来源"，而那帧其实是用原图像素渲染的。要判断已渲染帧的轨，
    /// 只看**像素从哪来**（见 `show_into_buffer` 的 `rendered_enhanced`）。
    pub(super) fn prefers_enhanced(&self, index: usize, epoch: u64, bypass_enhanced: bool) -> bool {
        self.entries
            .iter()
            .find(|e| e.index == index && e.epoch == epoch)
            .map(|e| e.prefers_enhanced(bypass_enhanced))
            .unwrap_or(false)
    }

    /// 淘汰超出保留集的超分大图（对齐 mImageViewer evict_final_pipeline_cache_for_keep_set 原版函数）
    pub(super) fn evict_final_pipeline_cache_for_keep_set(
        &mut self,
        keep_set: &[usize],
        epoch: u64,
    ) {
        for entry in self.entries.iter_mut() {
            if entry.epoch == epoch && !keep_set.contains(&entry.index) {
                entry.enhanced_pixels = None;
                entry.pre_rendered_enhanced.clear();
            }
        }
    }
}

#[cfg(test)]
mod tests;
