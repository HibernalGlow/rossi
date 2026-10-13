//! 非破坏式色调补正与 AI 档位身份 —— 上游 mImageViewer `src/adjustment.rs` 的 CPU 内核（MIT）。
//! Copyright (c) 2026 SANO Taku (Mikage Sawatari), MIT.
//!
//! 逐字抽取（`upstream_sources.json` 的 `adjustment` 条目，由 `build.rs` 在编译期取进 `OUT_DIR`）：
//! `HISTOGRAM_SAMPLE_LIMIT` / `AutoMode` / `color_log_summary` / `build_u8_lut` /
//! `apply_brightness_contrast` / `apply_saturation` / `apply_temperature` / `apply_color_pipeline`。
//! 名字、量程、默认值与处理顺序全部保持上游原样（AGENTS.md §13「搬运保住上游的名字」）。
//!
//! 刻意偏离（登记在 `script/sync_vendored_modules.py` 的 `PORTS`，负责人见
//! `docs/mimageviewer-reuse-inventory.json`）：
//!
//! 1. **像素载体**是 RGBA8 字节切片（步长 4），不是 `egui::Color32` / `egui::ColorImage`。
//!    本仓解码层交付的就是这份未预乘字节，GPU 呈现层收的也是它（ADR-0024 §决定 1）；
//!    上游那对 `pixels_to_f32` / `f32_to_image` 因此不需要 —— 少了两次整页搬运。
//!    受影响的上游项：`pixel_lum` / `apply_pipeline_u8_lut` / `build_luma_histogram` /
//!    `resolve_auto_mode` / `compute_auto_levels` / `compute_manga_levels`，公式逐字照抄，只换取像素的方式。
//! 2. `AdjustParams` **不含** `post_filter` / `creative_lut` / `colorize` —— ADR-0024 明确不做风格化滤镜与上色。
//!    因此 `is_identity()` 少了那三项判定，`differs_only_in_final_stage()` 整条不搬（它比的正是那三项）。
//! 3. `ai_settings_eq()` **额外比较档序**。上游只比两个模型标识，因为上游没有可选档序；
//!    本仓「降噪→超分」与「超分→降噪」是两种产物（ADR-0024 §决定 1），档序一变 AI 缓存就必须失效。
//! 4. `smart_sharpen` 只进参数与档间判定（`effective_smart_sharpen` 逐字照抄上游），
//!    **锐化核本身**在 `crates/local-adjust-core` 里（`apply_smart_sharpen_rgba`），
//!    随局部调整层那一步一起接入，见 ADR-0024 §决定 3 与 ROADMAP 阶段 B。

use serde::{Deserialize, Serialize};

use crate::PagePixels;

include!(concat!(env!("OUT_DIR"), "/adjustment.rs"));

/// AI 档的执行顺序。**顺序是产物的一部分**，不是实现细节：
/// 降噪在超分之前清的是原始压缩噪声，之后清的是放大出来的噪声，网点保留程度不同。
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AdjustStageOrder {
    /// 先 1× 降噪，再放大。默认。
    DenoiseThenUpscale,
    /// 先放大，再降噪。
    UpscaleThenDenoise,
}

impl Default for AdjustStageOrder {
    fn default() -> Self {
        Self::DenoiseThenUpscale
    }
}

/// 画像補正パラメータ。字段名、量程与默认值对齐上游同名结构。
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct AdjustParams {
    pub brightness: f32,  // -100..+100
    pub contrast: f32,    // -100..+100
    pub gamma: f32,       // 0.2..5.0
    pub saturation: f32,  // -100..+100
    pub temperature: f32, // -100..+100
    pub black_point: u8,  // 0..255
    pub white_point: u8,  // 0..255
    pub midtone: f32,     // 0.1..10.0
    pub auto_mode: Option<AutoMode>,
    /// 最終表示段スマートシャープの強度。0 = OFF, 1..=100。
    pub smart_sharpen: u8,
    /// AI 超分模型。`None` = off。
    pub upscale_model: Option<String>,
    /// AI 降噪模型（1×，不改输出分辨率）。`None` = off。
    pub denoise_model: Option<String>,
    /// 降噪与超分谁先跑。只在两档都开的时候有意义。
    pub stage_order: AdjustStageOrder,
}

