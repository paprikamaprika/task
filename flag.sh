#!/usr/bin/env bash
set -euo pipefail

# ---------- Config ----------
PIXEL_ON='..'
PIXEL_OFF='  '
FILL_CHAR=' '
MIN_CHARS_PER_LINE=6
MAX_CHARS_PER_LINE=14
OUTER_MARGIN="${OUTER_MARGIN:-6}"
INNER_GUTTER="${INNER_GUTTER:-4}"

# Flag in codes only (no plain flag string)
FLAG_CODES=(
  111 112 101 110 99 116 102 123
  89 95 100 49 100 95 33 116 95
  103 48 79 100 95 119 48 114 124
  60 95 66 52 111 111 111 111 111
  111 111 111 111 111 125
)

# 5x5 font
# 1 = on pixel, 0 = off pixel
declare -A FONT
FONT['A']='01110;10001;11111;10001;10001'
FONT['B']='11110;10001;11110;10001;11110'
FONT['C']='01111;10000;10000;10000;01111'
FONT['D']='11110;10001;10001;10001;11110'
FONT['E']='11111;10000;11110;10000;11111'
FONT['F']='11111;10000;11110;10000;10000'
FONT['G']='01111;10000;10011;10001;01110'
FONT['N']='10001;11001;10101;10011;10001'
FONT['O']='01110;10001;10001;10001;01110'
FONT['P']='11110;10001;11110;10000;10000'
FONT['R']='11110;10001;11110;10010;10001'
FONT['T']='11111;00100;00100;00100;00100'
FONT['W']='10001;10001;10101;10101;01010'
FONT['Y']='10001;01010;00100;00100;00100'

FONT['0']='01110;10001;10001;10001;01110'
FONT['1']='00100;01100;00100;00100;01110'
FONT['4']='10010;10010;11111;00010;00010'

FONT['{']='00110;00100;01000;00100;00110'
FONT['}']='01100;00100;00010;00100;01100'
FONT['_']='00000;00000;00000;00000;11111'
FONT['!']='00100;00100;00100;00000;00100'
FONT['|']='00100;00100;00100;00100;00100'
FONT['<']='00010;00100;01000;00100;00010'
FONT['?']='11111;00010;00100;00000;00100'
FONT[' ']='00000;00000;00000;00000;00000'

repeat_char() {
  local ch="$1"
  local count="$2"
  local out=''
  local i
  for ((i = 0; i < count; i++)); do
    out+="$ch"
  done
  printf '%s' "$out"
}

repeat_to_width() {
  local pattern="$1"
  local width="$2"
  local out=''
  while [ "${#out}" -lt "$width" ]; do
    out+="$pattern"
  done
  printf '%s' "${out:0:width}"
}

build_flag_from_codes() {
  local out=''
  local code ch
  for code in "${FLAG_CODES[@]}"; do
    printf -v ch '\\%03o' "$code"
    out+="$ch"
  done
  printf '%b' "$out"
}

get_pattern() {
  local ch="$1"
  local key="$ch"

  if [[ "$ch" =~ [a-z] ]]; then
    key="${ch^^}"
  fi

  if [[ -n "${FONT[$key]:-}" ]]; then
    printf '%s' "${FONT[$key]}"
  else
    printf '%s' "${FONT['?']}"
  fi
}

# Global rendered rows for chunk
RENDER_ROWS=()

