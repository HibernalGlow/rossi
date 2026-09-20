#!/usr/bin/env bash
# 生成视频播放验收（docs/video-playback-acceptance.md）要用的全部样本。
#
# 为什么要有这个脚本：验收清单原先写的是「拿一个现成的图片文件夹，往里丢一个 mp4」，
# 但真去凑齐「带章节的 mkv / 同名字幕 / 伪装后缀 / 整本都是视频」这几样，
# 大多数人会中途放弃 —— 而这几样恰好各自对应一类只在真机才暴露的缺陷。
# 本机装了 ffmpeg 就能一把生成；没有 ffmpeg 会明确报错，不会生成半套。
#
# 用法：
#   script/make_video_samples.sh              # 生成到 /tmp/rossi-video-samples
#   script/make_video_samples.sh ~/Samples    # 生成到指定目录
set -euo pipefail

OUT="${1:-/tmp/rossi-video-samples}"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "需要 ffmpeg（brew install ffmpeg）。它是生成工具，不是运行依赖 —— 产物是普通 mp4/mkv。" >&2
  exit 1
fi

mkdir -p "$OUT"
FF=(ffmpeg -hide_banner -loglevel error -y)

# 一张能看的「漫画页」：彩色条纹 + 编号，翻起来一眼看得出顺序。
make_page() { # 目标 序号
  "${FF[@]}" -f lavfi -i "testsrc2=size=800x1200:rate=25:duration=0.04" \
    -frames:v 1 -update 1 "$1"
}

# ── 1. 视频夹在图片中间（A1 / A2 / A4 / B 组的主场景）──
M="$OUT/01_mixed_image_video_image"; mkdir -p "$M"
make_page "$M/001.jpg" 1
make_page "$M/003.jpg" 3
"${FF[@]}" -f lavfi -i "testsrc2=size=320x240:rate=25:duration=6" \
  -f lavfi -i "sine=frequency=220:sample_rate=44100:duration=6" \
  -map 0:v -map 1:a -c:v libx264 -pix_fmt yuv420p -c:a aac "$M/002.mp4"

# ── 2. 带章节 + 内嵌字幕 + 多音轨（C5b / 音轨面板 / 章节刻度）──
C="$OUT/02_chapters_multitrack"; mkdir -p "$C"
cat > "$C/chapters.txt" <<'EOF'
;FFMETADATA1
[CHAPTER]
TIMEBASE=1/1000
START=0
END=2500
title=第一章
[CHAPTER]
TIMEBASE=1/1000
START=2500
END=5000
title=第二章
EOF
printf '1\n00:00:01,000 --> 00:00:02,000\n第一句\n\n2\n00:00:03,000 --> 00:00:04,000\n第二句 | 带竖线\n\n' > "$C/in.srt"
# 第二条音轨用变调的正弦，切换时耳朵能听出区别。
"${FF[@]}" -f lavfi -i "testsrc2=size=320x240:rate=25:duration=5" \
  -f lavfi -i "sine=frequency=220:sample_rate=44100:duration=5" \
  -f lavfi -i "sine=frequency=330:sample_rate=44100:duration=5" \
  -f srt -i "$C/in.srt" -f ffmetadata -i "$C/chapters.txt" \
  -map 0:v -map 1:a -map 2:a -map 3:s -map_metadata 4 \
  -metadata:s:a:0 language=eng -metadata:s:a:1 language=jpn \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -c:s ass \
  "$C/chapters.mkv"
rm -f "$C/in.srt"   # 留 mkv 本体；内嵌字幕才是这条要验的

# ── 3. 同名字幕（侧挂）：C1 / C2 ──
S="$OUT/03_sidecar_subtitle"; mkdir -p "$S"
"${FF[@]}" -f lavfi -i "testsrc2=size=320x240:rate=25:duration=5" \
  -f lavfi -i "sine=frequency=220:sample_rate=44100:duration=5" \
  -map 0:v -map 1:a -c:v libx264 -pix_fmt yuv420p -c:a aac "$S/movie.mp4"
printf '1\n00:00:01,000 --> 00:00:02,500\n外挂字幕 中文\n\n2\n00:00:03,000 --> 00:00:04,000\n第二句\n\n' > "$S/movie.zh-CN.srt"
# MicroDVD：Rossi 侧要先转 WebVTT 才交给 mpv（探针 ⑥b 验的就是这条链）。
printf '{0}{60}MicroDVD 第一句|换行\n{70}{130}MicroDVD 第二句\n' > "$S/movie.sub"

# ── 4. 伪装后缀：D5（.nov 其实是 mp4）+ 自定义后缀 ──
D="$OUT/04_disguised"; mkdir -p "$D"
cp "$S/movie.mp4" "$D/hidden.nov"

# ── 5. 整本都是视频（A6：封面必须走海报，不能白图）──
V="$OUT/05_all_video"; mkdir -p "$V"
for n in 1 2 3; do
  "${FF[@]}" -f lavfi -i "testsrc2=size=320x240:rate=25:duration=4" \
    -f lavfi -i "sine=frequency=$((180 + n * 60)):sample_rate=44100:duration=4" \
    -map 0:v -map 1:a -c:v libx264 -pix_fmt yuv420p -c:a aac \
    "$V/$(printf '%03d' "$n").mp4"
done

# ── 6. 带容器转置的竖屏样本（信息卡「尺寸」该与画面一致）──
R="$OUT/06_rotated"; mkdir -p "$R"
"${FF[@]}" -display_rotation:v:0 90 \
  -f lavfi -i "testsrc2=size=320x240:rate=25:duration=3" \
  -c:v libx264 -pix_fmt yuv420p "$R/portrait.mp4"

# ── 7. 归档内含视频（A7 / E4：页数 = 图片 + 视频）──
Z="$OUT/07_archive"; mkdir -p "$Z"
(cd "$M" && zip -q "$Z/mixed.zip" 001.jpg 002.mp4 003.jpg)

echo
echo "样本已生成在：$OUT"
find "$OUT" -type f | sort | sed "s|$OUT/|  |"
echo
echo "把它们逐个加进书架（本地文件夹 / zip），按 docs/video-playback-acceptance.md 的编号对着看。"