impl Default for AdjustParams {
    fn default() -> Self {
        Self {
            brightness: 0.0,
            contrast: 0.0,
            gamma: 1.0,
            saturation: 0.0,
            temperature: 0.0,
            black_point: 0,
            white_point: 255,
            midtone: 1.0,
            auto_mode: None,
            smart_sharpen: 0,
            upscale_model: None,
            denoise_model: None,
            stage_order: AdjustStageOrder::default(),
        }
    }
}

impl AdjustParams {
    /// 色調パラメータのみ無補正か (post-filter は問わない)。
    pub fn is_color_identity(&self) -> bool {
        self.brightness == 0.0
            && self.contrast == 0.0
            && self.gamma == 1.0
            && self.saturation == 0.0
            && self.temperature == 0.0
            && self.black_point == 0
            && self.white_point == 255
            && self.midtone == 1.0
            && self.auto_mode.is_none()
    }

    /// すべてのパラメータがデフォルト値か（偏离 2：本仓没有 post_filter / LUT / 上色）。
    pub fn is_identity(&self) -> bool {
        self.is_color_identity()
            && self.smart_sharpen == 0
            && !self.needs_upscale()
            && !self.needs_denoise()
    }

    pub fn needs_upscale(&self) -> bool {
        self.upscale_model.is_some()
    }

    pub fn needs_denoise(&self) -> bool {
        self.denoise_model.is_some()
    }

    /// ページ個別設定として保存する価値がないか (= identity かつ AI も使わない)。
    pub fn is_removable(&self) -> bool {
        self.is_identity() && !self.needs_upscale() && !self.needs_denoise()
    }

    /// AI 設定 (upscale/denoise/**档序**) が other と同じか。
    /// 色调只变了的话 AI 缓存要保住；档序变了则缓存必须失效（偏离 3）。
    pub fn ai_settings_eq(&self, other: &Self) -> bool {
        self.upscale_model == other.upscale_model
            && self.denoise_model == other.denoise_model
            && self.stage_order == other.stage_order
    }

    /// 色調設定 (サムネ補正に乗る brightness..midtone + auto_mode) が other と同じか。
    pub fn color_settings_eq(&self, other: &Self) -> bool {
        self.brightness == other.brightness
            && self.contrast == other.contrast
            && self.gamma == other.gamma
            && self.saturation == other.saturation
            && self.temperature == other.temperature
            && self.black_point == other.black_point
            && self.white_point == other.white_point
            && self.midtone == other.midtone
            && self.auto_mode == other.auto_mode
    }

    /// 最終合成で実際に使うシャープ化強度を解決する。
    /// アップスケール出力には常に 0 (= スキップ、固定動作)。
    /// デノイズのみ・サイズ上限スキップには通常どおり強度を返す。
    pub fn effective_smart_sharpen(&self, output_is_ai_upscaled: bool) -> u8 {
        if output_is_ai_upscaled {
            0
        } else {
            self.smart_sharpen
        }
    }

    /// 派生图像的缓存身份：每一档的模型标识 + 参数 + **档序**（ADR-0024 §决定 2）。
    /// 少任何一项，就会出现「开了开关画面没变」——命中的是上一份未处理的产物。
    pub fn fingerprint(&self) -> String {
        format!(
            "color[{}]|auto[{:?}]|sharpen[{}]|ai[{}/{}/{:?}]",
            color_log_summary(self),
            self.auto_mode,
            self.smart_sharpen,
            self.denoise_model.as_deref().unwrap_or("off"),
            self.upscale_model.as_deref().unwrap_or("off"),
            self.stage_order,
        )
    }
}

#[inline]
fn pixel_lum(p: &[u8]) -> u8 {
    ((p[0] as u32 * 77 + p[1] as u32 * 150 + p[2] as u32 * 29) >> 8) as u8
}

