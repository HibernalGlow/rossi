//! 基于 wgpu 与 WGSL 的跨平台高性能 GPU 图像重采样与视口呈现器。
//!
//! 统一承载：
//! 1. 毫秒级 GPU Lanczos3 / 双线性等比缩放（取代 CPU `fast_image_resize`）；
//! 2. 毫秒级 GPU Anime4K / 边缘锐化实时滤镜；
//! 3. 视口 Letterbox 居中对齐，图片外透明以透出阅读器背景；
//! 4. RGBA8 -> BGRA8 硬件格式无开销自动转换。

use anyhow::{anyhow, Result};
use std::sync::Arc;
use wgpu::util::DeviceExt;
mod render;
mod source;

pub use source::SourceTextureInfo;
use source::{CachedSource, SourceInput};

/// 一次离屏重采样的 CPU 墙钟分段。
///
/// 这些字段描述命令准备、提交、GPU 完成等待和映射后的 CPU 拷贝；
/// 它们不是 GPU shader 的独占执行时间。
#[derive(Debug, Clone, Copy, Default)]
pub struct ResampleTimings {
    pub target_setup_ms: f64,
    pub source_setup_ms: f64,
    pub upload_ms: f64,
    pub uploaded_bytes: u64,
    pub source_reused: bool,
    pub mipmap_generated_levels: u32,
    pub mipmap_encode_ms: f64,
    pub mipmap_submit_ms: f64,
    pub render_encode_ms: f64,
    pub render_submit_ms: f64,
    pub readback_encode_ms: f64,
    pub readback_submit_ms: f64,
    pub gpu_wait_ms: f64,
    pub cpu_copy_ms: f64,
    pub total_ms: f64,
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod mip_tests;
#[cfg(all(test, not(target_arch = "wasm32")))]
mod reuse_tests;

/// 与 WGSL 对齐的 Uniform 结构
#[repr(C)]
#[derive(Debug, Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
pub struct ResampleUniforms {
    pub src_width: f32,
    pub src_height: f32,
    pub render_offset_x: f32,
    pub render_offset_y: f32,
    pub render_width: f32,
    pub render_height: f32,
    pub target_width: f32,
    pub target_height: f32,
    pub scale: f32,
    pub filter_mode: u32, // 0: mip 预滤 pass, 1: Lanczos3, 2: Anime4K
    pub _pad1: f32,
    pub _pad2: f32,
    /// 缩小路径使用的 mip 等级，由 Rust 侧按 `log2(1/scale)` 算好。
    pub sample_lod: f32,
    /// 取完 mip 级之后剩下的缩放倍率（见 WGSL 那边同名字段的说明）。
    pub residual_scale: f32,
    // 补齐到 64 字节。WGSL 会把 uniform 结构体补到 16 的整数倍，
    // 而 Rust 侧不会 —— 少写两个 f32 就会让后面所有字段错位，
    // 表现出来是「参数明明传了却不生效」（实测：sample_lod 被读成 0，
    // 缩小又退回单点采样，锯齿照旧）。下面那条断言就是为了让这种错位
    // 在编译期就炸，而不是等到画面对不上。
    pub _pad3: f32,
    pub _pad5: f32,
}

const _: () = assert!(std::mem::size_of::<ResampleUniforms>() == 64);

pub struct WgpuResampler {
    pub device: Arc<wgpu::Device>,
    pub queue: Arc<wgpu::Queue>,
    pipeline: wgpu::RenderPipeline,
    /// 只用来生成 mip 链（片元入口 `fs_mip`）。
    mip_pipeline: wgpu::RenderPipeline,
    bind_group_layout: wgpu::BindGroupLayout,
    sampler: wgpu::Sampler,

