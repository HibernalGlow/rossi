//! 文字识别：manga-ocr 的 ONNX 导出（`mayocream/manga-ocr-onnx`，apache-2.0）。
//!
//! 依据见 ADR-0018 §决定 3.2：同一探针下 encoder 38.5 ms / decoder 2.2 ms 每步（CPU），
//! CoreML EP 两边都更慢；**这份导出没有 KV cache**，自回归每步重跑整个前缀 → 单格成本按 O(n²) 长。
//!
//! 与 Python 参考实现（`manga_ocr`）的口径差异，写在这里免得后人以为漏了：
//! - 预处理：224×224 **压扁**（不保宽高比，`ViTFeatureExtractor` 的默认行为）、
//!   均值/方差 **0.5 / 0.5**（不是 ImageNet 那组 —— 那组是检测件的）；
//! - 解码：参考实现用 `num_beams=4`，一期用**贪心**；`no_repeat_ngram_size=3` 保留，
//!   因为它在短文本上直接决定「会不会复读同一个词」。

use crate::session::{Ep, Stage, build_session};
use anyhow::{Context, Result, anyhow};
use image::{RgbImage, imageops::FilterType};
use ort::session::Session;
use ort::value::TensorRef;
use std::path::Path;
use std::time::Instant;

/// `[CLS]`：参考实现的 `decoder_start_token_id`。
const DECODER_START: i64 = 2;
/// `[SEP]`：参考实现的 `eos_token_id`。
const EOS: i64 = 3;
/// 词表头部这 5 个是特殊 token（`[PAD] [UNK] [CLS] [SEP] [MASK]`），解码时一律丢掉。
const SPECIAL_IDS: std::ops::RangeInclusive<i64> = 0..=4;
const IMAGE_SIZE: u32 = 224;
const IMAGE_MEAN: f32 = 0.5;
const IMAGE_STD: f32 = 0.5;

pub struct Recognizer {
    encoder: Session,
    decoder: Session,
    vocab: Vec<String>,
    max_new_tokens: usize,
    ep: Ep,
}

pub struct Recognition {
    pub text: String,
    /// 实际生成的 token 数（含终止符），用来判断是否被 `max_new_tokens` 截断。
    pub tokens: usize,
    /// 是否因达到 `max_new_tokens` 而停下（**没有**遇到 EOS）——截断的文本要当可疑结果看。
    pub truncated: bool,
    pub encoder_ms: u128,
    pub decoder_ms: u128,
}

impl Recognizer {
    pub fn from_files(encoder: &Path, decoder: &Path, vocab: &Path, ep: Ep) -> Result<Self> {
        let vocab = load_vocab(vocab)?;
        Ok(Self {
            encoder: build_session(encoder, ep, Stage::Recognize, 1)?,
            decoder: build_session(decoder, ep, Stage::Recognize, 1)?,
            vocab,
            max_new_tokens: 64,
            // 记实际生效的 EP，理由同 Detector。
            ep: ep.resolve(Stage::Recognize),
        })
    }

    pub fn with_max_new_tokens(mut self, n: usize) -> Self {
        self.max_new_tokens = n.max(1);
        self
    }

    pub fn ep(&self) -> Ep {
        self.ep
    }

    pub fn vocab_size(&self) -> usize {
        self.vocab.len()
    }

