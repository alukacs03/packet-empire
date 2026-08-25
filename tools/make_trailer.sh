#!/usr/bin/env bash
set -euo pipefail

capture_dir="${1:-/tmp/packet-guided-deal-final.6U2MxZ}"
output_path="${2:-artifacts/packet-empire-highlight.mp4}"

mkdir -p "$(dirname "$output_path")"

images=(
  "$capture_dir/title.png"
  "$capture_dir/welcome.png"
  "$capture_dir/floor.png"
  "$capture_dir/rack_arrival.png"
  "$capture_dir/rack_cable_feedback.png"
  "$capture_dir/console.png"
  "$capture_dir/map.png"
  "$capture_dir/guided_lead.png"
  "$capture_dir/guided_delivery.png"
  "$capture_dir/floor_outage.png"
  "$capture_dir/ops.png"
  "$capture_dir/floor_mature.png"
  "$capture_dir/demo_end.png"
  "$capture_dir/title.png"
)

for image_path in "${images[@]}"; do
  if [[ ! -f "$image_path" ]]; then
    echo "Missing trailer frame: $image_path" >&2
    exit 1
  fi
done

segment_duration="4.0"
transition_duration="0.65"
step_duration="3.35"
frame_count="${#images[@]}"
total_duration="$(awk -v count="$frame_count" -v first="$segment_duration" -v step="$step_duration" 'BEGIN { printf "%.2f", first + (count - 1) * step }')"

input_args=()
for image_path in "${images[@]}"; do
  input_args+=( -loop 1 -framerate 30 -t "$segment_duration" -i "$image_path" )
done

# Three small synthesized voices form an original server-room score: a low mains
# drone, a breathing fifth, and a soft clocked pulse under filtered pink noise.
input_args+=(
  -f lavfi -t "$total_duration" -i "sine=frequency=55:sample_rate=48000"
  -f lavfi -t "$total_duration" -i "sine=frequency=82.41:sample_rate=48000"
  -f lavfi -t "$total_duration" -i "sine=frequency=220:sample_rate=48000"
  -f lavfi -t "$total_duration" -i "anoisesrc=color=pink:sample_rate=48000"
)

filter_graph=""

for ((index = 0; index < frame_count; index++)); do
  filter_graph+="[$index:v]scale=1408:792:force_original_aspect_ratio=increase,crop=1408:792,"
  filter_graph+="zoompan=z='min(zoom+0.00030,1.065)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=1280x720:fps=30,"
  filter_graph+="trim=duration=$segment_duration,setpts=PTS-STARTPTS"
  filter_graph+="[v$index];"
done

current="v0"
for ((index = 1; index < frame_count; index++)); do
  offset="$(awk -v step="$step_duration" -v frame_index="$index" 'BEGIN { printf "%.2f", step * frame_index }')"
  next="mix$index"
  filter_graph+="[$current][v$index]xfade=transition=fade:duration=$transition_duration:offset=$offset[$next];"
  current="$next"
done

audio_start="$frame_count"
filter_graph+="[$audio_start:a]volume=0.12,lowpass=f=180,pan=stereo|FL=0.72*c0|FR=0.72*c0[bass];"
filter_graph+="[$((audio_start + 1)):a]volume=0.055,tremolo=f=0.12:d=0.55,lowpass=f=420,pan=stereo|FL=0.86*c0|FR=0.38*c0[fifth];"
filter_graph+="[$((audio_start + 2)):a]volume=0.022,tremolo=f=0.72:d=0.92,highpass=f=160,lowpass=f=1600,pan=stereo|FL=0.28*c0|FR=0.92*c0[pulse];"
filter_graph+="[$((audio_start + 3)):a]volume=0.018,highpass=f=70,lowpass=f=1800,pan=stereo|FL=0.62*c0|FR=0.78*c0[air];"
filter_graph+="[bass][fifth][pulse][air]amix=inputs=4:normalize=0,"
filter_graph+="afade=t=in:st=0:d=2.0,afade=t=out:st=$(awk -v total="$total_duration" 'BEGIN { printf "%.2f", total - 2.5 }'):d=2.5,"
filter_graph+="loudnorm=I=-19:TP=-1.5:LRA=8[aout]"

/opt/homebrew/bin/ffmpeg -y \
  "${input_args[@]}" \
  -filter_complex "$filter_graph" \
  -map "[$current]" -map "[aout]" \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
  -c:a aac -b:a 192k -ar 48000 \
  -movflags +faststart -shortest "$output_path"

echo "$output_path"