    // 缓存的目标纹理与读取缓冲（按 target_w x target_h 复用）
    target_cache: Option<CachedTarget>,
    // 源纹理复用已有 mip 容量，只在尺寸变化或需要更深的 mip 时重建。
    source_cache: Option<CachedSource>,
}

struct CachedTarget {
    width: u32,
    height: u32,
    texture: wgpu::Texture,
    staging_buffer: wgpu::Buffer,
    padded_bytes_per_row: u32,
}

/// 设备要申请的纹理单边上限。
///
/// 抽成一处共用，是因为**测试和 App 必须是同一档限制**：早先测试用默认的 8192、
/// 而 App 里申请了适配器上限，结果同一张 9504 px 的页在测试里被拒、在 App 里能开。
/// 这种漂移会让「测过的」和「跑的」变成两件事。
pub fn requested_texture_dimension(adapter_limit: u32) -> u32 {
    // wgpu 的 `Limits::default()` 只给 8192，而漫画扫描件常见 8000–10000 px 宽
    // （手上那本 AVIF 就是 9504）。16384 盖得住任何现实的漫画页，
    // 同时是要超过适配器就会让 `request_device` 失败的边界。
    adapter_limit.min(16384)
}

// 重建核的两个参数（瓣数 `LANCZOS_A`、抽头半径上限 `MAX_LANCZOS_RADIUS`）
// **唯一定义在 `shaders/gpu_lanczos.wgsl`**。Rust 侧只消费它们的后果：
// mip 级取 `floor(log2(1/scale))`，于是残余倍率恒在 [0.5, 1)、核宽恒 ≤ 13×13。
//
// 不在这里再写一份常量：两处各写一遍必然漂移，而漂移的表现是「测过的」和
// 「跑的」不是同一件事 —— 这一轮已经因为同样的原因踩过一次（测试设备用默认的
// 8192 上限、App 申请适配器上限，同一张 9504 的页一边被拒一边能开）。

/// 一个纹理最大能有多少级 mip（完整链）。
fn full_mip_levels(width: u32, height: u32) -> u32 {
    let max_dim = width.max(height).max(1);
    32 - max_dim.leading_zeros()
}

/// 建一条全屏三角形管线。
///
/// `fragment_entry` 区分用途：`fs_main` 是正常重采样，`fs_mip` 是生成 mip 链。
/// 两条管线共用同一套 bind group 布局，所以它们能直接互换 bind group。
fn create_pipeline(
    device: &wgpu::Device,
    layout: &wgpu::PipelineLayout,
    shader: &wgpu::ShaderModule,
    format: wgpu::TextureFormat,
    fragment_entry: &str,
) -> wgpu::RenderPipeline {
    device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some("rossi_resample_pipeline"),
        layout: Some(layout),
        vertex: wgpu::VertexState {
            module: shader,
            entry_point: Some("vs_main"),
            buffers: &[],
            compilation_options: Default::default(),
        },
        fragment: Some(wgpu::FragmentState {
            module: shader,
            entry_point: Some(fragment_entry),
            targets: &[Some(wgpu::ColorTargetState {
                format,
                blend: None,
                write_mask: wgpu::ColorWrites::ALL,
            })],
            compilation_options: Default::default(),
        }),
        primitive: wgpu::PrimitiveState {
            topology: wgpu::PrimitiveTopology::TriangleList,
            strip_index_format: None,
            front_face: wgpu::FrontFace::Ccw,
            cull_mode: None,
            unclipped_depth: false,
            polygon_mode: wgpu::PolygonMode::Fill,
            conservative: false,
        },
        depth_stencil: None,
        multisample: wgpu::MultisampleState::default(),
        multiview: None,
        cache: None,
    })
}

impl WgpuResampler {
    pub fn new(device: Arc<wgpu::Device>, queue: Arc<wgpu::Queue>) -> Result<Self> {
        Self::new_with_format(device, queue, wgpu::TextureFormat::Bgra8Unorm)
    }