    pub fn recognize(&mut self, crop: &RgbImage) -> Result<Recognition> {
        if crop.width() == 0 || crop.height() == 0 {
            return Err(anyhow!("空裁剪块"));
        }
        let pixels = preprocess(crop);
        let tensor = TensorRef::from_array_view((
            [1usize, 3, IMAGE_SIZE as usize, IMAGE_SIZE as usize],
            pixels.as_slice(),
        ))
        .context("构造 encoder 输入")?;

        // 输出借用 encoder 会话，作用域必须收在一个块里，否则后面 `self.decode_ids` 借不到 self。
        let (hidden, hidden_len, hidden_dim, encoder_ms) = {
            let encode_start = Instant::now();
            let encoded = self
                .encoder
                .run(ort::inputs![tensor])
                .map_err(|e| anyhow!("encoder 推理失败：{e:?}"))?;
            let (shape, raw) = encoded[0]
                .try_extract_tensor::<f32>()
                .context("读取 encoder 输出")?;
            let hidden_len: usize = shape
                .get(1)
                .copied()
                .ok_or_else(|| anyhow!("encoder 输出缺少序列维：{shape:?}"))?
                as usize;
            let hidden_dim: usize = shape
                .get(2)
                .copied()
                .ok_or_else(|| anyhow!("encoder 输出缺少特征维：{shape:?}"))?
                as usize;
            (
                raw.to_vec(),
                hidden_len,
                hidden_dim,
                encode_start.elapsed().as_millis(),
            )
        };

        let decode_start = Instant::now();
        let mut ids: Vec<i64> = vec![DECODER_START];
        let mut truncated = true;
        for _ in 0..self.max_new_tokens {
            let ids_tensor = TensorRef::from_array_view(([1usize, ids.len()], ids.as_slice()))
                .context("构造 decoder 输入")?;
            let hidden_tensor =
                TensorRef::from_array_view(([1usize, hidden_len, hidden_dim], hidden.as_slice()))
                    .context("构造 encoder_hidden_states 输入")?;
            let out = self
                .decoder
                .run(ort::inputs![ids_tensor, hidden_tensor])
                .map_err(|e| anyhow!("decoder 推理失败：{e:?}"))?;
            let (lshape, logits) = out[0]
                .try_extract_tensor::<f32>()
                .context("读取 decoder 输出")?;
            let vocab_size: usize = lshape
                .last()
                .copied()
                .ok_or_else(|| anyhow!("decoder 输出缺少词表维：{lshape:?}"))?
                as usize;
            let steps = lshape.get(1).copied().unwrap_or(1) as usize;
            let last = ids.len().saturating_sub(1).min(steps.saturating_sub(1));
            let row = &logits[last * vocab_size..(last + 1) * vocab_size];
            let next = argmax_without_ngram_repeat(row, &ids, vocab_size);
            ids.push(next);
            if next == EOS {
                truncated = false;
                break;
            }
        }
        let decoder_ms = decode_start.elapsed().as_millis();
        let text = self.decode_ids(&ids[1..]);
        Ok(Recognition {
            text,
            tokens: ids.len() - 1,
            truncated,
            encoder_ms,
            decoder_ms,
        })
    }

    /// 词表是**字符级**的（无 `##` 续词、无 SentencePiece 前缀），所以直接拼接即可；
    /// 只需丢掉特殊 token。`[UNK]` 也丢：留着会在回填时变成可见乱码。
    fn decode_ids(&self, ids: &[i64]) -> String {
        let mut out = String::new();
        for &id in ids {
            if SPECIAL_IDS.contains(&id) || id == EOS {
                continue;
            }
            match self.vocab.get(id as usize) {
                Some(tok) if !is_special_text(tok) => out.push_str(tok),
                Some(_) => {}
                None => {}
            }
        }
        out.trim().to_string()
    }
}

fn is_special_text(token: &str) -> bool {
    (token.starts_with('[') && token.ends_with(']'))
        || (token.starts_with('<') && token.ends_with('>'))
}

/// 词表文件是 CRLF 且首行是 `[PAD]`；空行（若有）按空串保留，否则 id 与行号会错位。
pub fn load_vocab(path: &Path) -> Result<Vec<String>> {
    let text =
        std::fs::read_to_string(path).with_context(|| format!("读词表失败：{}", path.display()))?;
    let vocab: Vec<String> = text
        .lines()
        .map(|line| line.trim_end_matches('\r').to_string())
        .collect();
    if vocab.len() < 100 {
        return Err(anyhow!(
            "词表行数可疑：{} 行（{}）",
            vocab.len(),
            path.display()
        ));
    }
    Ok(vocab)
}

fn preprocess(crop: &RgbImage) -> Vec<f32> {
    let resized = image::imageops::resize(crop, IMAGE_SIZE, IMAGE_SIZE, FilterType::Triangle);
    let plane = (IMAGE_SIZE * IMAGE_SIZE) as usize;
    let mut out = vec![0.0f32; 3 * plane];
    for (x, y, px) in resized.enumerate_pixels() {
        let idx = (y * IMAGE_SIZE + x) as usize;
        for c in 0..3 {
            out[c * plane + idx] = (px.0[c] as f32 / 255.0 - IMAGE_MEAN) / IMAGE_STD;
        }
    }
    out
}

