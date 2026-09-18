//! 端到端验证：本地文件 → 解码 → wgpu 上传 → letterbox 渲染 → **共享纹理** → 回读比对。
//!
//! # 为什么需要它
//!
//! 「翻页时屏幕上出现的是正确的那一页」这件事，最终得靠人眼看。但**像素是怎么变成
//! 错的**可以自动化地查出来 —— 只要把共享纹理（也就是交给 Flutter 的那张）拷回 CPU
//! 逐点比对。这样链路一断就能立刻知道断在哪一段，而不是"打开 App 发现黑屏"。
//!
//! 它比 PoC 的探针严格的地方在于：PoC 只证明"Flutter 能合成我们的纹理"，
//! 这里证明的是**纹理里装的确实是这一页**。
//!
//! ```text
//! cargo run -p rossi_gpu_present --bin present_probe --features probe -- <路径> [--index 0]
//! ```
//!
//! 判据（全部自动断言，见 `run`）：
//! 1. 底色占比 ≈ letterbox 理论值（页外的黑边真的黑）；
//! 2. 内容包围盒 ≈ 理论绘制矩形（没有偏移 / 没有裁切）；
//! 3. 页内采样点与**同档位重新解码**的基准一致（像素真的搬对了，不是糊的 / 不是错页）；
//! 4. 平均亮度 > 0（不是全黑）。

#[cfg(target_os = "windows")]
mod win {
    use std::path::PathBuf;
    use std::time::Instant;

    use anyhow::{anyhow, Context, Result};
    use clap::Parser;
    use rossi_gpu_present::{Presenter, BACKGROUND_RGBA8};
    use rossi_local_core::LocalSource;

