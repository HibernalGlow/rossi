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
    /// 取完 mip 级之后**剩下的**缩放倍率（`scale * 2^lod`，落在 [0.5, 1)）。
    ///
    /// 它决定重建核该有多宽。这是这条路上最容易写错的一个数：
    /// 核宽必须按**残余**倍率算，不能按原始倍率算 —— 原始倍率那一大截已经由
    /// mip 链做掉了，再按它加宽就等于对同一段频谱滤两遍。
    residual_scale: f32,
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

/// 变宽 Lanczos 的抽头上限（半径，源像素）。
///
/// 由于 mip 链把残余倍率钉在 [0.5, 1)，理论上半径不会超过 `ceil(3/0.5) = 6`；
/// 这个上限只是防御性的（比如调用方给了个异常的 residual_scale），
/// 同时把最坏情况的开销写明白：半径 6 → 13×13 = 169 抽/像素。
const MAX_LANCZOS_RADIUS: i32 = 8;

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

fn lanczos_n(x: f32, a: f32) -> f32 {
    let ax = abs(x);
    if ax >= a {
        return 0.0;
    }
    return sinc(ax) * sinc(ax / a);
}

/// 重建核的瓣数。3 = 经典 Lanczos3（锐、略有振铃），2 = Lanczos2（更窄、更少振铃，
/// 但滚降更缓 → 抗锯齿弱一点）。这个数是「锐度 ↔ 干净」那个旋钮。
const LANCZOS_A: f32 = 3.0;

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
    // LOD 取的是 `floor(log2(1/scale))`，所以残余倍率始终落在 [0.5, 1)，
    // 无论原始缩小多少倍。这一点很关键：它把**核宽和成本一起钉死了** ——
    // 核最宽就是 `ceil(3 / 0.5) = 6`，即 13×13。
    //
    // 而核宽必须跟着残余倍率走，不能定死：正确的重采样核在源像素上的支撑是
    // `3 / 倍率`。用固定的 ±2 抽头在残余倍率 0.508 时只有 ±2（该有 ±5.9），
    // 那是**欠采样** —— 表现不是糊，是「假锐」：边缘看着硬，但同时起锯齿与摩尔纹。
    // 这也解释了为什么「定死核宽」的两个极端（太窄=锯齿、只做面积平均=糊）
    // 都不对：真正缺的是让核宽等于它该有的值。
    let r = clamp(uniforms.residual_scale, 0.05, 1.0);
    let radius = i32(min(ceil(LANCZOS_A / r), f32(MAX_LANCZOS_RADIUS)));

    let src_x = uv.x * uniforms.src_width - 0.5;
    let src_y = uv.y * uniforms.src_height - 0.5;

    let base_x = i32(floor(src_x));
    let base_y = i32(floor(src_y));

    var total_weight: f32 = 0.0;
    var accumulated_color: vec4<f32> = vec4<f32>(0.0);

    let max_w = i32(uniforms.src_width) - 1;
    let max_h = i32(uniforms.src_height) - 1;

    // 变宽 Lanczos3：`lanczos3(d * r)`，r = 1 时就是经典 Lanczos3（支撑 ±3），
    // 缩小（r < 1）时支撑展宽到 ±3/r。权重的常数因子 r 在归一化时约掉。
    for (var dy: i32 = -radius; dy <= radius; dy = dy + 1) {
        let sample_y = clamp(base_y + dy, 0, max_h);
        let wy = lanczos_n((f32(dy) - (src_y - f32(base_y))) * r, LANCZOS_A);

        for (var dx: i32 = -radius; dx <= radius; dx = dx + 1) {
            let sample_x = clamp(base_x + dx, 0, max_w);
            let wx = lanczos_n((f32(dx) - (src_x - f32(base_x))) * r, LANCZOS_A);
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