/// 贪心 + `no_repeat_ngram_size = 3`：禁止生成会与已生成序列构成重复三元组的 token。
/// 参考实现是 `num_beams = 4` + 同一条 ngram 规则；一期先要「不复读」，不要 beam 的代价。
fn argmax_without_ngram_repeat(row: &[f32], ids: &[i64], vocab_size: usize) -> i64 {
    let n = 3usize;
    let history = &ids[1..]; // 不含起始的 [CLS]
    let mut banned: Vec<i64> = Vec::new();
    if history.len() >= n - 1 {
        let tail = &history[history.len() - (n - 1)..];
        for i in 0..history.len().saturating_sub(n - 1) {
            if &history[i..i + n - 1] == tail {
                banned.push(history[i + n - 1]);
            }
        }
    }
    let mut best = -1i64;
    let mut best_v = f32::NEG_INFINITY;
    for id in 0..vocab_size.min(row.len()) {
        let v = row[id];
        if v > best_v {
            best_v = v;
            best = id as i64;
        }
    }
    if !banned.contains(&best) {
        return best;
    }
    // 命中最优 token 被禁 → 取下一个不被禁的。全被禁时退回原最优（不返回垃圾）。
    let mut fallback = best;
    let mut fallback_v = f32::NEG_INFINITY;
    for id in 0..vocab_size.min(row.len()) {
        let id = id as i64;
        if banned.contains(&id) {
            continue;
        }
        if row[id as usize] > fallback_v {
            fallback_v = row[id as usize];
            fallback = id;
        }
    }
    if fallback_v == f32::NEG_INFINITY {
        return best;
    }
    fallback
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write_vocab(lines: usize) -> (tempfile::TempDir, std::path::PathBuf) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vocab.txt");
        let mut text = String::from("[PAD]\r\n[UNK]\r\n[CLS]\r\n[SEP]\r\n[MASK]\r\n");
        for i in 5..lines {
            text.push_str(&format!("t{i}\r\n"));
        }
        std::fs::write(&path, text).unwrap();
        (dir, path)
    }

    #[test]
    fn vocab_keeps_line_order_and_strips_cr() {
        let (_dir, path) = write_vocab(200);
        let vocab = load_vocab(&path).unwrap();
        assert_eq!(vocab.len(), 200);
        assert_eq!(vocab[0], "[PAD]");
        assert_eq!(vocab[5], "t5");
        assert!(!vocab[5].contains('\r'));
    }

    #[test]
    fn suspicious_vocab_is_rejected() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vocab.txt");
        std::fs::write(&path, "[PAD]\n[UNK]\n").unwrap();
        assert!(load_vocab(&path).is_err());
    }

    #[test]
    fn preprocess_is_nchw_normalized() {
        let mut img = RgbImage::new(10, 40);
        for p in img.pixels_mut() {
            *p = image::Rgb([255, 0, 128]);
        }
        let data = preprocess(&img);
        let plane = (IMAGE_SIZE * IMAGE_SIZE) as usize;
        assert_eq!(data.len(), 3 * plane);
        assert!((data[0] - 1.0).abs() < 1e-6, "R=255 → +1");
        assert!((data[plane] + 1.0).abs() < 1e-6, "G=0 → -1");
    }

    #[test]
    fn ngram_block_forbids_repeating_triples() {
        // history 里出现过 [1,2,3]，现在尾部是 [1,2] → 3 必须被禁。
        let mut row = vec![0.0f32; 200];
        row[3] = 10.0; // 被禁的 token 恰好是最优
        row[7] = 1.0;
        let ids = vec![DECODER_START, 1, 2, 3, 1, 2];
        let next = argmax_without_ngram_repeat(&row, &ids, 200);
        assert_eq!(next, 7, "应当跳过会造成三元组重复的 token");
    }

    #[test]
    fn ngram_rule_leaves_normal_case_alone() {
        let mut row = vec![0.0f32; 200];
        row[42] = 5.0;
        let ids = vec![DECODER_START, 9, 9];
        assert_eq!(argmax_without_ngram_repeat(&row, &ids, 200), 42);
    }
}