/// u8→u8 LUT で全パイプラインを処理する高速パス。alpha 原样保留。
fn apply_pipeline_u8_lut(rgba: &mut [u8], params: &AdjustParams) {
    let lut = build_u8_lut(params);
    let full_desat = params.saturation == -100.0;
    let has_sat = params.saturation != 0.0;
    let sat_factor = 1.0 + params.saturation / 100.0;

    for p in rgba.chunks_exact_mut(4) {
        let (mut r, mut g, mut b) = (lut[p[0] as usize], lut[p[1] as usize], lut[p[2] as usize]);
        if full_desat {
            let lum = pixel_lum(&[r, g, b, 255]);
            r = lum;
            g = lum;
            b = lum;
        } else if has_sat {
            let (r01, g01, b01) = (r as f32 / 255.0, g as f32 / 255.0, b as f32 / 255.0);
            let max = r01.max(g01).max(b01);
            let min = r01.min(g01).min(b01);
            if (max - min).abs() >= 1e-6 {
                let lum = (max + min) * 0.5;
                r = ((lum + (r01 - lum) * sat_factor) * 255.0).clamp(0.0, 255.0) as u8;
                g = ((lum + (g01 - lum) * sat_factor) * 255.0).clamp(0.0, 255.0) as u8;
                b = ((lum + (b01 - lum) * sat_factor) * 255.0).clamp(0.0, 255.0) as u8;
            }
        }
        p[0] = r;
        p[1] = g;
        p[2] = b;
    }
}

/// 色調補正を適用する（上游 `apply_adjustments_fast` 的同位入口）。
/// 色温度ゼロなら u8 LUT 高速パス、ありなら f32 パイプライン。
pub fn apply_adjustments_rgba(rgba: &mut [u8], params: &AdjustParams) {
    let effective = resolve_auto_mode(rgba, params);
    if effective.temperature == 0.0 {
        apply_pipeline_u8_lut(rgba, &effective);
        return;
    }
    let mut buf: Vec<[f32; 3]> = rgba
        .chunks_exact(4)
        .map(|p| [p[0] as f32, p[1] as f32, p[2] as f32])
        .collect();
    apply_color_pipeline(&mut buf, &effective);
    for (p, [r, g, b]) in rgba.chunks_exact_mut(4).zip(buf) {
        p[0] = r.clamp(0.0, 255.0) as u8;
        p[1] = g.clamp(0.0, 255.0) as u8;
        p[2] = b.clamp(0.0, 255.0) as u8;
    }
}

/// 就地补正一整页解码像素。非破坏式：调用方持有的这份 `PagePixels` 已经是派生物，
/// 归档里的原始页从头到尾没被写过（ADR-0024 §决定 1）。
pub fn apply_adjustments(page: &mut PagePixels, params: &AdjustParams) {
    apply_adjustments_rgba(&mut page.rgba, params);
}

/// 輝度ヒストグラムを構築する。大きな画像では LCG ランダムサンプリングで高速化。
/// 戻り値: (histogram[256], sample_count)
fn build_luma_histogram(rgba: &[u8]) -> ([u64; 256], u64) {
    let mut hist = [0u64; 256];
    let n = rgba.len() / 4;
    if n == 0 {
        return (hist, 0);
    }
    if n <= HISTOGRAM_SAMPLE_LIMIT {
        for p in rgba.chunks_exact(4) {
            hist[pixel_lum(p) as usize] += 1;
        }
        (hist, n as u64)
    } else {
        // LCG ランダムサンプリング (Vec 割り当てなし)
        let m = n as u64;
        let a: u64 = 6364136223846793005;
        let c: u64 = 1442695040888963407;
        let mut x: u64 = 42;
        let sample_count = HISTOGRAM_SAMPLE_LIMIT as u64;
        for _ in 0..sample_count {
            x = x.wrapping_mul(a).wrapping_add(c);
            let idx = (x % m) as usize;
            hist[pixel_lum(&rgba[idx * 4..idx * 4 + 4]) as usize] += 1;
        }
        (hist, sample_count)
    }
}

