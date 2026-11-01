#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then
  echo 'Usage: research/prepare-fixtures.sh /absolute/path/to/SDR-video-with-faces.mp4' >&2
  exit 2
fi
android_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
assets_dir="$android_dir/app/build/generated/labTestAssets"
mkdir -p "$assets_dir"
ffmpeg -y -v error -ss 2 -i "$1" -frames:v 1 "$assets_dir/face.jpg"
ffmpeg -y -v error -i "$1" -t 2 -vf scale=640:360 -c:v libx264 -preset ultrafast -crf 25 -an "$assets_dir/short.mp4"
ffmpeg -y -v error -i "$assets_dir/short.mp4" -vf transpose=clock -c:v libx264 -preset ultrafast -crf 25 "$assets_dir/rotated-raw.mp4"
ffmpeg -y -v error -display_rotation:v:0 90 -i "$assets_dir/rotated-raw.mp4" -c copy "$assets_dir/rotated.mp4"
rm "$assets_dir/rotated-raw.mp4"
for duration in 30 60 180; do
  filter='scale=640:360,fps=15'
  if [ "$duration" -eq 60 ]; then filter='crop=406:720,scale=360:640,fps=15'; fi
  ffmpeg -y -v error -stream_loop -1 -i "$1" -f lavfi -i sine=frequency=440:sample_rate=44100 \
    -map 0:v:0 -map 1:a:0 -t "$duration" -vf "$filter" \
    -c:v libx264 -preset ultrafast -crf 25 -c:a aac -b:a 64k \
    -metadata location='+31.1234+121.1234/' -metadata creation_time='2020-01-02T03:04:05Z' \
    "$assets_dir/matrix-$duration.mp4"
done
echo "Prepared private local fixtures in $assets_dir (ignored by Git)."