render_chunk_rows() {
  local chunk="$1"
  local hscale="$2"
  local len=${#chunk}
  local row idx col bit char pattern bits pixel
  local gap

  RENDER_ROWS=()
  gap="$(repeat_char "$PIXEL_OFF" "$hscale")"

  for row in 0 1 2 3 4; do
    local line=''

    for ((idx = 0; idx < len; idx++)); do
      char="${chunk:idx:1}"
      pattern="$(get_pattern "$char")"
      IFS=';' read -r -a rows <<< "$pattern"
      bits="${rows[$row]}"

      for ((col = 0; col < ${#bits}; col++)); do
        bit="${bits:col:1}"
        if [[ "$bit" == '1' ]]; then
          pixel="$PIXEL_ON"
        else
          pixel="$PIXEL_OFF"
        fi
        line+="$(repeat_char "$pixel" "$hscale")"
      done

      if [ "$idx" -lt $((len - 1)) ]; then
        line+="$gap"
      fi
    done

    RENDER_ROWS+=("$line")
  done
}

build_centered_line() {
  local text="$1"
  local width="$2"
  local fill="$3"

  if [ "${#text}" -ge "$width" ]; then
    printf '%s' "${text:0:width}"
    return
  fi

  local pad=$((width - ${#text}))
  local left=$((pad / 2))
  local right=$((pad - left))
  printf '%s%s%s' "$(repeat_char "$fill" "$left")" "$text" "$(repeat_char "$fill" "$right")"
}

print_scene() {
  local idx="$1"
  local canvas_width="$2"
  local margin_pad="$3"
  local s1 s2 s3

  case "$((idx % 3))" in
    0)
      s1='   /\_/\        .-.-.        /\_/\   '
      s2='  ( o.o )      (     )      ( o.o )  '
      s3='   > ^ <        `-.-`        > ^ <   '
      ;;
    1)
      s1='   *     .       *       .     *     '
      s2='      /\        /\ /\        /\      '
      s3='     /__\      /_/_\_\      /__\     '
      ;;
    *)
      s1='   <>==<>==<>==<>==<>==<>==<>==<>    '
      s2='   ||  ||  ||  ||  ||  ||  ||  ||    '
      s3='   <>==<>==<>==<>==<>==<>==<>==<>    '
      ;;
  esac

  printf '%s%s\n' "$margin_pad" "$(build_centered_line "$s1" "$canvas_width" ' ')"
  printf '%s%s\n' "$margin_pad" "$(build_centered_line "$s2" "$canvas_width" ' ')"
  printf '%s%s\n' "$margin_pad" "$(build_centered_line "$s3" "$canvas_width" ' ')"
}

main() {
  local flag term_cols term_lines canvas_width inner_width content_width title
  local chars_per_line len chunks
  local hscale vscale available_lines
  local start=0 chunk chunk_idx=0
  local used=0
  local margin_pad

  flag="$(build_flag_from_codes)"
  len=${#flag}

  term_cols="$(tput cols 2>/dev/null || echo 120)"
  term_lines="$(tput lines 2>/dev/null || echo 40)"

  if [ "$term_cols" -lt 80 ]; then term_cols=80; fi
  if [ "$term_lines" -lt 24 ]; then term_lines=24; fi

  canvas_width=$((term_cols - (OUTER_MARGIN * 2)))
  if [ "$canvas_width" -lt 50 ]; then
    canvas_width=50
  fi
  inner_width=$((canvas_width - 2))
  content_width=$((inner_width - (INNER_GUTTER * 2)))
  if [ "$content_width" -lt 30 ]; then
    content_width=30
    inner_width=$((content_width + (INNER_GUTTER * 2)))
    canvas_width=$((inner_width + 2))
  fi
  margin_pad="$(repeat_char ' ' "$OUTER_MARGIN")"

  # Each char roughly needs 12 columns at hscale=1 with '..' pixels.
  chars_per_line=$((content_width / 12))
  if [ "$chars_per_line" -lt "$MIN_CHARS_PER_LINE" ]; then chars_per_line="$MIN_CHARS_PER_LINE"; fi
  if [ "$chars_per_line" -gt "$MAX_CHARS_PER_LINE" ]; then chars_per_line="$MAX_CHARS_PER_LINE"; fi
  if [ "$chars_per_line" -gt "$len" ]; then chars_per_line="$len"; fi

  chunks=$(((len + chars_per_line - 1) / chars_per_line))

  # Fit width scale
  local base_bits=$((6 * chars_per_line - 1))
  hscale=$((inner_width / (base_bits * 2)))
  if [ "$hscale" -lt 1 ]; then hscale=1; fi
  if [ "$hscale" -gt 2 ]; then hscale=2; fi

  # Fit height scale
  available_lines=$((term_lines - 6))
  vscale=$(((available_lines - 2 * chunks) / (5 * chunks)))
  if [ "$vscale" -lt 1 ]; then vscale=1; fi
  if [ "$vscale" -gt 3 ]; then vscale=3; fi

  clear

  title='[ DOT-MATRIX FLAG WALL ]'
  printf '%s%s\n' "$margin_pad" "$(build_centered_line "$title" "$canvas_width" ' ')"
  used=$((used + 1))

  printf '%s%s\n' "$margin_pad" "$(build_centered_line "$(repeat_to_width '.~' "$canvas_width")" "$canvas_width" ' ')"
  used=$((used + 1))
  print_scene 0 "$canvas_width" "$margin_pad"
  used=$((used + 3))
  printf '\n'
  used=$((used + 1))

  while [ "$start" -lt "$len" ]; do
    chunk="${flag:start:chars_per_line}"
    render_chunk_rows "$chunk" "$hscale"

    printf '%s+%s+\n' "$margin_pad" "$(repeat_char '-' "$inner_width")"
    used=$((used + 1))

    local r vr row_text
    for r in 0 1 2 3 4; do
      row_text="${RENDER_ROWS[$r]}"
      local row_len=${#row_text}
      if [ "$row_len" -gt "$content_width" ]; then
        row_text="${row_text:0:content_width}"
        row_len=${#row_text}
      fi

      local pad=$((content_width - row_len))
      local left=$((pad / 2))
      local right=$((pad - left))
      local left_fill right_fill
      left_fill="$(repeat_char "$FILL_CHAR" "$left")"
      right_fill="$(repeat_char "$FILL_CHAR" "$right")"
      local gutter
      gutter="$(repeat_char ' ' "$INNER_GUTTER")"

      for ((vr = 0; vr < vscale; vr++)); do
        printf '%s|%s%s%s%s%s|\n' "$margin_pad" "$gutter" "$left_fill" "$row_text" "$right_fill" "$gutter"
        used=$((used + 1))
      done
    done

    printf '%s+%s+\n' "$margin_pad" "$(repeat_char '-' "$inner_width")"
    used=$((used + 1))

    if [ $((start + chars_per_line)) -lt "$len" ]; then
      printf '%s%s\n' "$margin_pad" "$(build_centered_line "$(repeat_to_width '<>' "$canvas_width")" "$canvas_width" ' ')"
      used=$((used + 1))
      print_scene "$((chunk_idx + 1))" "$canvas_width" "$margin_pad"
      used=$((used + 3))
    fi

    start=$((start + chars_per_line))
    chunk_idx=$((chunk_idx + 1))
  done

  # Fill remaining screen lines with patterns
  while [ "$used" -lt $((term_lines - 1)) ]; do
    printf '%s%s\n' "$margin_pad" "$(build_centered_line "" "$canvas_width" ' ')"
    used=$((used + 1))
  done

  printf '%s%s\n' "$margin_pad" "$(build_centered_line "[ done ]" "$canvas_width" ' ')"
}

main "$@"
