//! 波形峰值列 —— 视频进度条背后那条声音轮廓。
//!
//! 口径来自 mImageViewer 的 `video/seek_strip_wave.rs`，搬的是**判据与常量**，
//! 不是那台机器：上游 3656 行里绑了 `music_core::TimelineAnalysis`、wgpu 波形纹理
//! 与 SQLite tile 缓存，那些属于「原生 presenter」那一层，而 Rossi 的界面是 Flutter。
//! 上游的解码走 FFmpeg（`audio_decode.rs` 用 `ffmpeg_the_third`），而 **B4 明令
//! ffmpeg 不进 `local_core`**，所以解码器换成同为纯 Rust 的 symphonia
//! （MPL-2.0，文件级 copyleft，不是 GPL ⇒ 不触 ADR-0008 的许可线）。
//!
//! ```text
//! mimage 常量                       本文件
//! MIN_WAVEFORM_BIN_SECS 0.010   →   MIN_BIN_SECS（再细就是噪声）
//! COARSE_BIN_SECS       0.100   →   COARSE_BIN_SECS（粗列默认密度）
//! WAVEFORM_PRE_ROLL     0.75    →   PRE_ROLL_SECS（窗口前多解一点，首格不是半截）
//! WaveFileIdentity{path,size,mtime} → 缓存键在 Dart 侧（video_waveform_service）
//! ```
//!
//! ## 为什么每格取 RMS 而不是单点峰值
//!
//! 波形条要的是「这一段有多响」。单点峰值会被一两个瞬态尖峰拉满、让整条看起来一样粗；
//! RMS 之后再归一化，对白段与动作段才分得开。

use std::path::Path;

use anyhow::{Context, Result, anyhow};
use symphonia::core::audio::AudioBufferRef;
use symphonia::core::codecs::{CodecParameters, Decoder, DecoderOptions};
use symphonia::core::conv::IntoSample;
use symphonia::core::formats::{FormatOptions, SeekMode, SeekTo};
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use symphonia::core::units::Time;

/// 一格最短 10 ms（mimage 同名常量）。
pub const MIN_BIN_SECS: f64 = 0.010;
/// 粗列的默认密度：100 ms 一格（mimage `COARSE_BIN_SECS`）。
pub const COARSE_BIN_SECS: f64 = 0.100;
/// 窗口前多解 0.75 s 再丢弃（mimage `WAVEFORM_PRE_ROLL_SECS`）：
/// 不然拖动进度条时第一格总是缺半截，看上去像在抖。
pub const PRE_ROLL_SECS: f64 = 0.75;

