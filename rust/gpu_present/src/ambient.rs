//! 阅读背景「自适应取色」的采样器：从**已经解出来的**页面像素里顺手采四边色标。
//!
//! # 它为什么必须活在这里
//!
//! 参考实现是 neoview 的 `edgeMatchBackground.ts`：新建一个 `Image` 再解一遍码、
//! 画进 48 px 的画布、回读像素，然后拼成 CSS 渐变。而它自己的呈现层
//! （`ReaderBackgroundLayer.tsx`）把这条路**关掉了**，注释写得很直白：
//!
//! > `Edge matching is intentionally disabled: it used a hidden Image decode
//! > and canvas readback on page changes, competing with Reader rendering.`
//!
//! 也就是说它踩的坑**不是采样本身，而是又解了一遍图**。这里换一条路：页面像素
//! 在本进程里本来就已经解出来了（呈现器要拿它上屏），采样只是从这块**已经热的**
//! 缓冲里读几十个字节。于是三条性质同时成立：
//!
//! 1. **不额外解码** —— 复用 `LocalSource::page_pixels` 的产物；
//! 2. **不额外分配** —— 除了四条边那几个 `[u8; 3]`，没有大缓冲；
//! 3. **不进关键路径** —— 调用点在页缓存插入的那一刻，而那是**预取线程**在干。
//!
//! 采样量与图片尺寸**无关**：四边 × `STOPS` 个色标 × 一个小块，
//! 一张 10000 px 宽的和一张 100 px 宽的都是同一笔固定开销。
//!
//! # 色彩空间
//!
//! 平均值直接在 sRGB（已 gamma 编码）上算，与 neoview 同一口径。严格说
//! 应当在**线性空间**求平均再转回来，但那会得到更"平"的颜色；背景要的是与
//! 页面边沿观感一致，sRGB 下平均反而更贴近人眼预期。这是一个刻意的选择。

use rossi_local_core::PagePixels;

/// 每条边取几个色标。与 neoview 的 `EDGE_MATCH_DEFAULTS.stops` 同量级。
pub const STOPS: usize = 6;

/// 采样点离边缘的深度（像素）。`1` = 只取最外那一行 / 列。
pub const DEPTH: u32 = 1;

/// 每个色标在**沿边方向**上平均几个像素。
///
/// 取 3 而不是 1：扫描件的最外一列常有孤立脏点与 JPEG 振铃，单点采样会
/// 把一条背景色采成花斑。三个点求平均是能压掉这类噪声的最小代价。
const WINDOW: u32 = 3;

/// 色标摆放的内缩比例。
///
/// 避开扫描件最常见的贴边黑框 / 白框 —— 那圈框不是画面内容，
/// 拿它当背景色会让整个背景变成纯黑或纯白。
const INSET: f32 = 0.02;

/// 最外那一块**整块没有不透明像素**时，最多再往里试探几步（每步 1 像素）。
///
/// 留着这个上限是因为「往里找」必须能停下来：整页透明的图（或整页透明的那一条边）
/// 如果无限往里找，就会一路找到图像中心，把一个"这一页这条边没有内容"的情况
/// 答成"这一条边是那个颜色"。有上限之后两种情形分得开：
/// 有留白的页会找到留白里面的内容，真没内容的边就是黑。
///
/// 16 步 × 四条边 × `STOPS` 个色标 × 每块 3 像素 = 最多约 1.2 KB 的读取，
/// 相比图片尺寸依然可以忽略。
const MAX_SKIP: u32 = 16;

/// 四边色标 + 一个代表色。
///
/// [average] 是**四边色标的平均**而不是整页平均，与 neoview 的
/// `edgeFrameToPresentation` 一致：背景要接的是页面的边沿色，不是页面的平均亮度。
/// 拿整页平均，一张大面积白底黑线的漫画页会得到一个灰底，反而与页面边沿对不上。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AmbientPalette {
    /// 代表色（四边色标的平均）。
    pub average: [u8; 3],
    pub top: Vec<[u8; 3]>,
    pub right: Vec<[u8; 3]>,
    pub bottom: Vec<[u8; 3]>,
    pub left: Vec<[u8; 3]>,
}

impl Default for AmbientPalette {
    fn default() -> Self {
        Self {
            average: [0, 0, 0],
            top: Vec::new(),
            right: Vec::new(),
            bottom: Vec::new(),
            left: Vec::new(),
        }
    }
}

