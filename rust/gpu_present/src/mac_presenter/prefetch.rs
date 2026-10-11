use super::*;
use std::collections::HashSet;

const FORWARD: usize = 8;
const BACKWARD: usize = 4;

#[derive(Default, Clone)]
struct View {
    revision: u64,
    completed_revision: u64,
    anchor: Option<usize>,
    page_count: usize,
    epoch: u64,
    source: Option<Arc<LocalSource>>,
    width: u32,
    height: u32,
    enabled: bool,
    foreground: bool,
    stopped: bool,
}

pub(super) struct PrefetchHub {
    shared: Mutex<View>,
    cv: Condvar,
}

impl PrefetchHub {
    pub(super) fn new(width: u32, height: u32) -> Self {
        Self {
            shared: Mutex::new(View {
                width,
                height,
                enabled: true,
                ..View::default()
            }),
            cv: Condvar::new(),
        }
    }

    fn change(&self, f: impl FnOnce(&mut View)) {
        let mut view = self.shared.lock().unwrap_or_else(|p| p.into_inner());
        f(&mut view);
        view.revision = view.revision.wrapping_add(1);
        self.cv.notify_all();
    }

    pub(super) fn wake(&self) {
        self.change(|_| {});
    }

    pub(super) fn set_anchor(
        &self,
        anchor: usize,
        page_count: usize,
        epoch: u64,
        width: u32,
        height: u32,
        source: Option<Arc<LocalSource>>,
    ) {
        self.change(|v| {
            v.anchor = Some(anchor);
            v.page_count = page_count;
            v.epoch = epoch;
            v.width = width;
            v.height = height;
            v.source = source;
        });
    }

    pub(super) fn update_dimensions(&self, width: u32, height: u32) {
        let mut view = self.shared.lock().unwrap_or_else(|p| p.into_inner());
        if view.width != width || view.height != height {
            view.width = width;
            view.height = height;
            view.revision = view.revision.wrapping_add(1);
            self.cv.notify_all();
        }
    }

    pub(super) fn clear_source(&self, epoch: u64) {
        self.change(|v| {
            v.anchor = None;
            v.page_count = 0;
            v.source = None;
            v.epoch = epoch;
        });
    }

    pub(super) fn set_enabled(&self, enabled: bool) {
        self.change(|v| v.enabled = enabled);
    }
    pub(super) fn shutdown(&self) {
        self.change(|v| v.stopped = true);
    }

    /// 不持有 presenter 的借用，RAII 保证 show 出错也会恢复后台工作。
    pub(super) fn foreground(self: &Arc<Self>) -> Foreground {
        self.change(|v| v.foreground = true);
        Foreground(self.clone())
    }

    fn wait_for_work(&self, seen: u64) -> Option<View> {
        let mut view = self.shared.lock().unwrap_or_else(|p| p.into_inner());
        while !view.stopped
            && (view.revision == seen || !view.enabled || view.foreground || view.source.is_none())
        {
            view = self.cv.wait(view).unwrap_or_else(|p| p.into_inner());
        }
        (!view.stopped).then(|| view.clone())
    }

    fn complete(&self, revision: u64) {
        let mut v = self.shared.lock().unwrap_or_else(|p| p.into_inner());
        v.completed_revision = revision;
        self.cv.notify_all();
    }

    fn ready(&self, revision: u64) -> bool {
        let v = self.shared.lock().unwrap_or_else(|p| p.into_inner());
        v.revision == revision && v.enabled && !v.foreground && !v.stopped
    }

    /// 与 clear_source 串行核对来源再写缓存，防止换书后旧解码污染新缓存。
    fn publish(&self, view: &View, f: impl FnOnce(bool)) -> bool {
        let current = self.shared.lock().unwrap_or_else(|p| p.into_inner());
        if current.stopped || current.epoch != view.epoch || current.source.is_none() {
            return false;
        }
        f(current.revision == view.revision);
        true
    }
}

pub(super) struct Foreground(Arc<PrefetchHub>);
impl Drop for Foreground {
    fn drop(&mut self) {
        self.0.change(|v| v.foreground = false);
    }
}

pub(super) fn spawn_prefetch_worker(
    cache: Arc<SharedCache>,
    hub: Arc<PrefetchHub>,
    resampler: Arc<Mutex<WgpuResampler>>,
) -> JoinHandle<()> {
    thread::Builder::new()
        .name("rossi-mac-prefetch".into())
        .spawn(move || run(&cache, &hub, &resampler))
        .expect("无法启动 macOS 预取线程")
}

