//! 看像素用的裁剪工具：把一页（或一页的某块）带坐标网格地画出来。
//!
//! 为什么要有：判「这块字到底是被检测漏了，还是被框到了但掩膜没盖住」，
//! 靠的是**页面上的位置**，而位置只能从图上读。没有网格时我只能估坐标，
//! 估错了就会把「漏检」误判成「外扩不够」—— 这两个的修法完全不同。
//!
//! 用法：
//! `crop_view <in.png> [--out out.png] [--rect x,y,w,h] [--grid 50] [--box x0,y0,x1,y1 ...]`
//! `--rect` 裁剪（默认整页），`--grid` 画网格（0 = 不画），`--box` 叠画若干矩形便于核对。

use anyhow::{Result, anyhow};
use image::{Rgb, RgbImage};
use std::path::PathBuf;

fn main() -> Result<()> {
    let mut input: Option<PathBuf> = None;
    let mut output = PathBuf::from("/tmp/ocr-lab/crop_view.png");
    let mut rect: Option<(u32, u32, u32, u32)> = None;
    let mut grid = 50u32;
    let mut boxes: Vec<(i32, i32, i32, i32)> = Vec::new();

    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--out" => output = PathBuf::from(args.next().ok_or_else(|| anyhow!("--out 缺值"))?),
            "--rect" => {
                let v = args.next().ok_or_else(|| anyhow!("--rect 缺值"))?;
                let n: Vec<u32> = v
                    .split(',')
                    .map(|s| s.trim().parse::<u32>())
                    .collect::<Result<_, _>>()?;
                if n.len() != 4 {
                    return Err(anyhow!("--rect 要 x,y,w,h"));
                }
                rect = Some((n[0], n[1], n[2], n[3]));
            }
            "--grid" => grid = args.next().ok_or_else(|| anyhow!("--grid 缺值"))?.parse()?,
            "--box" => {
                let v = args.next().ok_or_else(|| anyhow!("--box 缺值"))?;
                // 一次传一批：`x0,y0,x1,y1;x0,y0,x1,y1;…`
                for group in v.split(';') {
                    if group.trim().is_empty() {
                        continue;
                    }
                    let n: Vec<i32> = group
                        .split(',')
                        .map(|s| s.trim().parse::<i32>())
                        .collect::<Result<_, _>>()?;
                    if n.len() != 4 {
                        return Err(anyhow!("--box 要 x0,y0,x1,y1（分号分隔多个）"));
                    }
                    boxes.push((n[0], n[1], n[2], n[3]));
                }
            }
            other => input = Some(PathBuf::from(other)),
        }
    }
    let page = image::open(input.ok_or_else(|| anyhow!("要一个输入图"))?)?.to_rgb8();
    let (pw, ph) = page.dimensions();
    let (rx, ry, rw, rh) = rect.unwrap_or((0, 0, pw, ph));
    let (rw, rh) = (rw.min(pw - rx), rh.min(ph - ry));
    let mut img = image::imageops::crop_imm(&page, rx, ry, rw, rh).to_image();

    if grid > 0 {
        for gy in (0..rh).step_by(grid as usize) {
            for x in 0..rw {
                put(&mut img, x, gy, [255, 0, 0], 2);
                if gy > 0 {
                    put(&mut img, x, gy - 1, [255, 180, 180], 1);
                }
            }
        }
        for gx in (0..rw).step_by(grid as usize) {
            for y in 0..rh {
                put(&mut img, gx, y, [0, 120, 255], 2);
            }
            for (k, digit) in format!("{}", gx + rx).chars().enumerate() {
                glyph(&mut img, gx + 2, 2 + k as u32 * 7, digit, [0, 0, 200]);
            }
        }
        for gy in (0..rh).step_by(grid as usize) {
            for (k, digit) in format!("{}", gy + ry).chars().enumerate() {
                glyph(&mut img, 2 + k as u32 * 7, gy + 2, digit, [200, 0, 0]);
            }
        }
    }
    for (x0, y0, x1, y1) in &boxes {
        let (a, b) = (*x0 - rx as i32, *y0 - ry as i32);
        let (c, d) = (*x1 - rx as i32, *y1 - ry as i32);
        for x in a.max(0)..c.min(rw as i32) {
            for t in [b, d] {
                if (0..rh as i32).contains(&t) {
                    put(&mut img, x as u32, t as u32, [0, 220, 0], 2);
                }
            }
        }
        for y in b.max(0)..d.min(rh as i32) {
            for t in [a, c] {
                if (0..rw as i32).contains(&t) {
                    put(&mut img, t as u32, y as u32, [0, 220, 0], 2);
                }
            }
        }
    }
    std::fs::create_dir_all(output.parent().unwrap_or(PathBuf::from(".").as_path()))?;
    img.save(&output)?;
    println!(
        "{}x{} （取自 {pw}x{ph} 的 {rx},{ry}）→ {}",
        rw,
        rh,
        output.display()
    );
    Ok(())
}

fn put(img: &mut RgbImage, x: u32, y: u32, color: [u8; 3], thick: u32) {
    for dy in 0..thick {
        for dx in 0..thick {
            if x + dx < img.width() && y + dy < img.height() {
                img.put_pixel(x + dx, y + dy, Rgb(color));
            }
        }
    }
}

/// 3x5 的极简数字，只为标坐标，不做字体。
fn glyph(img: &mut RgbImage, x: u32, y: u32, ch: char, color: [u8; 3]) {
    let bits: &[&str] = match ch {
        '0' => &["111", "101", "101", "101", "111"],
        '1' => &["010", "110", "010", "010", "111"],
        '2' => &["111", "001", "111", "100", "111"],
        '3' => &["111", "001", "111", "001", "111"],
        '4' => &["101", "101", "111", "001", "001"],
        '5' => &["111", "100", "111", "001", "111"],
        '6' => &["111", "100", "111", "101", "111"],
        '7' => &["111", "001", "010", "010", "010"],
        '8' => &["111", "101", "111", "101", "111"],
        '9' => &["111", "101", "111", "001", "111"],
        _ => return,
    };
    for (dy, row) in bits.iter().enumerate() {
        for (dx, c) in row.chars().enumerate() {
            if c == '1' {
                put(img, x + dx as u32, y + dy as u32, color, 1);
            }
        }
    }
}