    #[derive(Parser, Debug)]
    #[command(
        name = "present_probe",
        about = "验证 GPU 呈现链路：解码 → 共享纹理 → 回读比对"
    )]
    struct Args {
        /// 本地来源路径（散图文件夹 / .cbz / .cbr）。
        path: PathBuf,
        /// 呈现哪一页（0 基）。
        #[arg(long, default_value_t = 0)]
        index: u32,
        /// 呈现目标的宽度（模拟引擎请求的 widget 尺寸）。
        #[arg(long, default_value_t = 900)]
        width: u32,
        /// 呈现目标的高度。
        #[arg(long, default_value_t = 1300)]
        height: u32,
        /// 重复呈现几次，用于看稳定态耗时（第一次含纹理创建）。
        #[arg(long, default_value_t = 1)]
        repeat: u32,
        /// 把结论写进这个 JSON 文件（给无人值守的脚本读）。
        #[arg(long)]
        out: Option<PathBuf>,
    }

    /// 页内采样的容差。
    ///
    /// 不设成 0 是因为两边会差在"采样方式"而不是"内容"上：
    /// GPU 侧是双线性采样（解码宽度与绘制宽度不总是整数比），基准侧取最近邻。
    /// 只要不是被放大很多倍，平坦区的偏差是个位数。放大场景下边缘会差得多，
    /// 所以下面的断言是"**绝大多数**采样点在容差内"而不是"全部"。
    const SAMPLE_TOLERANCE: i32 = 24;
    const SAMPLE_GRID: [f32; 5] = [0.1, 0.3, 0.5, 0.7, 0.9];

    struct SampleResult {
        checked: usize,
        within: usize,
        max_diff: i32,
    }

    pub fn run() -> Result<()> {
        let args = Args::parse();

        let reference = LocalSource::open(&args.path)
            .with_context(|| format!("打开基准来源失败: {}", args.path.display()))?;
        let page_count = reference.len();
        let index = args.index as usize;
        if index >= page_count {
            return Err(anyhow!("页下标越界: {index} / {page_count}"));
        }

        println!("来源   : {}", args.path.display());
        println!("页数   : {page_count}，本次呈现第 {} 页", index + 1);
        println!("目标   : {}×{}", args.width, args.height);

        let t_init = Instant::now();
        // LUID = 0：没有 Flutter 可问，交给呈现器自己挑一块高性能卡。
        let mut presenter =
            Presenter::new(0, args.width, args.height).context("创建 GPU 呈现器失败")?;
        println!(
            "适配器 : {}（初始化 {:.0} ms，直接共享 wgpu 纹理: {}）",
            presenter.adapter_name(),
            t_init.elapsed().as_secs_f64() * 1000.0,
            presenter.direct_share_verdict()
        );

        let opened = presenter.open(&args.path.to_string_lossy())?;
        println!("核心   : 打开成功，{opened} 页，自然序首项 = (Rust 侧决定，Dart 不再排)");

        let mut last_total = 0.0;
        for round in 0..args.repeat.max(1) {
            let timings = presenter
                .show(index)
                .with_context(|| format!("呈现第 {} 页失败", index + 1))?;
            last_total = timings.total_ms;
            if args.repeat > 1 {
                println!(
                    "第 {round} 轮: 解码 {:.1} / 上传 {:.1} / 提交 {:.1} / 合计 {:.1} ms",
                    timings.decode_ms, timings.upload_ms, timings.submit_ms, timings.total_ms
                );
            }
        }

        let timings = presenter.last_timings();
        println!(
            "\n分段耗时（末轮）: 解码 {:.1} ms，上传 {:.1} ms，渲染+提交 {:.1} ms，合计 {:.1} ms",
            timings.decode_ms, timings.upload_ms, timings.submit_ms, last_total
        );
        println!(
            "解码档位: {}×{}（原图 {}×{}，降采样 {}）",
            presenter.decoded_width(),
            presenter.decoded_height(),
            presenter.source_width(),
            presenter.source_height(),
            if presenter.source_width() > presenter.decoded_width() {
                "生效"
            } else {
                "未生效（原图本来就小）"
            }
        );

        // ── 回读 ──
        let t_readback = Instant::now();
        let frame = presenter.readback_bgra().context("回读共享纹理失败")?;
        let readback_ms = t_readback.elapsed().as_secs_f64() * 1000.0;

        // ── 判据 1：底色占比 ≈ letterbox 理论值 ──
        let (x, y, draw_w, draw_h) = presenter
            .expected_draw_rect()
            .ok_or_else(|| anyhow!("拿不到理论绘制矩形"))?;
        let expected_bg =
            1.0 - (draw_w as f64 * draw_h as f64) / (frame.width as f64 * frame.height as f64);
        let actual_bg = frame.background_ratio();

        // ── 判据 2：内容包围盒 ≈ 理论绘制矩形 ──
        let bounds = frame.content_bounds();
        let bounds_ok = match bounds {
            None => false,
            Some((x0, y0, x1, y1)) => {
                // 采样时的双线性会在边界多染一圈像素，放宽到 3 px。
                let tolerance = 3i64;
                (x0 as i64 - x.round() as i64).abs() <= tolerance
                    && (y0 as i64 - y.round() as i64).abs() <= tolerance
                    && (x1 as i64 - (x + draw_w).round() as i64).abs() <= tolerance
                    && (y1 as i64 - (y + draw_h).round() as i64).abs() <= tolerance
            }
        };

        // ── 判据 3：页内采样点与基准一致 ──
        //
        // 基准用**同一个解码宽度提示**重解一遍 —— 两边的降采样档位必须一致，
        // 否则比出来的差异来自降采样而不是来自 GPU 路径。
        let hint = presenter.decode_hint();
        let baseline = reference
            .page_pixels_scaled(index, Some(hint))
            .context("基准解码失败")?;
        let samples = compare_samples(
            &frame,
            &baseline.rgba,
            baseline.width,
            baseline.height,
            x,
            y,
            draw_w,
            draw_h,
        );

        // ── 判据 4：不是全黑 ──
        let luma = frame.mean_luma();

        println!(
            "\n回读   : {}×{}（{:.0} ms）",
            frame.width, frame.height, readback_ms
        );
        println!(
            "底色占比: 实际 {:.3} / 理论 {:.3}（差 {:.4}）",
            actual_bg,
            expected_bg,
            (actual_bg - expected_bg).abs()
        );
        match bounds {
            Some((x0, y0, x1, y1)) => println!(
                "内容包围: ({x0}, {y0}) - ({x1}, {y1}) / 理论 ({:.0}, {:.0}) - ({:.0}, {:.0})",
                x,
                y,
                x + draw_w,
                y + draw_h
            ),
            None => println!("内容包围: 无（整屏都是底色）"),
        }
        println!(
            "采样比对: {}/{} 在容差 {SAMPLE_TOLERANCE} 内，最大通道差 {}",
            samples.within, samples.checked, samples.max_diff
        );
        println!("平均亮度: {luma:.1} / 255");

        let verdicts = [
            (
                "底色占比符合 letterbox",
                (actual_bg - expected_bg).abs() < 0.02,
            ),
            ("内容包围盒符合绘制矩形", bounds_ok),
            (
                "页内像素与基准一致",
                samples.checked > 0
                    && samples.within * 10 >= samples.checked * 9
                    && samples.max_diff <= SAMPLE_TOLERANCE * 3,
            ),
            ("不是全黑", luma > 1.0),
        ];

        println!();
        let mut failed = Vec::new();
        for (name, ok) in verdicts {
            println!("  [{}] {name}", if ok { "通过" } else { "失败" });
            if !ok {
                failed.push(name);
            }
        }

        if let Some(out) = &args.out {
            let json = format!(
                concat!(
                    "{{",
                    "\"path\":\"{}\",",
                    "\"index\":{},",
                    "\"pageCount\":{},",
                    "\"targetWidth\":{},",
                    "\"targetHeight\":{},",
                    "\"decodedWidth\":{},",
                    "\"decodedHeight\":{},",
                    "\"sourceWidth\":{},",
                    "\"sourceHeight\":{},",
                    "\"decodeMs\":{:.2},",
                    "\"uploadMs\":{:.2},",
                    "\"submitMs\":{:.2},",
                    "\"totalMs\":{:.2},",
                    "\"readbackMs\":{:.2},",
                    "\"backgroundRatio\":{:.4},",
                    "\"expectedBackgroundRatio\":{:.4},",
                    "\"meanLuma\":{:.2},",
                    "\"samplesChecked\":{},",
                    "\"samplesWithinTolerance\":{},",
                    "\"maxChannelDiff\":{},",
                    "\"directShareOfWgpuTexture\":\"{}\",",
                    "\"adapter\":\"{}\",",
                    "\"failed\":[{}]",
                    "}}"
                ),
                escape(&args.path.to_string_lossy()),
                index,
                page_count,
                args.width,
                args.height,
                presenter.decoded_width(),
                presenter.decoded_height(),
                presenter.source_width(),
                presenter.source_height(),
                timings.decode_ms,
                timings.upload_ms,
                timings.submit_ms,
                last_total,
                readback_ms,
                actual_bg,
                expected_bg,
                luma,
                samples.checked,
                samples.within,
                samples.max_diff,
                escape(presenter.direct_share_verdict()),
                escape(presenter.adapter_name()),
                failed
                    .iter()
                    .map(|name| format!("\"{}\"", escape(name)))
                    .collect::<Vec<_>>()
                    .join(","),
            );
            std::fs::write(out, json).with_context(|| format!("写报告失败: {}", out.display()))?;
            println!("\n报告已写入 {}", out.display());
        }

        if failed.is_empty() {
            println!("\n结论: 共享纹理里的像素与解码结果一致 —— 这条链路是通的。");
            Ok(())
        } else {
            Err(anyhow!(
                "有 {} 条判据未通过: {}",
                failed.len(),
                failed.join("、")
            ))
        }
    }

    /// 在页内取网格采样点，与基准逐点比通道差。
    ///
    /// 坐标映射用的是**同一套 letterbox 算式**的结果（由呈现器给出），
    /// 所以这一步同时也在验证"呈现器算出来的矩形"和"实际画出来的矩形"一致。
    fn compare_samples(
        frame: &rossi_gpu_present::Readback,
        baseline_rgba: &[u8],
        baseline_width: u32,
        baseline_height: u32,
        x: f32,
        y: f32,
        draw_w: f32,
        draw_h: f32,
    ) -> SampleResult {
        let mut checked = 0usize;
        let mut within = 0usize;
        let mut max_diff = 0i32;

        for fy in SAMPLE_GRID {
            for fx in SAMPLE_GRID {
                let target_x = (x + fx * draw_w).floor() as u32;
                let target_y = (y + fy * draw_h).floor() as u32;
                if target_x >= frame.width || target_y >= frame.height {
                    continue;
                }
                let base_x = ((fx * (baseline_width.saturating_sub(1)) as f32).round()) as u32;
                let base_y = ((fy * (baseline_height.saturating_sub(1)) as f32).round()) as u32;
                let base_offset = ((base_y * baseline_width + base_x) * 4) as usize;
                if base_offset + 4 > baseline_rgba.len() {
                    continue;
                }

                // 回读是 BGRA，基准是 RGBA —— 这里正是**通道顺序**最容易被搞错的地方，
                // 所以两个顺序都算一遍，取更接近的那个只会掩盖问题，
                // 因此这里严格按 BGRA 解释（Flutter 侧的格式声明也是 BGRA8888）。
                let [b, g, r, _] = frame.pixel(target_x, target_y);
                let reference = [
                    baseline_rgba[base_offset],
                    baseline_rgba[base_offset + 1],
                    baseline_rgba[base_offset + 2],
                ];
                let got = [r, g, b];
                let diff = (0..3)
                    .map(|channel| (got[channel] as i32 - reference[channel] as i32).abs())
                    .max()
                    .unwrap_or(0);

                checked += 1;
                max_diff = max_diff.max(diff);
                if diff <= SAMPLE_TOLERANCE {
                    within += 1;
                }
            }
        }

        SampleResult {
            checked,
            within,
            max_diff,
        }
    }

    fn escape(text: &str) -> String {
        text.replace('\\', "\\\\").replace('"', "\\\"")
    }

    /// 底色常量在探针里也要用到（报告里会写进去），这里做一次存在性检查，
    /// 免得将来改了着色器而这里忘了同步。
    #[allow(dead_code)]
    fn background_reference() -> [u8; 4] {
        BACKGROUND_RGBA8
    }
}

#[cfg(target_os = "windows")]
fn main() {
    if let Err(error) = win::run() {
        eprintln!("\n失败: {error:#}");
        std::process::exit(1);
    }
}

#[cfg(not(target_os = "windows"))]
fn main() {
    eprintln!("present_probe 只在 Windows 上有意义（D3D12 共享纹理）。");
    std::process::exit(2);
}