/// 取 `[start, end)` 这段音频的峰值列，每格宽 `bin_secs` 秒。
///
/// 失败（容器不认识 / 没有音轨）返回 `Err`，由 UI 退化成「不画波形条」——
/// 这条功能整条都是装饰，绝不该让一个视频播不了。
pub fn wave_peaks(path: &Path, start: f64, end: f64, bin_secs: f64) -> Result<Vec<f32>> {
    let bin = bin_secs.max(MIN_BIN_SECS);
    let start = start.max(0.0);
    let end = if end > start + bin { end } else { start + bin };
    let pre_start = (start - PRE_ROLL_SECS).max(0.0);

    let file = std::fs::File::open(path).with_context(|| format!("打不开 {}", path.display()))?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());

    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let probe = symphonia::default::get_probe();
    let read = probe
        .format(
            &hint,
            mss,
            &FormatOptions::default(),
            &MetadataOptions::default(),
        )
        .context("这个文件里没有认识的音频容器")?;
    let mut format = read.format;

    // 音轨的判别用「能不能造出解码器」当判据，**不看 `channels`**：symphonia 在打开
    // 解码器之前常常还没解析出声道数 —— 真实样本（mkv/mp4 里的 AAC）就是因为这个
    // 被整条判成「没有音轨」，症状是进度条对最常见的视频永远不画波形。
    // 视频 codec 不在 symphonia 的注册表里，`make` 自然失败，所以这条路只会挑到音频轨。
    let mut chosen: Option<(u32, CodecParameters, Box<dyn Decoder>)> = None;
    for track in format.tracks() {
        let params = track.codec_params.clone();
        if let Ok(decoder) =
            symphonia::default::get_codecs().make(&params, &DecoderOptions::default())
        {
            chosen = Some((track.id, params, decoder));
            break;
        }
    }
    let Some((track_id, codec_params, mut decoder)) = chosen else {
        return Err(anyhow!("这个视频里没有能解码的音轨"));
    };
    // 打开解码器之后参数常被补全（AAC 的 sample_rate / time_base 在这里才落地），
    // 所以优先读 decoder 的那一份，读不到再退回轨道自带的那一份。
    let opened = decoder.codec_params();
    let fallback_rate = opened
        .sample_rate
        .or(codec_params.sample_rate)
        .unwrap_or(44100) as f64;
    let time_base = opened.time_base.or(codec_params.time_base);

    // 定位失败（不可 seek 的流）不致命：从头解，把窗口前的样本丢掉即可。
    let mut pos_secs = match format.seek(
        SeekMode::Accurate,
        SeekTo::Time {
            time: Time::new(pre_start.floor() as u64, pre_start.fract()),
            track_id: Some(track_id),
        },
    ) {
        // `SeekedTo` 给的是 `actual_ts`（该轨 time base 单位的刻度），
        // 换回秒才要和后面的样本计数对齐 —— 用请求位置冒充落点是错的：
        // 不可精确 seek 的容器常常差一整帧。
        Ok(seeked) => match time_base {
            Some(base) if base.denom != 0 => {
                seeked.actual_ts as f64 * base.numer as f64 / base.denom as f64
            }
            _ => pre_start,
        },
        Err(_) => 0.0,
    };

    let bin_frames = (bin * fallback_rate).max(1.0) as usize;
    let mut peaks: Vec<f32> = Vec::new();
    let mut sum_sq = 0f64;
    let mut frames_in_bin = 0usize;

    loop {
        if pos_secs >= end {
            break;
        }
        let packet = match format.next_packet() {
            Ok(packet) => packet,
            // EndOfStream 与坏包都按「解完了」处理，不是错误。
            Err(_) => break,
        };
        if packet.track_id() != track_id {
            continue;
        }
        let decoded = match decoder.decode(&packet) {
            Ok(decoded) => decoded,
            Err(_) => continue,
        };

        // 0.5 的 `AudioBufferRef` 不直接把 samples/rate 透出来（它们在 `AudioBuffer`
        // 与 `AudioSpec` 上），所以按分支就地取：样本率取缓冲区的 spec，
        // 帧数取第一平面长度 —— 各平面等长是 symphonia 的不变式。
        // 每个分支都会各赋一次 `planes`/`rate`，所以这里**故意不给初值**：
        // 给了就是「写了从没读过的值」（编译器也这么报），而漏一个分支会直接编译不过 ——
        // 那正是我们要的失败方式，别让一个假初值把缺分支咽下去。
        let planes: Vec<Vec<f32>>;
        let rate: f64;
        let mut unsigned = false;
        match &decoded {
            AudioBufferRef::F32(buf) => {
                planes = plane_f32(buf.planes().planes());
                rate = buf.spec().rate as f64;
            }
            AudioBufferRef::F64(buf) => {
                planes = plane_f32(buf.planes().planes());
                rate = buf.spec().rate as f64;
            }
            AudioBufferRef::U8(buf) => {
                planes = plane_f32(buf.planes().planes());
                rate = buf.spec().rate as f64;
                unsigned = true;
            }
            AudioBufferRef::U16(buf) => {
                planes = plane_f32(buf.planes().planes());
                rate = buf.spec().rate as f64;
                unsigned = true;
            }
            AudioBufferRef::U24(buf) => {
                planes = plane_f32(buf.planes().planes());
                rate = buf.spec().rate as f64;
                unsigned = true;
            }
            AudioBufferRef::S16(buf) => {
                planes = plane_f32(buf.planes().planes());
                rate = buf.spec().rate as f64;
            }
            AudioBufferRef::S32(buf) => {
                planes = plane_f32(buf.planes().planes());
                rate = buf.spec().rate as f64;
            }
            // 0.5 的 `AudioBufferRef` 比 0.6 多了 U32 / S8 / S24 三档，
            // 少了分支就是「编译过、某些 codec 直接 panic 在 match 上」。
            AudioBufferRef::U32(buf) => {
                planes = plane_f32(buf.planes().planes());
                rate = buf.spec().rate as f64;
                unsigned = true;
            }
            AudioBufferRef::S8(buf) => {
                planes = plane_f32(buf.planes().planes());
                rate = buf.spec().rate as f64;
            }
            AudioBufferRef::S24(buf) => {
                planes = plane_f32(buf.planes().planes());
                rate = buf.spec().rate as f64;
            }
        };
        // symphonia 把无符号格式映射到 0.0–1.0，**静音在中点**；不减掉那 0.5
        // 就是把直流偏置当响度，整条波形会一样粗。是否无符号由分支静态给出。
        let offset = if unsigned { 0.5 } else { 0.0 };
        let frames = planes.first().map_or(0, |plane| plane.len());
        let rate = if rate > 0.0 { rate } else { fallback_rate };
        let step = 1.0 / rate;

        for frame in 0..frames {
            let at = pos_secs;
            pos_secs += step;
            // 预滚段（以及定位落点与 `start` 之间的差额）不产峰。
            if at < start {
                continue;
            }
            let mut mono = 0f64;
            let mut channels = 0usize;
            for plane in &planes {
                if let Some(&value) = plane.get(frame) {
                    mono += (value as f64) - offset;
                    channels += 1;
                }
            }
            if channels == 0 {
                continue;
            }
            let value = mono / channels as f64;
            sum_sq += value * value;
            frames_in_bin += 1;
            if frames_in_bin >= bin_frames {
                push_rms_bin(&mut peaks, sum_sq, frames_in_bin);
                sum_sq = 0f64;
                frames_in_bin = 0;
            }
        }
    }

    if frames_in_bin > 0 {
        push_rms_bin(&mut peaks, sum_sq, frames_in_bin);
    }
    // **不做归一化**：归一化必须是「整条列一个基准」，否则每个窗口都被拉成
    // 0–1，拖动时看不出任何响度差 —— 上游正是这个原因把峰值列与归一化分在两步
    // （`TimelineAnalysis` 出绝对值，光栅化时才按整条列取 max）。
    // Rossi 侧进度条一次要的就是整条列（≈180 格），所以归一化交给调用方。
    Ok(peaks)
}