fn render(
    view: &View,
    hub: &PrefetchHub,
    resampler: &Mutex<WgpuResampler>,
    pixels: &PagePixels,
) -> Option<PreRenderedFrame> {
    let mut r = resampler.lock().unwrap_or_else(|p| p.into_inner());
    // 已经解完原图也不能抢在当前页前面渲染；拿到 GPU 锁后再检查一次。
    if !hub.ready(view.revision) {
        return None;
    }
    let stride = view.width as usize * 4;
    let mut bgra = vec![0; stride * view.height as usize];
    r.resample_to_buffer(
        &pixels.rgba,
        pixels.width,
        pixels.height,
        view.width,
        view.height,
        bgra.as_mut_ptr(),
        stride,
        false,
    )
    .ok()?;
    Some(PreRenderedFrame {
        target_w: view.width,
        target_h: view.height,
        bgra: Arc::new(bgra),
        stride,
    })
}

fn run(shared: &SharedCache, hub: &PrefetchHub, resampler: &Mutex<WgpuResampler>) {
    let mut seen = 0;
    while let Some(view) = hub.wait_for_work(seen) {
        seen = view.revision;
        let (Some(anchor), Some(source)) = (view.anchor, view.source.as_ref()) else {
            continue;
        };
        let mut candidates = vec![anchor];
        candidates.extend(interleaved_prefetch_positions(
            anchor,
            view.page_count,
            FORWARD,
            BACKWARD,
        ));
        // 同一轮每页只尝试一次。预算淘汰或解码失败不会引发无限解码/淘汰循环。
        let mut decoded = HashSet::new();
        let mut rendered = HashSet::new();
        while hub.ready(view.revision) {
            let target = {
                let mut c = shared.cache.lock().unwrap_or_else(|p| p.into_inner());
                let target = candidates.iter().copied().find(|i| {
                    !decoded.contains(i)
                        && !c.has(*i, view.epoch)
                        && !c.in_flight.contains(&(*i, view.epoch))
                });
                if let Some(i) = target {
                    c.in_flight.insert((i, view.epoch));
                }
                target
            };
            if let Some(index) = target {
                decoded.insert(index);
                let result = source.page_pixels(index).map(Arc::new);
                // 先发布解码结果并唤醒等待当前页的 show；前台可接管渲染，无需等邻页预渲染。
                hub.publish(&view, |_| {
                    let mut c = shared.cache.lock().unwrap_or_else(|p| p.into_inner());
                    if let Ok(ref pixels) = result {
                        c.insert(CachedPage::new_raw(index, view.epoch, Some(pixels.clone())));
                    }
                    c.in_flight.remove(&(index, view.epoch));
                });
                shared.cv.notify_all();
                // 一页一页完成视口，避免只解原图把近邻顶出预算，再去渲染远邻。
                if let Ok(pixels) = result {
                    let retained = shared
                        .cache
                        .lock()
                        .unwrap_or_else(|p| p.into_inner())
                        .has(index, view.epoch);
                    if retained {
                        rendered.insert(index);
                        if let Some(frame) = render(&view, hub, resampler, &pixels) {
                            publish_frame(shared, hub, &view, index, &pixels, false, frame);
                        }
                    }
                }
                continue;
            }
            let target = {
                let c = shared.cache.lock().unwrap_or_else(|p| p.into_inner());
                candidates.iter().copied().find_map(|i| {
                    if rendered.contains(&i) {
                        return None;
                    }
                    let (pixels, enhanced) =
                        c.get_unrendered_pixels(i, view.epoch, view.width, view.height)?;
                    Some((i, pixels, enhanced))
                })
            };
            let Some((index, pixels, enhanced)) = target else {
                break;
            };
            rendered.insert(index);
            if let Some(frame) = render(&view, hub, resampler, &pixels) {
                publish_frame(shared, hub, &view, index, &pixels, enhanced, frame);
            }
        }
        hub.complete(view.revision);
    }
}

fn publish_frame(
    shared: &SharedCache,
    hub: &PrefetchHub,
    view: &View,
    index: usize,
    pixels: &Arc<PagePixels>,
    enhanced: bool,
    frame: PreRenderedFrame,
) {
    hub.publish(view, |same_view| {
        if !same_view {
            return;
        }
        let mut c = shared.cache.lock().unwrap_or_else(|p| p.into_inner());
        // 超分图可能在后台渲染途中被替换，不能用旧结果覆盖新轨。
        let still_current = c
            .entries
            .iter()
            .find(|e| e.index == index && e.epoch == view.epoch)
            .and_then(|e| {
                if enhanced {
                    e.enhanced_pixels.as_ref()
                } else {
                    e.raw_pixels.as_ref()
                }
            })
            .is_some_and(|p| Arc::ptr_eq(p, pixels));
        if !still_current {
            return;
        }
        if enhanced {
            c.add_pre_rendered_enhanced(index, view.epoch, frame);
        } else {
            c.add_pre_rendered(index, view.epoch, frame);
        }
    });
}

#[cfg(test)]
mod tests;
