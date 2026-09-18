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
    filter_mode: u32, // 1: Lanczos3（在 sample_lod 那一级上）, 2: Anime4K
    _pad1: f32,
    _pad2: f32,
    /// 重建所用的 mip 等级，由 Rust 侧按 `log2(1/scale)` 算好。
    ///
    /// `src_width`/`src_height` 传的也是**这一级**的尺寸 —— 采样几何必须与
    /// 实际读取的那一级一致，否则整幅画会错位放大。
    /// mip 生成那一趟（`fs_mip`）也会读到本结构体，但它只用 `src_width`/`src_height`。
    sample_lod: f32,
    _pad3: f32,
    _pad4: f32,
    _pad5: f32,
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
fn fs_main(@builtin(position) frag_pos: vec4<f32>) -> @location(0) vec4<f32> {    let px = frag_pos.x;
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

    // Lanczos3 高质量 Sinc 滤波重采样。
    //
    // # 为什么是在 mip 级上做，而不是分两条路
    //
    // 缩小时要同时满足两件事：**不欠采样**（否则锯齿）与**不糊**（否则细节没了）。
    //   - 只在第 0 级上取一个点/两点 → 欠采样，锯齿；
    //   - 只靠 mip 三线性（面积平均）→ 不锯齿，但明显比别的软件糊，
    //     因为面积平均没有重建核，高频被一并抹平。
    //
    // 所以分两步走：先用 mip 链把倍率降到 [0.5, 1)（这一步就是正确的面积平均，
    // 由 Rust 侧算出的 `sample_lod` 指定用哪一级），**再在同一级上跑 Lanczos3**。
    // 后者是有负瓣的重建核，能把这已经落在采样定理内的频段重新锐回来 ——
    // 于是既不锯齿也不糊。
    //
    // 注意 LOD 取的是 `floor(log2(1/scale))`，所以残余倍率始终落在 [0.5, 1)，
    // 对应的足迹不超过 2 个像素，正好在下面 5×5 核的覆盖范围内。
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

            let color = textureLoad(
                source_texture,
                vec2<i32>(sample_x, sample_y),
                i32(uniforms.sample_lod),
            );
            accumulated_color = accumulated_color + color * w;
            total_weight = total_weight + w;
        }
    }

    if total_weight > 0.0001 {
        return clamp(accumulated_color / total_weight, vec4<f32>(0.0), vec4<f32>(1.0));
    }

    return textureSampleLevel(source_texture, source_sampler, uv, 0.0);
}

/// Mip 生成用的片元入口：对上一级做 2×2 盒式降采样。
///
/// # 为什么单独一个入口，而且用盒式
///
/// mip 链的职责只有一个：**把采样率降到与输出匹配的档位**。真正的画质重建在最后
/// 一级由 Lanczos 完成。中间这一步用盒式（等权 2×2）的原因是它最稳 ——
/// 带负瓣的重建核在逐级降采样时会累积振铃（暗边/亮边），而 mip 链是逐级叠上去的，
/// 误差会一路放大。
///
/// 采样点取的是 2×2 四个象限的中心（±0.5 texel），配上 `mipmap_filter = Linear`
/// 的采样器，等效于在新一级的每个像素上做一次正确的面积平均。
@fragment
fn fs_mip(@location(0) uv: vec2<f32>) -> @location(0) vec4<f32> {
    let half_texel = 0.5 / vec2<f32>(uniforms.src_width, uniforms.src_height);
    let a = textureSampleLevel(source_texture, source_sampler, uv + vec2<f32>(-half_texel.x, -half_texel.y), 0.0);
    let b = textureSampleLevel(source_texture, source_sampler, uv + vec2<f32>(half_texel.x, -half_texel.y), 0.0);
    let c = textureSampleLevel(source_texture, source_sampler, uv + vec2<f32>(-half_texel.x, half_texel.y), 0.0);
    let d = textureSampleLevel(source_texture, source_sampler, uv + vec2<f32>(half_texel.x, half_texel.y), 0.0);
    return (a + b + c + d) * 0.25;
}