/// 从已解码的一页采出调色板。
pub fn sample_edge_palette(pixels: &PagePixels) -> AmbientPalette {
    sample_rgba(&pixels.rgba, pixels.width, pixels.height)
}

/// 采样核心（直接吃原始 RGBA，不依赖 [`PagePixels`] 的构造方式 —— 单测因此不用拼结构体）。
///
/// `rgba` 长度不足（`width * height * 4`）时按**能读到的部分**采，不 panic：
/// 这一层是「背景好不好看」，任何情况下都不该把阅读器带崩。
pub fn sample_rgba(rgba: &[u8], width: u32, height: u32) -> AmbientPalette {
    if width == 0 || height == 0 || rgba.is_empty() {
        return AmbientPalette::default();
    }
    let depth = DEPTH.min(width).min(height).max(1);
    let stops = STOPS;

    let xs = axis_positions(width, stops);
    let ys = axis_positions(height, stops);

    let top: Vec<[u8; 3]> = xs
        .iter()
        .map(|&x| first_opaque_block(rgba, width, height, |offset| (x, offset, WINDOW, depth)))
        .collect();
    let bottom: Vec<[u8; 3]> = xs
        .iter()
        .map(|&x| {
            first_opaque_block(rgba, width, height, |offset| {
                (x, (height - depth).saturating_sub(offset), WINDOW, depth)
            })
        })
        .collect();
    let left: Vec<[u8; 3]> = ys
        .iter()
        .map(|&y| first_opaque_block(rgba, width, height, |offset| (offset, y, depth, WINDOW)))
        .collect();
    let right: Vec<[u8; 3]> = ys
        .iter()
        .map(|&y| {
            first_opaque_block(rgba, width, height, |offset| {
                ((width - depth).saturating_sub(offset), y, depth, WINDOW)
            })
        })
        .collect();

    let average = mean_of_edges(&top, &right, &bottom, &left);

    AmbientPalette {
        average,
        top,
        right,
        bottom,
        left,
    }
}

/// 色标沿一条边摆放的位置（含内缩，两端夹在 `0..len-1`）。
fn axis_positions(len: u32, stops: usize) -> Vec<u32> {
    let stops = stops.clamp(1, STOPS);
    if len <= 1 {
        return vec![0];
    }
    let last = (len - 1) as f32;
    let inset = last * INSET;
    let span = (last - inset * 2.0).max(0.0);
    (0..stops)
        .map(|index| {
            let t = if stops <= 1 {
                0.0
            } else {
                index as f32 / (stops - 1) as f32
            };
            (inset + span * t).round().clamp(0.0, last) as u32
        })
        .collect()
}

/// 沿「深度」方向从最外一行 / 列往里试探，返回**第一个**含有不透明像素的小块的平均色。
///
/// # 为什么必须允许往里找
///
/// 「外圈整圈透明」在真实数据里是常态而不是特例：PNG 页留白、跨页扫描件、
/// 以及带透明边的转换产物都是这样。只采最外一行的话，这些页的背景会全部变成纯黑 ——
/// 而那个结果**不像"取色失败了"，像"这本漫画是黑的"**，事后根本无从判断。
///
/// 试探有上限（[MAX_SKIP]），所以两种情况分得开：往里找到内容的边取内容的颜色，
/// 一路探到底仍然全透明的边就是黑 —— 那时这一页在这条边上确实什么也没有。
///
/// `block_at(offset)` 给出距最外一行 / 列 `offset` 像素处那一块的中心与大小时；
/// 越界由 [`block_average`] 内部夹紧，调用方不必自己算边界。
fn first_opaque_block(
    rgba: &[u8],
    width: u32,
    height: u32,
    block_at: impl Fn(u32) -> (u32, u32, u32, u32),
) -> [u8; 3] {
    let limit = MAX_SKIP
        .min(height.saturating_sub(1))
        .min(width.saturating_sub(1));
    for offset in 0..=limit {
        let (center_x, center_y, block_w, block_h) = block_at(offset);
        let (color, count) =
            block_average(rgba, width, height, center_x, center_y, block_w, block_h);
        if count > 0 {
            return color;
        }
    }
    [0, 0, 0]
}

