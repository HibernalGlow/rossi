struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

struct ResampleUniforms {
    src_width: f32,
    src_height: f32,
    render_offset_x: f32,
    render_offset_y: f32,
    render_width: f32,
    render_height: f32,
    target_width: f32,
    target_height: f32,
    scale: f32,
    filter_mode: u32,      // 0: Bilinear, 1: Lanczos3, 2: Anime4k Sharp
    hdr_mode: u32,         // 0: Off, 1: Extended Linear, 2: SDR Boost
    hdr_boost: f32,        // 白点与高光扩展倍率
    hdr_peak: f32,         // 显示器可用峰值倍率
    output_encoding: u32,  // 0: sRGB 编码的 8 位目标, 1: 线性浮点目标 (RGBA16F / EDR)
    _pad1: f32,
    _pad2: f32,
};

@group(0) @binding(0)
var source_texture: texture_2d<f32>;

@group(0) @binding(1)
var source_sampler: sampler;

@group(0) @binding(2)
var<uniform> uniforms: ResampleUniforms;

const PI: f32 = 3.14159265358979323846;
const LANCZOS_SUPPORT: f32 = 3.0;

// Rec. 709 亮度系数（对应 sRGB 原色系，与 libplacebo / ITU-R BT.709 一致）
const LUMA_REC709: vec3<f32> = vec3<f32>(0.2126, 0.7152, 0.0722);

// 深黑留白背景色 0xFF05050A。
// sRGB 编码值（8 位目标直通）
const BG_COLOR_SRGB: vec4<f32> = vec4<f32>(5.0 / 255.0, 5.0 / 255.0, 10.0 / 255.0, 1.0);
// 同一颜色的线性值（浮点线性目标用：0.0196 sRGB ≈ 0.0015 线性）
const BG_COLOR_LINEAR: vec4<f32> = vec4<f32>(0.0015, 0.0015, 0.0030, 1.0);

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
    var out: VertexOutput;
    // 3 个顶点构建覆盖屏幕的完整三角形
    let pos = vec2<f32>(
        f32((vertex_index << 1u) & 2u),
        f32(vertex_index & 2u)
    );
    out.position = vec4<f32>(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = vec2<f32>(pos.x, 1.0 - pos.y);
    return out;
}

fn sinc(x: f32) -> f32 {
    if abs(x) < 1.0e-5 {
        return 1.0;
    }
    let pix = PI * x;
    return sin(pix) / pix;
}

fn lanczos3(x: f32) -> f32 {
    let ax = abs(x);
    if ax >= LANCZOS_SUPPORT {
        return 0.0;
    }
    return sinc(ax) * sinc(ax / LANCZOS_SUPPORT);
}

// ───────────────────── 色彩空间转换与 Inverse Tone Mapping ─────────────────────

fn srgb_to_linear(c: f32) -> f32 {
    if c <= 0.04045 {
        return c / 12.92;
    }
    return pow((c + 0.055) / 1.055, 2.4);
}

fn srgb_to_linear_rgb(c: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(
        srgb_to_linear(c.r),
        srgb_to_linear(c.g),
        srgb_to_linear(c.b),
    );
}

fn linear_to_srgb(c: f32) -> f32 {
    if c <= 0.0031308 {
        return c * 12.92;
    }
    return 1.055 * pow(max(c, 0.0), 1.0 / 2.4) - 0.055;
}

fn linear_to_srgb_rgb(c: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(
        linear_to_srgb(c.r),
        linear_to_srgb(c.g),
        linear_to_srgb(c.b),
    );
}

/// 亮度逆色调映射曲线（Inverse Tone Mapping）
///
/// 参考 libplacebo / mpv 的做法：
/// 1. 暗部 (Y ≈ 0) 与中间调 (Y ≈ 0.18) 基本不动 —— 黑线墨迹绝不发灰；
/// 2. 白点与高光 (Y -> 1.0) 平滑扩展到目标倍率；
/// 3. Y_exp = Y + (boost - 1) * Y^2.5，指数 2.5 让扩展量集中在高光段。
fn expand_luminance(y: f32, boost: f32) -> f32 {
    let headroom = max(boost - 1.0, 0.0);
    if headroom <= 0.0 {
        return y;
    }
    let weight = pow(clamp(y, 0.0, 1.0), 2.5);
    return y + headroom * weight;
}