fn resolve_auto_mode(rgba: &[u8], params: &AdjustParams) -> AdjustParams {
    let mut p = params.clone();
    match p.auto_mode {
        None => {}
        Some(AutoMode::Auto) => {
            let (bp, wp) = compute_auto_levels(rgba, 0.005);
            p.black_point = bp;
            p.white_point = wp;
        }
        Some(AutoMode::MangaCleanup) => {
            p.saturation = -100.0;
            let (bp, wp) = compute_manga_levels(rgba);
            p.black_point = bp;
            p.white_point = wp;
            p.gamma = 0.85;
            p.contrast = p.contrast.max(15.0);
        }
    }
    p
}

fn compute_auto_levels(rgba: &[u8], clip_ratio: f64) -> (u8, u8) {
    let (hist, sample_count) = build_luma_histogram(rgba);
    let total = sample_count as f64;
    let low_threshold = (total * clip_ratio) as u64;
    let high_threshold = (total * (1.0 - clip_ratio)) as u64;

    let mut cum = 0u64;
    let mut bp = 0u8;
    for (i, &count) in hist.iter().enumerate() {
        cum += count;
        if cum >= low_threshold {
            bp = i as u8;
            break;
        }
    }
    cum = 0;
    let mut wp = 255u8;
    for (i, &count) in hist.iter().enumerate() {
        cum += count;
        if cum >= high_threshold {
            wp = i as u8;
            break;
        }
    }
    (bp, wp.max(bp + 1))
}