    pub fn new_with_format(
        device: Arc<wgpu::Device>,
        queue: Arc<wgpu::Queue>,
        target_format: wgpu::TextureFormat,
    ) -> Result<Self> {
        let shader_src = include_str!("shaders/gpu_lanczos.wgsl");
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("rossi_wgpu_resample_shader"),
            source: wgpu::ShaderSource::Wgsl(shader_src.into()),
        });

        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("rossi_resample_bgl"),
            entries: &[
                // Binding 0: source_texture
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
                // Binding 1: source_sampler
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                    count: None,
                },
                // Binding 2: uniforms
                wgpu::BindGroupLayoutEntry {
                    binding: 2,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
            ],
        });

        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("rossi_resample_layout"),
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });

        let pipeline =
            create_pipeline(&device, &pipeline_layout, &shader, target_format, "fs_main");
        // Mip 生成那一趟与主渲染**共用同一套 bind group 布局**（纹理 / 采样器 / uniform），
        // 只是换一个片元入口 —— 于是它可以直接复用主渲染建好的 bind group，
        // 不需要第二套布局，也不需要第二份 uniform 结构。
        let mip_pipeline = create_pipeline(
            &device,
            &pipeline_layout,
            &shader,
            wgpu::TextureFormat::Rgba8Unorm,
            "fs_mip",
        );

        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("rossi_resample_sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            address_mode_w: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            // mip 生成与 Anime4K 使用线性采样。Lanczos 用 textureLoad 读取
            // 指定的整数 mip，不依赖相邻级之间的插值。
            mipmap_filter: wgpu::FilterMode::Linear,
            ..Default::default()
        });

        Ok(Self {
            device,
            queue,
            pipeline,
            mip_pipeline,
            bind_group_layout,
            sampler,
            target_cache: None,
            source_cache: None,
        })
    }

    /// 获取或创建匹配目标视口尺寸的 Target 纹理和读取 Staging Buffer
    fn get_or_create_target(&mut self, width: u32, height: u32) -> &CachedTarget {
        let need_recreate = match &self.target_cache {
            Some(c) => c.width != width || c.height != height,
            None => true,
        };

        if need_recreate {
            let texture = self.device.create_texture(&wgpu::TextureDescriptor {
                label: Some("rossi_target_texture"),
                size: wgpu::Extent3d {
                    width,
                    height,
                    depth_or_array_layers: 1,
                },
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format: wgpu::TextureFormat::Bgra8Unorm,
                usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
                view_formats: &[],
            });

            let bytes_per_row = width * 4;
            // wgpu copy 要求 bytes_per_row 必须为 256 的整数倍
            let padded_bytes_per_row = (bytes_per_row + 255) & !255;
            let staging_size = (padded_bytes_per_row * height) as wgpu::BufferAddress;

            let staging_buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("rossi_staging_read_buffer"),
                size: staging_size,
                usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                mapped_at_creation: false,
            });

            self.target_cache = Some(CachedTarget {
                width,
                height,
                texture,
                staging_buffer,
                padded_bytes_per_row,
            });
        }

        self.target_cache.as_ref().unwrap()
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    #[test]
    fn letterbox_is_transparent_without_erasing_black_image_pixels() {
        let (device, queue) = init_test_device().expect("回归测试需要 GPU 设备");
        let mut resampler = WgpuResampler::new(device, queue).unwrap();
        let stride = 64;
        // 横图、竖图、等比例图；同时覆盖放大、缩小与 Anime4K。
        for (width, height) in [(4, 2), (2, 4), (16, 8), (8, 16), (8, 8)] {
            for anime4k in [false, true] {
                let rgba = [0, 0, 0, 255].repeat((width * height) as usize);
                let mut out = vec![123u8; stride * 8];
                resampler
                    .resample_to_buffer(
                        &rgba,
                        width,
                        height,
                        8,
                        8,
                        out.as_mut_ptr(),
                        stride,
                        anime4k,
                    )
                    .unwrap();
                for y in 0..8 {
                    for x in 0..8 {
                        let inside = if width > height {
                            (2..6).contains(&y)
                        } else if height > width {
                            (2..6).contains(&x)
                        } else {
                            true
                        };
                        let expected = if inside { [0, 0, 0, 255] } else { [0; 4] };
                        let offset = y * stride + x * 4;
                        assert_eq!(
                            &out[offset..offset + 4],
                            &expected,
                            "{width}x{height}, Anime4K={anime4k}, ({x},{y})"
                        );
                    }
                    assert!(out[y * stride + 32..(y + 1) * stride]
                        .iter()
                        .all(|v| *v == 0));
                }
            }
        }
    }

    pub(super) fn init_test_device() -> Option<(Arc<wgpu::Device>, Arc<wgpu::Queue>)> {
        let instance = wgpu::Instance::default();
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: None,
            force_fallback_adapter: false,
        }))
        .ok()?;
        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("test_resampler_device"),
            required_limits: wgpu::Limits {
                max_texture_dimension_2d: requested_texture_dimension(
                    adapter.limits().max_texture_dimension_2d,
                ),
                ..wgpu::Limits::default()
            },
            ..Default::default()
        }))
        .ok()?;
        Some((Arc::new(device), Arc::new(queue)))
    }

    /// 缩小必须是「面积平均」，不能是「取一个点」。
    ///
    /// 16×16 的单像素棋盘格缩到 3×3（ratio = 0.1875，lod = 2）：
    /// 棋盘格里任何 4×4 块的平均值都是中灰，所以正确重建的结果应当处处约等于 128，
    /// 而且**方差接近 0**。
    ///
    /// 尺寸是特意挑的，不是随手写的：`3` 让采样点落在非整数 texel 位置上。
    /// 早先试过 8×8 → 2×2，那个尺寸**分不出好坏** —— 采样点正好落在 texel 边界，
    /// 双线性在那里恰好把相邻两个反色像素各取一半，也能得到中灰，
    /// 于是「单点采样」和「面积平均」的断言同时通过。挑尺寸这件事本身就是要写进
    /// 注释的，否则下一个人会以为随便选都行。
    #[test]
    fn test_downscale_averages_instead_of_point_sampling() {
        let Some((device, queue)) = init_test_device() else {
            return;
        };

        let src_w = 16u32;
        let src_h = 16u32;
        let mut rgba = vec![0u8; (src_w * src_h * 4) as usize];
        for y in 0..src_h {
            for x in 0..src_w {
                let v: u8 = if (x + y) % 2 == 0 { 255 } else { 0 };
                let i = ((y * src_w + x) * 4) as usize;
                rgba[i] = v;
                rgba[i + 1] = v;
                rgba[i + 2] = v;
                rgba[i + 3] = 255;
            }
        }

        let mut resampler =
            WgpuResampler::new_with_format(device, queue, wgpu::TextureFormat::Bgra8Unorm)
                .expect("初始化 resampler 失败");

        let target_w = 3u32;
        let target_h = 3u32;
        let stride = 256usize;
        let mut out = vec![0u8; stride * target_h as usize];
        resampler
            .resample_to_buffer(
                &rgba,
                src_w,
                src_h,
                target_w,
                target_h,
                out.as_mut_ptr(),
                stride,
                false,
            )
            .expect("渲染失败");

        for y in 0..target_h as usize {
            for x in 0..target_w as usize {
                let b = out[y * stride + x * 4] as i32;
                assert!(
                    (110..=145).contains(&b),
                    "输出像素 ({x},{y}) 应约为中灰 128（面积平均），实测 {b} —— \
                     说明缩小又退回了单点采样，锯齿会跟着回来"
                );
            }
        }
    }
}

