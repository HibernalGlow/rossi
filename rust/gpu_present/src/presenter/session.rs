//! 文档与预览模式对外接口：打开来源、页码、增强像素、原图预览、预取开关。

use super::*;

impl Presenter {
    /// 打开一个本地来源（散图文件夹 / CBZ / CBR）。
    pub fn open(&mut self, path: &str) -> Result<usize> {
        let source = LocalSource::open(path)?;
        let count = source.len();
        if count == 0 {
            return Err(anyhow!("这个来源里没有可显示的页: {path}"));
        }
        self.source = Some(Arc::new(source));
        self.page_index = None;

        // 换来源 = 缓存整体作废，并让预取线程改用新来源。
        {
            let mut shared = self.hub.shared.lock().expect("prefetch shared 中毒");
            shared.view.epoch += 1;
            shared.view.source = self.source.clone();
            shared.view.anchor = None;
            shared.view.page_count = count;
            // 刚打开还没显示任何页 —— 从这里起算"没有翻页过"是**对**的语义：
            // 准入判决的 `NoScrollYet` 分支本来就是给"启动/切来源之后"准备的。
            shared.view.last_show_at = None;
            shared.view.visible_pending = 1;
        }
        let epoch = self.current_epoch();
        if let Ok(mut cache) = self.cache.lock() {
            cache.drop_range(epoch);
        }
        // 增强轨跟着来源一起作废：留着的话，打开第二本书的第 3 页会沿用第一本书
        // 第 3 页的超分图 —— 页号相同而内容毫无关系。
        self.enhanced.retain_epoch(epoch);
        self.raw_source_sizes.clear();
        self.last_used_enhanced = false;
        self.hub.cv.notify_all();
        Ok(count)
    }

    pub fn page_count(&self) -> usize {
        self.source.as_ref().map(|s| s.len()).unwrap_or(0)
    }

    pub fn page_index(&self) -> Option<usize> {
        self.page_index
    }

    /// 注入一页的超分产物。
    ///
    /// Windows 每帧都在 GPU 上重采样，所以这里只存像素 —— 不像 mac 侧还要顺手
    /// 预渲染一张视口帧。新注入的图要等下一次 `show(index)` 才会上屏，
    /// Dart 侧注入完就会触发一次重绘。
    pub fn set_enhanced_pixels(&mut self, index: usize, pixels: Arc<PagePixels>) -> Result<()> {
        let epoch = self.current_epoch();
        self.enhanced.put(index, epoch, pixels.clone());
        eprintln!(
            "[Rossi GPU] set_enhanced_pixels: index={}, epoch={}, {}x{}, enhancedPages={}, enhancedBytes={}",
            index,
            epoch,
            pixels.width,
            pixels.height,
            self.enhanced.len(),
            self.enhanced.bytes()
        );
        Ok(())
    }

    /// 开关「原图对比」旁路：置位期间画面回到原图，增强图**保留**。
    pub fn set_original_preview(&mut self, active: bool) {
        self.original_preview.set(active);
    }

    pub fn is_original_preview(&self) -> bool {
        self.original_preview.active()
    }

    /// 预取开关。默认开 —— 它就是修翻页延迟的那件事。
    ///
    /// 留这个开关是为了 A/B：**在同一份二进制上只改这一处**，才排得掉代码漂移
    /// 对数字的影响。环境变量 `ROSSI_GPU_PREFETCH=0` 是同一个开关的启动期写法。
    pub fn set_prefetch_enabled(&mut self, enabled: bool) {
        self.hub.enabled.store(enabled, Ordering::Relaxed);
        if let Ok(mut shared) = self.hub.shared.lock() {
            if !enabled {
                // 关掉时连锚点一起撤。不撤的话恢复时会先去解一页早就翻过去的页。
                shared.view.anchor = None;
            }
        }
        self.hub.cv.notify_all();
    }

    pub fn prefetch_enabled(&self) -> bool {
        self.hub.enabled.load(Ordering::Relaxed)
    }
}
