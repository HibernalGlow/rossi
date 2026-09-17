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
    filter_mode: u32, // 0: Bilinear, 1: Lanczos3, 2: Anime4k Sharp
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

// 深黑留白背景色: 0xFF05050A (BGRA: B=0x0A, G=0x05, R=0x05, A=0xFF)
const BG_COLOR: vec4<f32> = vec4<f32>(5.0 / 255.0, 5.0 / 255.0, 10.0 / 255.0, 1.0);

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

@fragment
fn fs_main(@builtin(position) frag_pos: vec4<f32>) -> @location(0) vec4<f32> {
    let px = frag_pos.x;
    let py = frag_pos.y;

    let min_x = uniforms.render_offset_x;
    let max_x = uniforms.render_offset_x + uniforms.render_width;
    let min_y = uniforms.render_offset_y;
    let max_y = uniforms.render_offset_y + uniforms.render_height;

    // 视口 Letterbox 留白检查
    if px < min_x || px >= max_x || py < min_y || py >= max_y {
        return BG_COLOR;
    }

    // 计算源图像纹理对应 UV 坐标 (0.0 ~ 1.0)
    let local_x = (px - min_x) / uniforms.render_width;
    let local_y = (py - min_y) / uniforms.render_height;
    let uv = vec2<f32>(clamp(local_x, 0.0, 1.0), clamp(local_y, 0.0, 1.0));

    // 模式 0：快速双线性重采样（大比例缩小下采样，过渡自然抗锯齿）
    if uniforms.filter_mode == 0u {
        return textureSampleLevel(source_texture, source_sampler, uv, 0.0);
    }

    // 模式 2：动漫/二次元线条边缘增强 (Anime4K 简化轻量核)
    if uniforms.filter_mode == 2u {
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
        return clamp(sharpened, vec4<f32>(0.0), vec4<f32>(1.0));
    }

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
        return clamp(accumulated_color / total_weight, vec4<f32>(0.0), vec4<f32>(1.0));
    }

    return textureSampleLevel(source_texture, source_sampler, uv, 0.0);
}