#[cfg(test)]
mod sharpness_tests {
    use super::*;

    /// 诊断：**在用户的真实尺寸上**量质量与耗时（9504×6336 → 2940×1608）。
    ///
    /// 小图的结论不能直接外推：核宽、mip 级数、纹理上传量都跟尺寸强相关。
    /// 这个尺寸就是那本 AVIF 的实际数字（scale 0.254，2x DPR 下的物理目标）。
    #[test]
    fn diagnose_real_size_cost() {
        let (device, queue) = super::tests::init_test_device().expect("无 GPU 适配器");
        let (sw, sh) = (9504u32, 6336u32);
        let (tw, th) = (2940u32, 1608u32);
        // 合成源：竖条纹 + 一条台阶边（只看时间与边缘跳变，图案具体形状不重要）
        let mut rgba = vec![0u8; sw as usize * sh as usize * 4];
        for y in 0..sh as usize {
            for x in 0..sw as usize {
                let v: u8 = if x < sw as usize / 2 {
                    (x % 251) as u8
                } else {
                    255 - (x % 251) as u8
                };
                let i = (y * sw as usize + x) * 4;
                rgba[i] = v;
                rgba[i + 1] = v;
                rgba[i + 2] = v;
                rgba[i + 3] = 255;
            }
        }
        // 行跨步是**字节**数：每行 tw 个 BGRA 像素 = tw*4 字节，再按 64 对齐。
        // （这里一开始写成 `tw` 对齐，比实际行宽小 4 倍 —— 正好被 resample_to_buffer
        //  新加的跨步校验拦下，没写进越界。）
        let stride = (tw as usize * 4 + 63) & !63;
        let mut out = vec![0u8; stride * th as usize];
        let mut r =
            WgpuResampler::new_with_format(device, queue, wgpu::TextureFormat::Bgra8Unorm).unwrap();
        r.resample_to_buffer(&rgba, sw, sh, tw, th, out.as_mut_ptr(), stride, false)
            .unwrap();
        // 预热一次（首次含纹理创建），再量两次取小
        let mut best = f64::MAX;
        for _ in 0..2 {
            let t = std::time::Instant::now();
            r.resample_to_buffer(&rgba, sw, sh, tw, th, out.as_mut_ptr(), stride, false)
                .unwrap();
            best = best.min(t.elapsed().as_secs_f64() * 1000.0);
        }
        let y = (th / 2) as usize;
        let row: Vec<i32> = (0..tw as usize)
            .map(|x| out[y * stride + x * 4] as i32)
            .collect();
        let mut max_step = 0;
        for w in row.windows(2) {
            max_step = max_step.max((w[0] - w[1]).abs());
        }
        println!("真实尺寸 9504x6336 → 2940x1608: 渲染 {best:.1} ms，边缘跳变 {max_step}");
    }