/// 一格的 RMS 入账。
fn push_rms_bin(peaks: &mut Vec<f32>, sum_sq: f64, frames: usize) {
    let rms = if frames == 0 {
        0.0
    } else {
        (sum_sq / frames as f64).sqrt()
    };
    peaks.push(rms as f32);
}

/// 任意样本平面 → f32 平面。无符号格式的中点归零由调用方按分支处理。
fn plane_f32<S>(planes: &[&[S]]) -> Vec<Vec<f32>>
where
    S: Copy + IntoSample<f32>,
{
    planes
        .iter()
        .map(|plane| {
            plane
                .iter()
                .map(|&sample| {
                    let value: f32 = sample.into_sample();
                    value
                })
                .collect()
        })
        .collect()
}

/// 归一到 0–1。**留给 UI 侧调用**：进度条拿到的整条列共用一个基准才有意义。
pub fn normalize_peaks(peaks: &mut [f32]) {
    let mut max = 0f32;
    for peak in peaks.iter() {
        if *peak > max {
            max = *peak;
        }
    }
    if max <= 0.0 {
        return;
    }
    for peak in peaks.iter_mut() {
        *peak = (*peak / max).clamp(0.0, 1.0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mean(values: &[f32]) -> f32 {
        if values.is_empty() {
            return 0.0;
        }
        values.iter().sum::<f32>() / values.len() as f32
    }

    /// 造一个 PCM s16le 单声道 WAV：前半响、后半轻。
    ///
    /// 自己写 RIFF 头而不是再引一个 wav 编码器：测试只依赖已经在树里的东西，
    /// 而且这正好证明解码走的是**容器**，不是「我预先知道样本」。
    fn write_sine_wav(path: &Path, seconds: f64, rate: u32) {
        let frames = (seconds * rate as f64) as usize;
        let mut data: Vec<u8> = Vec::with_capacity(frames * 2);
        for index in 0..frames {
            let t = index as f64 / rate as f64;
            let amp = if t < seconds / 2.0 { 0.6 } else { 0.05 };
            let sample = (amp * (2.0 * std::f64::consts::PI * 220.0 * t).sin() * 32767.0) as i16;
            data.extend_from_slice(&sample.to_le_bytes());
        }
        let mut bytes: Vec<u8> = Vec::new();
        bytes.extend_from_slice(b"RIFF");
        bytes.extend_from_slice(&(36 + data.len() as u32).to_le_bytes());
        bytes.extend_from_slice(b"WAVEfmt ");
        bytes.extend_from_slice(&16u32.to_le_bytes());
        bytes.extend_from_slice(&1u16.to_le_bytes()); // PCM
        bytes.extend_from_slice(&1u16.to_le_bytes()); // mono
        bytes.extend_from_slice(&rate.to_le_bytes());
        bytes.extend_from_slice(&(rate * 2).to_le_bytes());
        bytes.extend_from_slice(&2u16.to_le_bytes()); // block align
        bytes.extend_from_slice(&16u16.to_le_bytes()); // bits
        bytes.extend_from_slice(b"data");
        bytes.extend_from_slice(&(data.len() as u32).to_le_bytes());
        bytes.extend_from_slice(&data);
        std::fs::write(path, bytes).unwrap();
    }

    fn temp_wav(name: &str, seconds: f64) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("rossi-wave-{name}"));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join(format!("{name}.wav"));
        write_sine_wav(&path, seconds, 44100);
        path
    }

    #[test]
    fn bin_count_matches_window_over_bin_width() {
        let path = temp_wav("full", 2.0);
        let peaks = wave_peaks(&path, 0.0, 2.0, COARSE_BIN_SECS).unwrap();
        // 2 s / 0.1 s = 20 格；允许 ±2（最后一格可能不满、定位有前后偏差）。
        assert!(
            (18..=22).contains(&peaks.len()),
            "得到 {} 格，应在 18..=22",
            peaks.len()
        );
        let top = peaks.iter().copied().fold(0f32, f32::max);
        assert!(
            (0.05..=1.0).contains(&top),
            "0.6 振幅正弦的 RMS 应在 0.05–1.0 之间，得到 {top}"
        );
    }

    #[test]
    fn windows_keep_absolute_scale_so_they_are_comparable() {
        // 这条断言防的正是「每个窗口各自归一化」：那样前后两段都会变成 0–1，
        // 拖动条上看不出响度差，而这是波形条唯一的作用。
        let path = temp_wav("raw", 2.0);
        let loud = wave_peaks(&path, 0.0, 1.0, COARSE_BIN_SECS).unwrap();
        let quiet = wave_peaks(&path, 1.0, 2.0, COARSE_BIN_SECS).unwrap();
        assert!(
            mean(&loud) > mean(&quiet) * 2.0,
            "响段均值 {} 应是轻段 {} 的两倍以上（绝对刻度）",
            mean(&loud),
            mean(&quiet)
        );
        let mut merged = loud.clone();
        merged.extend(quiet.iter().copied());
        normalize_peaks(&mut merged);
        assert_eq!(
            merged.iter().copied().fold(0f32, f32::max),
            1.0,
            "归一化后最响那一格必须是 1"
        );
    }

    #[test]
    fn loud_first_half_dips_in_quiet_second_half() {
        let path = temp_wav("shape", 2.0);
        let peaks = wave_peaks(&path, 0.0, 2.0, COARSE_BIN_SECS).unwrap();
        let half = peaks.len() / 2;
        assert!(
            mean(&peaks[..half]) > mean(&peaks[half..]) * 2.0,
            "前半 {} 应显著高于后半 {}",
            mean(&peaks[..half]),
            mean(&peaks[half..])
        );
    }

    #[test]
    fn windowed_request_excludes_the_rest() {
        let path = temp_wav("window", 4.0);
        let loud = wave_peaks(&path, 0.0, 1.0, COARSE_BIN_SECS).unwrap();
        let quiet = wave_peaks(&path, 3.0, 4.0, COARSE_BIN_SECS).unwrap();
        assert!(
            mean(&loud) > mean(&quiet),
            "响段均值 {} 应高于轻段 {}",
            mean(&loud),
            mean(&quiet)
        );
    }

    #[test]
    fn unreadable_file_returns_err_not_panic() {
        let dir = std::env::temp_dir().join("rossi-wave-none");
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("not-audio.mp4");
        std::fs::write(&path, b"definitely not a media file").unwrap();
        assert!(wave_peaks(&path, 0.0, 10.0, COARSE_BIN_SECS).is_err());
    }
}