/// 软肩压缩（Soft-knee Rolloff）
///
/// 接近或超过目标峰值时用指数渐近收敛，避免硬截断造成的高光死白。
fn soft_shoulder(y: f32, peak: f32) -> f32 {
    let limit = max(peak, 1.0);
    let knee = limit * 0.75;
    if y <= knee {
        return y;
    }
    let over = (y - knee) / max(limit - knee, 1e-4);
    return knee + (limit - knee) * (1.0 - exp(-over));
}

/// 按亮度比率缩放色度：严格保持 R:G:B 相对比例，
/// 从根本上杜绝独立通道 boost 造成的色相漂移与过饱和。
fn scale_by_luma(rgb_lin: vec3<f32>, luma_in: f32, luma_out: f32) -> vec3<f32> {
    if luma_in <= 1e-6 {
        return rgb_lin;
    }
    return rgb_lin * (luma_out / luma_in);
}

/// 极高光自然去饱和（Bezold-Brücke 效应）：
/// 极亮高光接近峰值时逐步收敛到白色，避免出现荧光假彩。
fn highlight_desaturate(rgb: vec3<f32>, luma_out: f32, peak: f32) -> vec3<f32> {
    let limit = max(peak, 1.0);
    let threshold = limit * 0.85;
    if luma_out <= threshold {
        return rgb;
    }
    let t = clamp((luma_out - threshold) / max(limit - threshold, 1e-4), 0.0, 1.0);
    let desat = t * t * 0.45; // 最高 45% 适度去饱和
    return mix(rgb, vec3<f32>(luma_out), desat);
}

/// 后处理入口。
///
/// `output_encoding` 决定最后一步怎么落地：
/// - `0`：目标是 8 位 SDR 纹理（Bgra8Unorm）。数值必须压回 [0,1] 并按 sRGB 编码，
///        此时无论怎么调都只可能得到「SDR 增强」，不可能超出 SDR 白点。
/// - `1`：目标是扩展线性浮点纹理（Rgba16Float）。直接输出**线性**值且不做上限钳制，
///        1.0 对应 SDR 参考白，> 1.0 的部分由 macOS EDR 交给显示器头顶空间。
///        这才是真 HDR。
fn apply_hdr_postprocess(color_srgb: vec4<f32>) -> vec4<f32> {
    let alpha = color_srgb.a;
    let linear_target = uniforms.output_encoding == 1u;

    // 模式 0：不做色调映射。
    // 8 位目标直接直通（源纹理本来就是 sRGB 编码的）；
    // 浮点线性目标必须先把 sRGB 解开成线性，否则整幅画面会偏暗。
    if uniforms.hdr_mode == 0u {
        if linear_target {
            return vec4<f32>(srgb_to_linear_rgb(color_srgb.rgb), alpha);
        }
        return color_srgb;
    }

    let rgb_lin = srgb_to_linear_rgb(color_srgb.rgb);
    let luma_in = dot(rgb_lin, LUMA_REC709);

    let boost = max(uniforms.hdr_boost, 1.0);
    let peak = max(uniforms.hdr_peak, 1.0);

    // 模式 1 允许把白点推到 peak（真 HDR）；模式 2 收在 SDR 白点内（增强）。
    let limit = select(1.0, peak, uniforms.hdr_mode == 1u);

    let luma_out = soft_shoulder(expand_luminance(luma_in, boost), limit);
    let rgb_boosted = scale_by_luma(rgb_lin, luma_in, luma_out);
    let rgb_final = highlight_desaturate(rgb_boosted, luma_out, limit);

    if linear_target {
        // 真 HDR 落地：线性、不钳上限
        return vec4<f32>(max(rgb_final, vec3<f32>(0.0)), alpha);
    }
    return vec4<f32>(clamp(linear_to_srgb_rgb(rgb_final), vec3<f32>(0.0), vec3<f32>(1.0)), alpha);
}

