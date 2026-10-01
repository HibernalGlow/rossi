//! OCR 三个模型会话的**跨页复用**。
//!
//! 为什么要这一层：`ocr_analyze_page` 以前每页都重新 `from_file` 三个会话，
//! 也就是每页都要把 检测 4.7 MB + encoder 343.5 MB + decoder 117.5 MB + 擦字 206.3 MB
//! 从盘上读一遍、建一遍图。
//!
//! 实测（`test/ocr/completed_page_multi_page_probe_test.dart`，8 页真页同机两轮对表，
//! 「建会话」= 分析段墙钟 − 三段自报合计，这把尺在**同一页内取差**，所以不受负载漂移影响）：
//! 每页强制重建时**八页全部** 1793–2381 ms；复用后只有**第一页** 2518 ms，
//! 其余七页 15–103 ms。8 页均值 7227 ms → 6058 ms（**每页省 1170 ms**，
//! 第一页把那笔付掉、往后各页省 0.6–2.8 s）。
//!
//! 顺带否掉一条我原先写在这里的猜测：「每页新建会让擦字多吃一次动态 shape 冷启动，
//! 所以实际差距比 2 s 更大」—— **不成立**。同两轮里擦字所在三段合计 3421 ms（每页新建）
//! vs 3860 ms（复用），复用一侧没有更快，差距全部落在建会话那一段。
//!
//! 缓存的键是**路径 + 字节数 + mtime + EP**，不是「模型名」：
//! 用户重下权重时路径不变而内容变，只按路径缓存会让新权重永远不生效 ——
//! 那正是本 ADR 一路在防的「静默用旧的」。
//!
//! 锁的粒度是**整个一次建页**：同时两页各建一套会话会把内存顶到 1.3 GB×2，
//! 而阅读器本来就是一页一页建的，串行没有损失。

use crate::api::ocr::OcrModelPaths;
use anyhow::{Context, Result};
use rossi_ocr_core::{Detector, Ep, Inpainter, Recognizer};
use std::fs;
use std::path::Path;
use std::sync::Mutex;

pub(crate) struct Sessions {
    key: String,
    pub(crate) detector: Detector,
    pub(crate) recognizer: Recognizer,
    /// `(键, 会话)`。没给擦字模型时是 `None`；给了但键不同就重建。
    pub(crate) inpaint: Option<(String, Inpainter)>,
}

impl Sessions {
    fn new(models: &OcrModelPaths, ep: Ep, key: String, inpaint: Option<&str>) -> Result<Self> {
        Ok(Self {
            detector: Detector::from_file(Path::new(&models.det), ep)
                .with_context(|| format!("建检测会话失败：{}", models.det))?,
            recognizer: Recognizer::from_files(
                Path::new(&models.encoder),
                Path::new(&models.decoder),
                Path::new(&models.vocab),
                ep,
            )
            .with_context(|| format!("建识别会话失败：{}", models.encoder))?,
            inpaint: match inpaint {
                Some(p) => Some((
                    p.to_string(),
                    Inpainter::from_file(Path::new(p), ep)
                        .with_context(|| format!("建擦字会话失败：{p}"))?,
                )),
                None => None,
            },
            key,
        })
    }
}

static CACHE: Mutex<Option<Sessions>> = Mutex::new(None);

/// 一个文件的可辨识指纹：路径 + 字节数 + mtime。
fn stamp(path: &str) -> String {
    match fs::metadata(path) {
        Ok(m) => {
            let mt = m
                .modified()
                .map(|t| {
                    t.duration_since(std::time::UNIX_EPOCH)
                        .map(|d| d.as_secs())
                        .unwrap_or(0)
                })
                .unwrap_or(0);
            format!("{path}:{}:{mt}", m.len())
        }
        // 读不到元数据也要有稳定的表示：让它与「读到了但内容不同」一样触发重建，
        // 而不是让缺失文件悄悄沿用上一个会话。
        Err(_) => format!("{path}:unreadable"),
    }
}

pub(crate) fn session_key(models: &OcrModelPaths, ep: Ep, inpaint: Option<&str>) -> String {
    format!(
        "ep={}|det={}|enc={}|dec={}|vocab={}|inpaint={}",
        ep.label(),
        stamp(&models.det),
        stamp(&models.encoder),
        stamp(&models.decoder),
        stamp(&models.vocab),
        inpaint.map(stamp).unwrap_or_else(|| "-".to_string()),
    )
}

/// 取（必要时重建）会话，并在**持锁期间**跑完这一次建页。
///
/// 先丢旧的再建新的：反过来的话重建那一瞬间会同时驻留两套权重（约 1.3 GB×2）。
pub(crate) fn with_sessions<T>(
    key: &str,
    models: &OcrModelPaths,
    ep: Ep,
    inpaint: Option<&str>,
    f: impl FnOnce(&mut Sessions) -> Result<T>,
) -> Result<T> {
    let mut guard = CACHE.lock().unwrap_or_else(|e| e.into_inner());
    if guard.as_ref().map(|s| s.key != key).unwrap_or(true) {
        // 先把旧的放掉，再建新的。
        *guard = None;
        *guard = Some(Sessions::new(models, ep, key.to_string(), inpaint)?);
    }
    let sessions = guard
        .as_mut()
        .ok_or_else(|| anyhow::anyhow!("会话缓存为空（内部逻辑错了）"))?;
    f(sessions)
}

/// 让调用方在**离开阅读器**时主动交还内存（约 670 MB 常驻不是可以随手要的东西）。
/// 换章不调：那一条的语义是「人还在读」，下一张多半还要译。
pub(crate) fn release_sessions() {
    let mut guard = CACHE.lock().unwrap_or_else(|e| e.into_inner());
    *guard = None;
}
