#!/system/bin/sh

output_dir="$1"
frame_count="$2"
interval_seconds="$3"
frame_prefix="${4:-frame}"
timeline="$output_dir/${frame_prefix}-timeline.tsv"

i=0
while [ "$i" -lt "$frame_count" ]; do
  started_at="$(date +%s%N)"
  snapshot_display -f "$output_dir/${frame_prefix}_$i.jpeg"
  finished_at="$(date +%s%N)"
  printf '%s\t%s\t%s\n' "$i" "$started_at" "$finished_at" >> "$timeline"
  i=$((i + 1))
  sleep "$interval_seconds"
done

touch "$output_dir/${frame_prefix}-done"
