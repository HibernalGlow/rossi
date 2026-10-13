//! 动图容器嗅探：不像素解码，只看容器结构。
//!
//! 构建时直接编译 mImageViewer 的流式扫描函数：
//! `canonical_image_loader.rs::probe_static_animation` /
//! `apng_has_multiple_frames` / `webp_has_animation` / `gif_has_multiple_frames`。
//! 本地只用 Cursor 将字节接口适配为 Read。
//!
//! # 为什么这条判定必须存在
//!
//! 「一页 = 一段循环画面」与「一页 = 一张静态图」在两条显示路径上是两回事：
//! 引擎（Skia）的解码器出多帧，而 `image` crate 的 `load_from_memory` 只出**第一帧**。
//! 于是任何一处「先解成位图、再重编码」的步骤都会把动图**悄悄拍平成静帧**——
//! 用户看到的是一张不会动的图，而且没有任何报错。禁漫反混淆就是这一处，
//! 所以它在下重编码之前必须先问一次，而问的方式只能是查容器。
//! （按区域裁剪 `crop_image_by_regions` 同样只出第一帧，但那是用户**点名**要的
//! 几何操作，动图在那里本来就没有「保留所有帧」这个选项，所以不拦。）
//!
//! # 为什么只看头部
//!
//! `acTL` 在 `IDAT` 之前、`ANIM`/`ANMF` 在帧数据之前，两者都在文件头几 KB 内。
//! 于是「是不是动图」可以在**不 inflate 整条**、不像素解码的前提下回答。
//! 头部读到的字节不够时一律答「不是动图」：宁可漏判一条动图（回到今天的行为：
//! 画第一帧），也不能把一本 500 页的静图 PNG 误判成动图换掉整条渲染路径。
//!
//! # GIF 与 `.wbp` 为什么不在这里
//!
//! GIF 的第二帧在第 0 帧的 LZW 数据**之后**，头部无法判定，必须整串扫。
//! 而「后缀本身就意味着动图」这条规则住在 Dart（`lib/reader/page_animation.dart` 的
//! `animatedNameSuffixes` = `gif` / `apng` / `wbp`），Rust 这一侧只回答
//! 「后缀答不出的那两档（webp / png）容器里到底有没有第二帧」——
//! 一条规则只有一个家，所以这里不再抄一张后缀表。

/// 只看容器结构判断「这是一段动图」。
///
/// 传入的字节数不必是完整文件：读个几 KB 就够（Dart 侧的口径是
/// `page_animation.dart` 的 `sniffHeadBytes = 4096`），不足时返回 `false`。
pub fn animated_container(bytes: &[u8]) -> bool {
    apng_has_multiple_frames(&mut Cursor::new(bytes))
        || webp_has_animation(&mut Cursor::new(bytes))
        || webp_head_has_animation_flag(bytes)
}

// Dart 只送头部 4096 字节；大 ICCP 块可能把 ANIM 推到这个窗口之外。
// 上游扫描实际 ANIM/ANMF，本地保留 VP8X 标志作为头部接口适配。
fn webp_head_has_animation_flag(bytes: &[u8]) -> bool {
    bytes.len() >= 21
        && &bytes[..4] == b"RIFF"
        && &bytes[8..12] == b"WEBP"
        && &bytes[12..16] == b"VP8X"
        && bytes[20] & 0x02 != 0
}

use std::io::{Cursor, Read};
include!(concat!(env!("OUT_DIR"), "/animation_probe.rs"));