/// 以 `(center_x, center_y)` 为中心取一块 `block_w × block_h`，
/// 返回平均色与**参与平均的像素个数**。
///
/// 个数必须一起返回：它是调用方判断「这块到底有没有内容」的唯一依据。
/// 返回 `[0, 0, 0]` 时，那个黑可能是"采到的真是黑"，也可能是"一个不透明像素都没有" ——
/// 两者对调用方的动作完全相反（前者照用，后者要往里找），拼在一起就再也分不开。
///
/// 完全透明的像素**不参与**平均：若按 RGB 计入，会把边色算成那个位置在压缩里
/// 残留的垃圾值。
fn block_average(
    rgba: &[u8],
    width: u32,
    height: u32,
    center_x: u32,
    center_y: u32,
    block_w: u32,
    block_h: u32,
) -> ([u8; 3], u64) {
    let x0 = center_x.saturating_sub(block_w / 2);
    let y0 = center_y.saturating_sub(block_h / 2);
    let x1 = (x0 + block_w).min(width);
    let y1 = (y0 + block_h).min(height);

    let mut sum = [0u64; 3];
    let mut count = 0u64;
    for y in y0..y1 {
        for x in x0..x1 {
            let offset = ((y as usize) * (width as usize) + (x as usize)) * 4;
            let Some(pixel) = rgba.get(offset..offset + 4) else {
                continue;
            };
            if pixel[3] == 0 {
                continue;
            }
            sum[0] += pixel[0] as u64;
            sum[1] += pixel[1] as u64;
            sum[2] += pixel[2] as u64;
            count += 1;
        }
    }

    if count == 0 {
        return ([0, 0, 0], 0);
    }
    (
        [
            (sum[0] / count) as u8,
            (sum[1] / count) as u8,
            (sum[2] / count) as u8,
        ],
        count,
    )
}

fn mean_of_edges(
    top: &[[u8; 3]],
    right: &[[u8; 3]],
    bottom: &[[u8; 3]],
    left: &[[u8; 3]],
) -> [u8; 3] {
    let mut sum = [0u64; 3];
    let mut count = 0u64;
    for color in top.iter().chain(right).chain(bottom).chain(left) {
        sum[0] += color[0] as u64;
        sum[1] += color[1] as u64;
        sum[2] += color[2] as u64;
        count += 1;
    }
    if count == 0 {
        return [0, 0, 0];
    }
    [
        (sum[0] / count) as u8,
        (sum[1] / count) as u8,
        (sum[2] / count) as u8,
    ]
}

impl AmbientPalette {
    /// 拼成 `stats_json()` 里那一小段 JSON。
    ///
    /// 自己拼字符串而不是引 `serde_json`：这里只有一个固定形状，
    /// 而且是**每页一次**的调用点，多一个依赖不值当。
    /// 颜色一律 `#rrggbb`，不含引号，所以嵌进外层 JSON 时不需要再转义。
    pub fn to_probe_json(&self) -> String {
        format!(
            "{{\"average\":\"{}\",\"top\":{},\"right\":{},\"bottom\":{},\"left\":{}}}",
            hex(self.average),
            json_colors(&self.top),
            json_colors(&self.right),
            json_colors(&self.bottom),
            json_colors(&self.left),
        )
    }
}

fn json_colors(colors: &[[u8; 3]]) -> String {
    let body: Vec<String> = colors.iter().map(|c| format!("\"{}\"", hex(*c))).collect();
    format!("[{}]", body.join(","))
}