@fragment
fn fs_main(@builtin(position) frag_pos: vec4<f32>) -> @location(0) vec4<f32> {
    let px = frag_pos.x;
    let py = frag_pos.y;

    let min_x = uniforms.render_offset_x;
    let max_x = uniforms.render_offset_x + uniforms.render_width;
    let min_y = uniforms.render_offset_y;
    let max_y = uniforms.render_offset_y + uniforms.render_height;

    // 视口 Letterbox 留白检查：留白色必须与目标的编码方式一致
    if px < min_x || px >= max_x || py < min_y || py >= max_y {
        if uniforms.output_encoding == 1u {
            return BG_COLOR_LINEAR;
        }
        return BG_COLOR_SRGB;
    }

    // 计算源图像纹理对应 UV 坐标 (0.0 ~ 1.0)
    let local_x = (px - min_x) / uniforms.render_width;
    let local_y = (py - min_y) / uniforms.render_height;
    let uv = vec2<f32>(clamp(local_x, 0.0, 1.0), clamp(local_y, 0.0, 1.0));

    var sampled_color: vec4<f32>;

    // 模式 0：快速双线性重采样（大比例缩小下采样，过渡自然抗锯齿）
    if uniforms.filter_mode == 0u {
        sampled_color = textureSampleLevel(source_texture, source_sampler, uv, 0.0);
    } else if uniforms.filter_mode == 2u {
        // 模式 2：动漫/二次元线条边缘增强 (Anime4K 简化轻量核)
        let center_color = textureSampleLevel(source_texture, source_sampler, uv, 0.0);
        let tex_el = vec2<f32>(1.0 / uniforms.src_width, 1.0 / uniforms.src_height);

        // 采样 4 邻域做拉普拉斯边缘检测与自适应锐化
        let north = textureSampleLevel(source_texture, source_sampler, uv + vec2<f32>(0.0, -tex_el.y), 0.0);
        let south = textureSampleLevel(source_texture, source_sampler, uv + vec2<f32>(0.0, tex_el.y), 0.0);
        let west  = textureSampleLevel(source_texture, source_sampler, uv + vec2<f32>(-tex_el.x, 0.0), 0.0);
        let east  = textureSampleLevel(source_texture, source_sampler, uv + vec2<f32>(tex_el.x, 0.0), 0.0);

        let laplacian = (north + south + west + east) * 0.25;
        let diff = center_color - laplacian;
        let sharpened = center_color + diff * 0.45;
        sampled_color = clamp(sharpened, vec4<f32>(0.0), vec4<f32>(1.0));
    } else {
        // 模式 1：Lanczos3 高质量 Sinc 滤波重采样
        let src_x = uv.x * uniforms.src_width - 0.5;
        let src_y = uv.y * uniforms.src_height - 0.5;

        let base_x = i32(floor(src_x));
        let base_y = i32(floor(src_y));

        var total_weight: f32 = 0.0;
        var accumulated_color: vec4<f32> = vec4<f32>(0.0);

        let max_w = i32(uniforms.src_width) - 1;
        let max_h = i32(uniforms.src_height) - 1;

        // 5x5 邻域卷积（逼近 3-tap Lanczos，兼顾极致画质与单 Pass 极速吞吐）
        for (var dy: i32 = -2; dy <= 2; dy = dy + 1) {
            let sample_y = clamp(base_y + dy, 0, max_h);
            let wy = lanczos3(f32(dy) - (src_y - f32(base_y)));

            for (var dx: i32 = -2; dx <= 2; dx = dx + 1) {
                let sample_x = clamp(base_x + dx, 0, max_w);
                let wx = lanczos3(f32(dx) - (src_x - f32(base_x)));
                let w = wx * wy;

                let color = textureLoad(source_texture, vec2<i32>(sample_x, sample_y), 0);
                accumulated_color = accumulated_color + color * w;
                total_weight = total_weight + w;
            }
        }

        if total_weight > 0.0001 {
            sampled_color = clamp(accumulated_color / total_weight, vec4<f32>(0.0), vec4<f32>(1.0));
        } else {
            sampled_color = textureSampleLevel(source_texture, source_sampler, uv, 0.0);
        }
    }

    return apply_hdr_postprocess(sampled_color);
}