fn compute_manga_levels(rgba: &[u8]) -> (u8, u8) {
    let (hist, _) = build_luma_histogram(rgba);

    let mut max_count = 0u64;
    let mut paper_lum = 240u8;
    for i in 180..256 {
        if hist[i] > max_count {
            max_count = hist[i];
            paper_lum = i as u8;
        }
    }
    let wp = paper_lum.saturating_sub(10);

    let mut max_dark = 0u64;
    let mut ink_lum = 20u8;
    for i in 0..80 {
        if hist[i] > max_dark {
            max_dark = hist[i];
            ink_lum = i as u8;
        }
    }
    let bp = ink_lum.saturating_add(5);
    (bp, wp.max(bp + 1))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn solid(rgba: [u8; 4], n: usize) -> Vec<u8> {
        rgba.repeat(n)
    }

    /// 白纸 + 浓墨的黑白页，用于自动档位的夹具。
    fn manga_page(white: usize, ink: usize) -> Vec<u8> {
        let mut buf = solid([250, 250, 250, 255], white);
        buf.extend_from_slice(&solid([10, 10, 10, 255], ink));
        buf
    }

    #[test]
    fn identity_params_no_change() {
        let src = solid([120, 60, 200, 255], 8);
        let mut buf = src.clone();
        apply_adjustments_rgba(&mut buf, &AdjustParams::default());
        assert_eq!(buf, src, "无补正参数却动了像素");
    }

    #[test]
    fn brightness_increases() {
        let mut buf = solid([100, 100, 100, 255], 4);
        let p = AdjustParams {
            brightness: 30.0,
            ..Default::default()
        };
        apply_adjustments_rgba(&mut buf, &p);
        assert!(buf[0] > 100, "亮度 +30 应当让灰点变亮，实得 {}", buf[0]);
    }

    #[test]
    fn temperature_moves_red_up_blue_down() {
        let mut warm = solid([128, 128, 128, 255], 4);
        apply_adjustments_rgba(
            &mut warm,
            &AdjustParams {
                temperature: 40.0,
                ..Default::default()
            },
        );
        assert!(
            warm[0] > warm[2],
            "正色温应当偏暖：R {} vs B {}",
            warm[0],
            warm[2]
        );

        let mut cool = solid([128, 128, 128, 255], 4);
        apply_adjustments_rgba(
            &mut cool,
            &AdjustParams {
                temperature: -40.0,
                ..Default::default()
            },
        );
        assert!(
            cool[2] > cool[0],
            "负色温应当偏冷：R {} vs B {}",
            cool[0],
            cool[2]
        );
    }

    #[test]
    fn saturation_minus_100_is_grayscale() {
        let mut buf = solid([200, 80, 40, 255], 4);
        apply_adjustments_rgba(
            &mut buf,
            &AdjustParams {
                saturation: -100.0,
                ..Default::default()
            },
        );
        assert_eq!(buf[0], buf[1]);
        assert_eq!(buf[1], buf[2], "饱和度 -100 必须落到灰度");
    }

    #[test]
    fn partial_saturation_keeps_hue_direction() {
        let mut buf = solid([200, 80, 40, 255], 4);
        apply_adjustments_rgba(
            &mut buf,
            &AdjustParams {
                saturation: 60.0,
                ..Default::default()
            },
        );
        assert!(buf[0] > 200 || buf[2] < 40, "正饱和度应当拉大红蓝距离");
    }

    #[test]
    fn alpha_is_preserved_on_both_paths() {
        let mut lut_path = solid([10, 20, 30, 77], 4);
        apply_adjustments_rgba(
            &mut lut_path,
            &AdjustParams {
                brightness: 20.0,
                ..Default::default()
            },
        );
        assert_eq!(lut_path[3], 77, "u8 LUT 高速路径吃掉 alpha");

        let mut f32_path = solid([10, 20, 30, 77], 4);
        apply_adjustments_rgba(
            &mut f32_path,
            &AdjustParams {
                brightness: 20.0,
                temperature: 10.0,
                ..Default::default()
            },
        );
        assert_eq!(f32_path[3], 77, "f32 路径吃掉 alpha");
    }

    #[test]
    fn auto_level_sets_points() {
        let p = AdjustParams {
            auto_mode: Some(AutoMode::Auto),
            ..Default::default()
        };
        let page = manga_page(4000, 1000);
        let resolved = resolve_auto_mode(&page, &p);
        assert!(
            resolved.black_point < resolved.white_point,
            "自动档黑点必须低于白点：{} vs {}",
            resolved.black_point,
            resolved.white_point
        );
    }

    #[test]
    fn manga_cleanup_overrides_saturation_gamma_and_points() {
        let p = AdjustParams {
            auto_mode: Some(AutoMode::MangaCleanup),
            ..Default::default()
        };
        let page = manga_page(4000, 1000);
        let resolved = resolve_auto_mode(&page, &p);
        assert_eq!(resolved.saturation, -100.0, "漫画清理必须去色");
        assert_eq!(resolved.gamma, 0.85);
        assert!(resolved.contrast >= 15.0);
        // 纸峰 250 → 白点 240；墨峰 10 → 黑点 15（上游 paper_lum-10 / ink_lum+5）
        assert_eq!(resolved.white_point, 240);
        assert_eq!(resolved.black_point, 15);
    }

    #[test]
    fn fingerprint_separates_stage_order() {
        let denoise_first = AdjustParams {
            denoise_model: Some("realplksr".into()),
            upscale_model: Some("cugan4x".into()),
            stage_order: AdjustStageOrder::DenoiseThenUpscale,
            ..Default::default()
        };
        let upscale_first = AdjustParams {
            stage_order: AdjustStageOrder::UpscaleThenDenoise,
            ..denoise_first.clone()
        };
        assert_ne!(
            denoise_first.fingerprint(),
            upscale_first.fingerprint(),
            "档序不同必须落到不同缓存档，否则切顺序等于没切"
        );
        assert!(
            !denoise_first.ai_settings_eq(&upscale_first),
            "档序变了还不失效 AI 缓存 = 复用错产物"
        );
    }

    #[test]
    fn fingerprint_changes_with_every_tuning_field() {
        let base = AdjustParams::default();
        let mut probe = base.clone();
        probe.brightness = 1.0;
        assert_ne!(base.fingerprint(), probe.fingerprint());
        probe = base.clone();
        probe.contrast = 1.0;
        assert_ne!(base.fingerprint(), probe.fingerprint());
        probe = base.clone();
        probe.gamma = 1.1;
        assert_ne!(base.fingerprint(), probe.fingerprint());
        probe = base.clone();
        probe.saturation = 1.0;
        assert_ne!(base.fingerprint(), probe.fingerprint());
        probe = base.clone();
        probe.temperature = 1.0;
        assert_ne!(base.fingerprint(), probe.fingerprint());
        probe = base.clone();
        probe.black_point = 5;
        assert_ne!(base.fingerprint(), probe.fingerprint());
        probe = base.clone();
        probe.white_point = 250;
        assert_ne!(base.fingerprint(), probe.fingerprint());
        probe = base.clone();
        probe.midtone = 1.1;
        assert_ne!(base.fingerprint(), probe.fingerprint());
        probe = base.clone();
        probe.auto_mode = Some(AutoMode::Auto);
        assert_ne!(base.fingerprint(), probe.fingerprint());
        probe = base.clone();
        probe.smart_sharpen = 30;
        assert_ne!(base.fingerprint(), probe.fingerprint());
        probe = base.clone();
        probe.denoise_model = Some("realplksr".into());
        assert_ne!(base.fingerprint(), probe.fingerprint());
        probe = base.clone();
        probe.upscale_model = Some("cugan4x".into());
        assert_ne!(base.fingerprint(), probe.fingerprint());

        // 反向对照：参数完全一样的两份必须同名，否则缓存永远不会命中，改回原值也白跑。
        assert_eq!(base.fingerprint(), AdjustParams::default().fingerprint());
    }

    #[test]
    fn color_only_change_keeps_ai_cache() {
        let a = AdjustParams {
            upscale_model: Some("cugan4x".into()),
            ..Default::default()
        };
        let b = AdjustParams {
            upscale_model: Some("cugan4x".into()),
            brightness: 25.0,
            ..Default::default()
        };
        assert!(!a.color_settings_eq(&b), "色调变了必须被检出");
        assert!(a.ai_settings_eq(&b), "只有色调变了，AI 产物要能复用");
        assert_ne!(a.fingerprint(), b.fingerprint(), "但显示档名必须换");
    }

    #[test]
    fn effective_smart_sharpen_always_skips_upscaled_output() {
        let p = AdjustParams {
            smart_sharpen: 60,
            upscale_model: Some("cugan4x".into()),
            ..Default::default()
        };
        assert_eq!(p.effective_smart_sharpen(true), 0, "放大产物不许二次锐化");
        assert_eq!(p.effective_smart_sharpen(false), 60);

        // 仅降噪 / 被尺寸上限跳过：那不是放大输出，照常锐化。
        let denoise_only = AdjustParams {
            smart_sharpen: 60,
            denoise_model: Some("realplksr".into()),
            ..Default::default()
        };
        assert_eq!(denoise_only.effective_smart_sharpen(false), 60);
    }

    #[test]
    fn removable_when_nothing_is_on() {
        assert!(AdjustParams::default().is_removable());
        assert!(
            !AdjustParams {
                brightness: 1.0,
                ..Default::default()
            }
            .is_removable()
        );
        assert!(
            !AdjustParams {
                denoise_model: Some("realplksr".into()),
                ..Default::default()
            }
            .is_removable()
        );
    }

    #[test]
    fn apply_adjustments_touches_only_page_pixels() {
        let mut page = PagePixels {
            width: 2,
            height: 1,
            source_width: 4,
            source_height: 2,
            rgba: solid([100, 100, 100, 255], 2),
        };
        let before = page.rgba.clone();
        apply_adjustments(&mut page, &AdjustParams::default());
        assert_eq!(page.rgba, before);
        apply_adjustments(
            &mut page,
            &AdjustParams {
                gamma: 2.0,
                ..Default::default()
            },
        );
        assert_ne!(page.rgba, before, "gamma 2.0 应当改变像素");
        assert_eq!(page.width, 2, "色调补正不许改尺寸（改尺寸是超分那一档）");
    }

    #[test]
    fn fingerprint_is_stable_across_equal_params() {
        let a = AdjustParams {
            brightness: 12.0,
            gamma: 0.9,
            auto_mode: Some(AutoMode::MangaCleanup),
            ..Default::default()
        };
        let b = a.clone();
        assert_eq!(a.fingerprint(), b.fingerprint());
        assert_eq!(
            a.fingerprint(),
            a.fingerprint(),
            "同一份参数两次算出不同档名 = 缓存永远打不中"
        );
    }
}