/// 静图解码的 EXIF 闸门，与上游 canonical loader 的 first-frame 行为一致。
pub fn is_animated_image(bytes: &[u8]) -> bool {
    animated_container(bytes) || gif_has_multiple_frames(&mut Cursor::new(bytes))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn chunk(fourcc: &[u8; 4], payload: &[u8]) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(fourcc);
        out.extend_from_slice(&(payload.len() as u32).to_le_bytes());
        out.extend_from_slice(payload);
        if payload.len() & 1 != 0 {
            out.push(0);
        }
        out
    }

    /// PNG 块**没有** RIFF 那种奇数补齐字节，所以这里不能复用 `chunk`。
    fn png(chunks: &[(&[u8; 4], &[u8])]) -> Vec<u8> {
        let mut out = b"\x89PNG\r\n\x1a\n".to_vec();
        for &(fourcc, payload) in chunks {
            out.extend_from_slice(&(payload.len() as u32).to_be_bytes());
            out.extend_from_slice(fourcc);
            out.extend_from_slice(payload);
            out.extend_from_slice(&[0; 4]); // CRC 占位，嗅探不读它
        }
        out
    }

    fn webp(chunks: &[(&[u8; 4], &[u8])]) -> Vec<u8> {
        let mut body = Vec::new();
        for (fourcc, payload) in chunks {
            body.extend_from_slice(&chunk(fourcc, payload));
        }
        let mut out = b"RIFF".to_vec();
        out.extend_from_slice(&((4 + body.len()) as u32).to_le_bytes());
        out.extend_from_slice(b"WEBP");
        out.extend_from_slice(&body);
        out
    }

    #[test]
    fn apng_is_detected_by_frame_count_not_by_chunk_presence() {
        let three_frames = png(&[
            (b"IHDR", &[0; 13]),
            (b"acTL", &[0, 0, 0, 3, 0, 0, 0, 0]),
            (b"IDAT", &[1, 2, 3]),
        ]);
        assert!(animated_container(&three_frames));

        // 单帧 acTL 与静图无异，必须答 false。
        let one_frame = png(&[
            (b"IHDR", &[0; 13]),
            (b"acTL", &[0, 0, 0, 1, 0, 0, 0, 0]),
            (b"IDAT", &[1, 2, 3]),
        ]);
        assert!(!animated_container(&one_frame));

        let still = png(&[(b"IHDR", &[0; 13]), (b"IDAT", &[1, 2, 3])]);
        assert!(!animated_container(&still));

        // acTL 在 IDAT 之后不是合法排布，头部扫到 IDAT 就该收手。
        let misplaced = png(&[
            (b"IHDR", &[0; 13]),
            (b"IDAT", &[1, 2, 3]),
            (b"acTL", &[0, 0, 0, 9, 0, 0, 0, 0]),
        ]);
        assert!(!animated_container(&misplaced));

        // 块之间的杂项（gAMA / pHYs）要被跳过而不是被误判。
        let with_misc = png(&[
            (b"IHDR", &[0; 13]),
            (b"gAMA", &[0, 0, 123, 45]),
            (b"pHYs", &[0; 9]),
            (b"acTL", &[0, 0, 0, 2, 0, 0, 0, 1]),
        ]);
        assert!(animated_container(&with_misc));
    }

    #[test]
    fn animated_webp_is_detected_from_vp8x_flag_and_from_anim_chunk() {
        // 真机排布：VP8X 必须是第一个块，ANIM 在它之后 —— 所以「偏移 12 == ANIM」
        // 这种判定永远不成立（仓库里原有那份即是如此）。
        let with_anim = webp(&[
            (b"VP8X", &[0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
            (b"ANIM", &[0, 0, 0, 0, 0, 0]),
            (b"ANMF", &[0; 16]),
        ]);
        assert!(animated_container(&with_anim));

        // 只有 VP8X 标志位置起来、ANIM 还在头部之外时也要认。
        let flag_only = webp(&[(b"VP8X", &[0x12, 0, 0, 0, 0, 0, 0, 0, 0, 0])]);
        assert!(animated_container(&flag_only));

        let still_lossy = webp(&[(b"VP8 ", &[0; 10])]);
        assert!(!animated_container(&still_lossy));

        let still_extended = webp(&[(b"VP8X", &[0x04, 0, 0, 0, 0, 0, 0, 0, 0, 0])]);
        assert!(!animated_container(&still_extended));

        assert!(!animated_container(b"not a webp at all"));
    }

    #[test]
    fn truncated_head_reports_not_animated() {
        let three_frames = png(&[(b"IHDR", &[0; 13]), (b"acTL", &[0, 0, 0, 3, 0, 0, 0, 0])]);
        // 头部只剩一半：宁可漏判也不换路径（见模块注释）。
        assert!(!animated_container(&three_frames[..12]));
        assert!(!animated_container(&[]));
    }
}