    /// 诊断：一张图量两个指标 —— **锐度**与**抗锯齿**必须分开量。
    ///
    /// 用两个图案是有意的，混在一个图案里量不出来：
    /// - 台阶边（边落在两个输出像素之间）→ 边缘最大跳变 = 锐度；
    /// - 周期 4 的细条纹（在 3.16× 之下远高于输出 Nyquist）→ 必须被滤成均匀灰，
    ///   「偏离中灰的均值」就是没滤干净的锯齿/摩尔纹。
    ///
    /// 前者只看滤波器**保住**了多少，后者只看它**滤掉**了多少。一个核只要够窄，
    /// 前者就好看（假锐），只要够宽后者就好看（糊）；两个数一起看才分得出好坏。
    #[test]
    fn diagnose_quality() {
        let (device, queue) = super::tests::init_test_device().expect("无 GPU 适配器");

        // ① 锐度：64×64 台阶边，边在 x=34（落在输出像素之间）→ 20×20
        let (sw, sh) = (64u32, 64u32);
        let mut rgba = vec![0u8; (sw * sh * 4) as usize];
        for y in 0..sh {
            for x in 0..sw {
                let v: u8 = if x < 34 { 0 } else { 255 };
                let i = ((y * sw + x) * 4) as usize;
                rgba[i] = v;
                rgba[i + 1] = v;
                rgba[i + 2] = v;
                rgba[i + 3] = 255;
            }
        }
        let (tw, th) = (20u32, 20u32);
        let stride = 512usize;
        let mut out = vec![0u8; stride * th as usize];
        let mut r = WgpuResampler::new_with_format(
            device.clone(),
            queue.clone(),
            wgpu::TextureFormat::Bgra8Unorm,
        )
        .unwrap();
        r.resample_to_buffer(&rgba, sw, sh, tw, th, out.as_mut_ptr(), stride, false)
            .unwrap();
        let y = (th / 2) as usize;
        let row: Vec<i32> = (0..tw as usize)
            .map(|x| out[y * stride + x * 4] as i32)
            .collect();
        let mut max_step = 0;
        for w in row.windows(2) {
            max_step = max_step.max((w[0] - w[1]).abs());
        }

        // ② 抗锯齿：256×256 周期 4 细条纹 → 81×81（3.16×）→ 应滤成均匀灰
        let (sw2, sh2) = (256u32, 256u32);
        let mut rgba2 = vec![0u8; (sw2 * sh2 * 4) as usize];
        for y in 0..sh2 {
            for x in 0..sw2 {
                let v: u8 = if (x / 2) % 2 == 0 { 0 } else { 255 };
                let i = ((y * sw2 + x) * 4) as usize;
                rgba2[i] = v;
                rgba2[i + 1] = v;
                rgba2[i + 2] = v;
                rgba2[i + 3] = 255;
            }
        }
        let (tw2, th2) = (81u32, 81u32);
        let mut out2 = vec![0u8; stride * th2 as usize];
        let mut r2 =
            WgpuResampler::new_with_format(device, queue, wgpu::TextureFormat::Bgra8Unorm).unwrap();
        r2.resample_to_buffer(&rgba2, sw2, sh2, tw2, th2, out2.as_mut_ptr(), stride, false)
            .unwrap();
        let mut dev = 0f64;
        let mut n = 0f64;
        for y in 8..(th2 as usize - 8) {
            for x in 8..(tw2 as usize - 8) {
                dev += (out2[y * stride + x * 4] as f64 - 128.0).abs();
                n += 1.0;
            }
        }
        println!(
            "锐度(边缘跳变) = {max_step}  |  残留锯齿(偏离中灰) = {:.1}",
            dev / n
        );
    }

