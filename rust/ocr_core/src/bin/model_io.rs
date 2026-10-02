//! 打印 ONNX 会话的输入/输出**名字与形状**——用来回答两个「能不能省」的前置问题：
//!
//! 1. **batch 维是不是动态**：如果 encoder 的 `pixel_values` 第 0 维写死成 1，
//!    「把一页 28 个框攒成一次 encoder 前向」这条路就得先重导出，不是代码能改的；
//! 2. **decoder 有没有 `past_key_values`**：没有的话，自回归解码每步都在重算整段前缀，
//!    所谓「加 KV cache」在这份导出上根本无从下手 —— 同样要先重导出。
//!
//! 这两条都是**看一眼就知道**的事实，之前却一直是靠记忆和文档转述在讨论。
//!
//! 用法：`model_io <a.onnx> [b.onnx …]`

use anyhow::Result;
use ort::session::Session;
use std::path::PathBuf;

fn main() -> Result<()> {
    for arg in std::env::args().skip(1) {
        let path = PathBuf::from(&arg);
        println!(
            "\n=== {} ===",
            path.file_name().unwrap_or_default().to_string_lossy()
        );
        let session = Session::builder()?.commit_from_file(&path)?;
        println!("输入 {} 个：", session.inputs().len());
        for inp in session.inputs() {
            println!("  {:<26} {:?}", inp.name(), inp.dtype());
        }
        println!("输出 {} 个：", session.outputs().len());
        for out in session.outputs() {
            println!("  {:<26} {:?}", out.name(), out.dtype());
        }
        let has_cache = session
            .inputs()
            .iter()
            .any(|i| i.name().contains("past") || i.name().contains("cache"));
        let note = if has_cache {
            ""
        } else {
            "（→ 用不了缓存，除非重导出）"
        };
        println!("→ 带 past/cache 输入：{has_cache}{note}");
    }
    Ok(())
}
