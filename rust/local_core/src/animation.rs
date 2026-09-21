//! 动图容器嗅探：不像素解码，只看容器结构。
//!
//! 判定的字节扫描移植自 mImageViewer 的
//! `canonical_image_loader.rs::probe_static_animation` /
//! `apng_has_multiple_frames` / `webp_has_animation`（那里还有一条
//! `gif_has_multiple_frames`，见下）。
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
    apng_has_multiple_frames(bytes) || webp_has_animation(bytes)
}

fn u32_be(bytes: &[u8]) -> Option<u32> {
    Some(u32::from_be_bytes(*bytes.first_chunk::<4>()?))
}

fn u32_le(bytes: &[u8]) -> Option<u32> {
    Some(u32::from_le_bytes(*bytes.first_chunk::<4>()?))
}

/// PNG：`acTL` 块存在且 `num_frames > 1` 才算动图（APNG）。
///
/// 单帧 `acTL` 是合法的（编码器写成 1 帧），那种图与静图无异，不能因为
/// 「有 acTL」就换渲染路径。
fn apng_has_multiple_frames(bytes: &[u8]) -> bool {
    let mut rest = match bytes.strip_prefix(b"\x89PNG\r\n\x1a\n") {
        Some(rest) => rest,
        None => return false,
    };
    loop {
        // 块头 = 4 字节长度 + 4 字节类型；后面还有 payload 与 4 字节 CRC。
        if rest.len() < 8 {
            return false;
        }
        let Some(len) = u32_be(&rest[..4]) else {
            return false;
        };
        let kind = &rest[4..8];
        let len = len as usize;
        rest = &rest[8..];
        if kind == b"acTL" {
            // num_frames 是 acTL 的前 4 字节。
            return len >= 8 && u32_be(rest).is_some_and(|frames| frames > 1);
        }
        // 走到 IDAT 之后 acTL 已经不可能出现（规范允许它的位置只有图像数据之前）。
        if kind == b"IDAT" || kind == b"IEND" {
            return false;
        }
        let skipped = len + 4;
        if rest.len() < skipped {
            return false;
        }
        rest = &rest[skipped..];
    }
}

/// WebP：VP8X 的 animation 标志位，或出现 `ANIM` / `ANMF` 块。
///
/// 查标志位而不是只查块名，是因为仓库里现有的那条判定（按偏移 12 找 `ANIM`）
/// 结构上永远命中不了：动图 WebP 的**第一个块必须是 VP8X**，`ANIM` 在它后面。
fn webp_has_animation(bytes: &[u8]) -> bool {
    if bytes.len() < 12 || &bytes[..4] != b"RIFF" || &bytes[8..12] != b"WEBP" {
        return false;
    }
    let mut rest = &bytes[12..];
    while rest.len() >= 8 {
        let Some(len) = u32_le(&rest[4..8]).map(|len| len as usize) else {
            return false;
        };
        let kind = &rest[..4];
        let payload = &rest[8..];
        if kind == b"ANIM" || kind == b"ANMF" {
            return true;
        }
        // VP8X 的 flags 字节里 bit1 = animation（规范：本块必须是第一个块）。
        if kind == b"VP8X" {
            return payload.first().is_some_and(|flags| flags & 0x02 != 0);
        }
        let padded = len + (len & 1);
        if rest.len() < 8 + padded {
            return false;
        }
        rest = &rest[8 + padded..];
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    fn chunk(fourcc: &[u8; 4], payload: &[u8]) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(fourcc);
        out.extend_from_slice(&(payload.len() as u32).to_be_bytes());
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