    /// 诊断用：把阶梯边放在**两个输出像素之间**，量它跨越了几个「半亮」像素。
    ///
    /// 这一点是这轮的关键教训：早先把边缘放在输出像素中心上，任何滤波器都是
    /// 一跳到底，量不出差别；只有落在像素之间时，滤波器的重建能力才显出来。
    ///
    /// 它是**诊断，不是断言**，这是有意的：实测 mip 级上的 Lanczos3 是 190、
    /// mip 三线性是 178 —— 差 7%，能看出方向，但不够稳定到可以当阈值
    /// （换 GPU / 换驱动就可能翻）。留一条永远不会失败的测试比没有测试更糟，
    /// 所以这里只打印数字，人工比对；能真正守住行为的断言是上面那条棋盘格的
    /// 「面积平均」，它在单点采样下会实实在在地失败。
    #[test]
    fn diagnose_edge_width() {
        let (device, queue) = super::tests::init_test_device().expect("无 GPU 适配器");
        let (sw, sh) = (64u32, 64u32);
        let (tw, th) = (20u32, 20u32);
        for edge in [32u32, 34] {
            let mut rgba = vec![0u8; (sw * sh * 4) as usize];
            for y in 0..sh {
                for x in 0..sw {
                    let v: u8 = if x < edge { 0 } else { 255 };
                    let i = ((y * sw + x) * 4) as usize;
                    rgba[i] = v;
                    rgba[i + 1] = v;
                    rgba[i + 2] = v;
                    rgba[i + 3] = 255;
                }
            }
            let stride = 512usize;
            let mut out = vec![0u8; stride * th as usize];
            let mut r = WgpuResampler::new_with_format(
                device.clone(),
                queue.clone(),
                wgpu::TextureFormat::Bgra8Unorm,
            )
            .unwrap();
            r.resample_to_buffer(&rgba, sw, sh, tw, th, out.as_mut_ptr(), stride, false)
                .unwrap();
            let y = (th / 2) as usize;
            let row: Vec<i32> = (0..tw as usize)
                .map(|x| out[y * stride + x * 4] as i32)
                .collect();
            let partial = row.iter().filter(|v| (20..=235).contains(*v)).count();
            let mut max_step = 0;
            for w in row.windows(2) {
                max_step = max_step.max((w[0] - w[1]).abs());
            }
            println!("边缘 x={edge}: 半亮像素 {partial} 个, 最大跳变 {max_step}");
        }
    }
}