fn hex(color: [u8; 3]) -> String {
    format!("#{:02x}{:02x}{:02x}", color[0], color[1], color[2])
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 造一张 `width × height` 的 RGBA 图，颜色由坐标决定。
    fn make(width: u32, height: u32, f: impl Fn(u32, u32) -> [u8; 4]) -> (Vec<u8>, u32, u32) {
        let mut rgba = Vec::with_capacity((width * height * 4) as usize);
        for y in 0..height {
            for x in 0..width {
                rgba.extend_from_slice(&f(x, y));
            }
        }
        (rgba, width, height)
    }

    #[test]
    fn solid_page_gives_that_color_on_every_edge() {
        let (rgba, w, h) = make(64, 48, |_, _| [200, 30, 40, 255]);
        let palette = sample_rgba(&rgba, w, h);

        assert_eq!(palette.average, [200, 30, 40], "纯色页的代表色就是它本身");
        for edge in [&palette.top, &palette.right, &palette.bottom, &palette.left] {
            assert!(
                edge.iter().all(|c| *c == [200, 30, 40]),
                "纯色页四边应当全是同一个颜色，实际 {edge:?}"
            );
        }
    }

    #[test]
    fn left_and_right_edges_are_sampled_from_their_own_side() {
        // 左半红、右半蓝：这条判据是「方向没搞反」的唯一证据 ——
        // 把 left/right 写反时，纯色页的用例照样全绿。
        let (rgba, w, h) = make(80, 60, |x, _| {
            if x < 40 {
                [255, 0, 0, 255]
            } else {
                [0, 0, 255, 255]
            }
        });
        let palette = sample_rgba(&rgba, w, h);

        assert!(
            palette.left.iter().all(|c| c[0] > 200 && c[2] < 40),
            "左边应当取到红，实际 {:?}",
            palette.left
        );
        assert!(
            palette.right.iter().all(|c| c[2] > 200 && c[0] < 40),
            "右边应当取到蓝，实际 {:?}",
            palette.right
        );
    }

    #[test]
    fn top_and_bottom_edges_are_sampled_from_their_own_side() {
        let (rgba, w, h) = make(60, 80, |_, y| {
            if y < 40 {
                [0, 255, 0, 255]
            } else {
                [255, 255, 0, 255]
            }
        });
        let palette = sample_rgba(&rgba, w, h);

        assert!(
            palette.top.iter().all(|c| c[1] > 200 && c[2] < 40),
            "上边应当取到绿，实际 {:?}",
            palette.top
        );
        assert!(
            palette.bottom.iter().all(|c| c[0] > 200 && c[1] > 200),
            "下边应当取到黄，实际 {:?}",
            palette.bottom
        );
    }

    /// 采样量**与图片尺寸无关**：这是「最高性能」这句话的可校验形式。
    ///
    /// 色标个数恒为 `STOPS`，一张 10000 px 宽的页和一张 100 px 宽的页
    /// 都只读同样多的像素 —— 所以不存在「大图取色变慢」这种退化。
    #[test]
    fn sample_count_does_not_scale_with_page_size() {
        for (w, h) in [(8, 8), (100, 100), (4000, 6000)] {
            let (rgba, w, h) = make(w, h, |_, _| [10, 20, 30, 255]);
            let palette = sample_rgba(&rgba, w, h);
            assert_eq!(palette.top.len(), STOPS);
            assert_eq!(palette.bottom.len(), STOPS);
            assert_eq!(palette.left.len(), STOPS);
            assert_eq!(palette.right.len(), STOPS);
        }
    }

    #[test]
    fn tiny_and_degenerate_pages_do_not_panic() {
        for (w, h) in [(0, 0), (1, 1), (1, 50), (50, 1), (2, 2), (3, 3)] {
            let (rgba, w, h) = make(w, h, |_, _| [1, 2, 3, 255]);
            let palette = sample_rgba(&rgba, w, h);
            assert!(!palette.top.is_empty() || w == 0 || h == 0);
        }
    }

    #[test]
    fn fully_transparent_page_falls_back_to_black() {
        let (rgba, w, h) = make(32, 32, |_, _| [255, 255, 255, 0]);
        let palette = sample_rgba(&rgba, w, h);
        assert_eq!(
            palette.average,
            [0, 0, 0],
            "整页透明时不该把残留的 RGB 当成边色"
        );
    }

    #[test]
    fn transparent_border_is_skipped_when_sampling() {
        // 最外一圈全透明、里面是青色：边色应当取到青而不是透明残留的黑。
        let (rgba, w, h) = make(40, 40, |x, y| {
            if x == 0 || y == 0 || x == 39 || y == 39 {
                [0, 0, 0, 0]
            } else {
                [0, 220, 220, 255]
            }
        });
        let palette = sample_rgba(&rgba, w, h);
        assert!(
            palette.average[1] > 100 && palette.average[2] > 100,
            "透明边应当被跳过，实际代表色 {:?}",
            palette.average
        );
    }

    #[test]
    fn probe_json_shape_is_stable() {
        let (rgba, w, h) = make(32, 32, |_, _| [0x12, 0x34, 0x56, 255]);
        let json = sample_rgba(&rgba, w, h).to_probe_json();

        for key in [
            "\"average\"",
            "\"top\"",
            "\"right\"",
            "\"bottom\"",
            "\"left\"",
        ] {
            assert!(json.contains(key), "probe JSON 缺少 {key}：{json}");
        }
        assert!(json.contains("\"#123456\""), "颜色应当是 #rrggbb：{json}");
        assert!(!json.contains('\n'), "不该有换行：{json}");
    }
}
