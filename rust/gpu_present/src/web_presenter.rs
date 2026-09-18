//! Rossi WebGPU 呈现器（Flutter Web / Wasm）。
//!
//! 在浏览器环境中，直接把解码出的 RGBA 图像通过 WebGPU (wgpu) 渲染到指定的 HTML `<canvas>`。
//! 复用统一的 WGSL 着色器（Lanczos3 / Anime4K 边缘锐化 / Letterbox 居中留白），
//! 实现零拷贝、纯硬件加速的 Web 端漫画页面呈现。

use crate::wgpu_resampler::WgpuResampler;
use std::sync::Arc;
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub struct RossiWebPresenter {
    device: Arc<wgpu::Device>,
    #[allow(dead_code)]
    queue: Arc<wgpu::Queue>,
    surface: wgpu::Surface<'static>,
    surface_config: wgpu::SurfaceConfiguration,
    resampler: WgpuResampler,
    canvas: web_sys::HtmlCanvasElement,
}

#[wasm_bindgen]
pub async fn create_web_presenter(
    canvas_id: String,
    width: u32,
    height: u32,
) -> Result<RossiWebPresenter, JsValue> {
    RossiWebPresenter::init(canvas_id, width, height).await
}

#[wasm_bindgen]
impl RossiWebPresenter {
    /// 异步创建 Web 呈现器并绑定到页面指定的 `<canvas>`
    pub async fn init(
        canvas_id: String,
        width: u32,
        height: u32,
    ) -> Result<RossiWebPresenter, JsValue> {
        let window = web_sys::window().ok_or_else(|| JsValue::from_str("无法获取 window 对象"))?;
        let document = window
            .document()
            .ok_or_else(|| JsValue::from_str("无法获取 document 对象"))?;
        let element = document.get_element_by_id(&canvas_id).ok_or_else(|| {
            JsValue::from_str(&format!("未找到 id 为 {canvas_id} 的 canvas 元素"))
        })?;
        let canvas: web_sys::HtmlCanvasElement = element
            .dyn_into()
            .map_err(|_| JsValue::from_str("指定的元素不是 HtmlCanvasElement"))?;

        canvas.set_width(width);
        canvas.set_height(height);

        let instance = wgpu::Instance::default();
        let surface = instance
            .create_surface(wgpu::SurfaceTarget::Canvas(canvas.clone()))
            .map_err(|e| JsValue::from_str(&format!("创建 WebGPU Surface 失败: {e}")))?;

        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::HighPerformance,
                force_fallback_adapter: false,
                compatible_surface: Some(&surface),
            })
            .await
            .map_err(|e| JsValue::from_str(&format!("无法请求 WebGPU 适配器: {e}")))?;

        let (device, queue) = adapter
            .request_device(&wgpu::DeviceDescriptor {
                label: Some("rossi_webgpu_device"),
                required_features: wgpu::Features::empty(),
                required_limits: wgpu::Limits::downlevel_webgl2_defaults(),
                memory_hints: Default::default(),
                ..Default::default()
            })
            .await
            .map_err(|e| JsValue::from_str(&format!("无法创建 WebGPU 设备: {e}")))?;

        let device = Arc::new(device);
        let queue = Arc::new(queue);

        let surface_caps = surface.get_capabilities(&adapter);
        let format = surface_caps
            .formats
            .iter()
            .copied()
            .find(|f| f.is_srgb())
            .unwrap_or(surface_caps.formats[0]);

        let surface_config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format,
            width,
            height,
            present_mode: wgpu::PresentMode::AutoVsync,
            alpha_mode: surface_caps.alpha_modes[0],
            view_formats: vec![],
            desired_maximum_frame_latency: 2,
        };
        surface.configure(&device, &surface_config);

        let resampler =
            WgpuResampler::new_with_format(Arc::clone(&device), Arc::clone(&queue), format)
                .map_err(|e| JsValue::from_str(&format!("创建 WgpuResampler 失败: {e}")))?;

        Ok(RossiWebPresenter {
            device,
            queue,
            surface,
            surface_config,
            resampler,
            canvas,
        })
    }

    /// 呈现一页 RGBA 图像到 `<canvas>`
    pub fn render_page(
        &mut self,
        rgba_bytes: &[u8],
        src_width: u32,
        src_height: u32,
        force_anime4k: bool,
    ) -> Result<(), JsValue> {
        let frame = self
            .surface
            .get_current_texture()
            .map_err(|e| JsValue::from_str(&format!("获取 Surface 纹理失败: {e}")))?;
        let view = frame
            .texture
            .create_view(&wgpu::TextureViewDescriptor::default());

        self.resampler
            .render_to_view(
                rgba_bytes,
                src_width,
                src_height,
                &view,
                self.surface_config.width,
                self.surface_config.height,
                force_anime4k,
            )
            .map_err(|e| JsValue::from_str(&format!("GPU 渲染失败: {e}")))?;

        frame.present();
        Ok(())
    }

    /// 当视口或窗口尺寸变化时调整 Surface 尺寸
    pub fn resize(&mut self, width: u32, height: u32) {
        if width == 0 || height == 0 {
            return;
        }
        self.canvas.set_width(width);
        self.canvas.set_height(height);
        self.surface_config.width = width;
        self.surface_config.height = height;
        self.surface.configure(&self.device, &self.surface_config);
    }
}
