#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT=""
OUT=""
COUNT=1
MODEL=""
TIMEOUT_SEC=300
ENHANCE=0
DISPLAY_OUTPUT=0
ASPECT_RATIO=""
SIZE_SPEC=""
QUALITY=""
FORMAT_SPEC=""
TRANSPARENT=0
REF_IMAGES=()
CONFIGS=()

usage() {
  cat <<'USAGE'
Usage: bash scripts/gen.sh --prompt TEXT --out PATH [options]

Options:
  --ref PATH              Reference image, repeatable.
  -n, --count N           Extract up to N distinct generated images. Default: 1.
  -m, --model MODEL       Pass a Codex model override.
  -c, --config KEY=VALUE  Pass Codex config override, repeatable.
  --aspect-ratio RATIO    Best-effort prompt hint.
  --size SIZE             Best-effort prompt hint.
  --quality LEVEL         Best-effort prompt hint.
  --format FORMAT         Best-effort prompt hint; no transcoding.
  --transparent           Request transparent background, best effort.
  --enhance               Let the image model refine the prompt.
  --display               Open output images after success when possible.
  --timeout-sec N         Use timeout(1) or gtimeout. Default: 300.
  -h, --help              Show this help.

Exit codes: 0 success, 2 bad args, 3 missing CLI, 4 bad ref, 5 codex failed,
6 no session, 7 no image payload, 8 quota/entitlement refusal suspected.
USAGE
}

bad_args() {
  echo "bad-args: $1" >&2
  exit 2
}

need_value() {
  [[ "$2" -ge 2 ]] || bad_args "$1 requires a value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt) need_value "$1" "$#"; PROMPT="$2"; shift 2 ;;
    --out) need_value "$1" "$#"; OUT="$2"; shift 2 ;;
    --ref) need_value "$1" "$#"; REF_IMAGES+=("$2"); shift 2 ;;
    -n|--count) need_value "$1" "$#"; COUNT="$2"; shift 2 ;;
    -m|--model) need_value "$1" "$#"; MODEL="$2"; shift 2 ;;
    -c|--config) need_value "$1" "$#"; CONFIGS+=("$2"); shift 2 ;;
    --aspect-ratio) need_value "$1" "$#"; ASPECT_RATIO="$2"; shift 2 ;;
    --size) need_value "$1" "$#"; SIZE_SPEC="$2"; shift 2 ;;
    --quality) need_value "$1" "$#"; QUALITY="$2"; shift 2 ;;
    --format) need_value "$1" "$#"; FORMAT_SPEC="$2"; shift 2 ;;
    --timeout-sec) need_value "$1" "$#"; TIMEOUT_SEC="$2"; shift 2 ;;
    --transparent) TRANSPARENT=1; shift ;;
    --enhance) ENHANCE=1; shift ;;
    --display) DISPLAY_OUTPUT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) bad_args "unknown option: $1" ;;
  esac
done

[[ -n "$PROMPT" ]] || bad_args "missing --prompt"
[[ -n "$OUT" ]] || bad_args "missing --out"
[[ "$COUNT" =~ ^[1-9][0-9]*$ ]] || bad_args "--count must be a positive integer"
[[ "$COUNT" -le 16 ]] || bad_args "--count must be 16 or lower"
[[ "$TIMEOUT_SEC" =~ ^[1-9][0-9]*$ ]] || bad_args "--timeout-sec must be a positive integer"

if ! command -v python3 >/dev/null 2>&1; then
  echo "missing-cli: python3 not found" >&2
  exit 3
fi

python3 "$SCRIPT_DIR/extract_image.py" --validate-out "$OUT" --count "$COUNT" || exit 2

for img in ${REF_IMAGES[@]+"${REF_IMAGES[@]}"}; do
  [[ -f "$img" ]] || { echo "ref-not-found: $img" >&2; exit 4; }
  python3 "$SCRIPT_DIR/extract_image.py" --validate-ref "$img" || exit 4
done

if ! command -v codex >/dev/null 2>&1; then
  echo "missing-cli: codex not found; run codex login after installing Codex CLI" >&2
  exit 3
fi

make_run_id() {
  if command -v uuidgen >/dev/null 2>&1; then
    printf 'img-maker-codex-%s' "$(uuidgen)"
  else
    printf 'img-maker-codex-%s-%s' "$(date +%s)" "$$"
  fi
}

RUN_ID="$(make_run_id)"
SESSIONS_ROOT="${HOME}/.codex/sessions"
before="$(mktemp)"
after="$(mktemp)"
new_sessions_file="$(mktemp)"
stdout_log="$(mktemp)"
stderr_log="$(mktemp)"
outputs_file="$(mktemp)"
trap 'rm -f "$before" "$after" "$new_sessions_file" "$stdout_log" "$stderr_log" "$outputs_file"' EXIT

snapshot_sessions() {
  if [[ -d "$SESSIONS_ROOT" ]]; then
    find "$SESSIONS_ROOT" -type f -name 'rollout-*.jsonl' -print 2>/dev/null | sort
  fi
}

build_instruction() {
  printf 'Use the image_generation tool for this img-maker-codex request.\n'
  printf 'Correlation token for extraction only: %s\n' "$RUN_ID"
  printf 'Do not render, mention, or incorporate the correlation token.\n'
  if [[ "$ENHANCE" -eq 1 ]]; then
    printf 'Enhancement is enabled: you may refine composition while preserving the user intent.\n'
  else
    printf 'Use the user prompt exactly as written. Do not translate, polish, or add unrequested style modifiers.\n'
  fi
  [[ "${#REF_IMAGES[@]}" -eq 0 ]] || printf 'Use the attached reference image(s) as visual input.\n'
  [[ "$COUNT" -le 1 ]] || printf 'Create up to %s distinct image results if supported.\n' "$COUNT"
  [[ -z "$ASPECT_RATIO" ]] || printf 'Best-effort aspect ratio: %s\n' "$ASPECT_RATIO"
  [[ -z "$SIZE_SPEC" ]] || printf 'Best-effort size: %s\n' "$SIZE_SPEC"
  [[ -z "$QUALITY" ]] || printf 'Best-effort quality: %s\n' "$QUALITY"
  [[ -z "$FORMAT_SPEC" ]] || printf 'Best-effort output format: %s\n' "$FORMAT_SPEC"
  [[ "$TRANSPARENT" -eq 0 ]] || printf 'Best-effort transparent background: true\n'
  printf '\nUSER_PROMPT_BEGIN\n%s\nUSER_PROMPT_END\n' "$PROMPT"
}

classify_refusal() {
  if grep -Eiq 'quota|entitlement|not entitled|usage limit|rate limit|plan|upgrade|forbidden|unauthorized|image_generation.*(disabled|unavailable|not available)|image generation.*(disabled|unavailable|not available)' "$stderr_log"; then
    echo "quota-or-entitlement-refused?: Codex appears to have declined image generation; check codex login and plan access" >&2
    exit 8
  fi
}

snapshot_sessions > "$before"
codex_args=(exec --skip-git-repo-check --color never --enable image_generation --sandbox read-only)
[[ -z "$MODEL" ]] || codex_args+=(-m "$MODEL")
for cfg in ${CONFIGS[@]+"${CONFIGS[@]}"}; do codex_args+=(-c "$cfg"); done
for img in ${REF_IMAGES[@]+"${REF_IMAGES[@]}"}; do codex_args+=(-i "$img"); done

instruction="$(build_instruction)"
set +e
if command -v timeout >/dev/null 2>&1; then
  printf '%s\n' "$instruction" | timeout "$TIMEOUT_SEC" codex "${codex_args[@]}" >"$stdout_log" 2>"$stderr_log"
elif command -v gtimeout >/dev/null 2>&1; then
  printf '%s\n' "$instruction" | gtimeout "$TIMEOUT_SEC" codex "${codex_args[@]}" >"$stdout_log" 2>"$stderr_log"
else
  printf '%s\n' "$instruction" | codex "${codex_args[@]}" >"$stdout_log" 2>"$stderr_log"
fi
codex_rc=$?
set -e

if [[ "$codex_rc" -ne 0 ]]; then
  classify_refusal
  echo "codex-exec-failed: codex exec exited with status $codex_rc" >&2
  exit 5
fi

snapshot_sessions > "$after"
comm -13 "$before" "$after" > "$new_sessions_file" || true
if [[ ! -s "$new_sessions_file" ]]; then
  echo "no-session: codex completed but no new rollout JSONL was created" >&2
  exit 6
fi

extract_args=(--out "$OUT" --sessions-list "$new_sessions_file" --prompt "$PROMPT" --run-id "$RUN_ID" --model "${MODEL:-codex default}" --count "$COUNT")
for img in ${REF_IMAGES[@]+"${REF_IMAGES[@]}"}; do extract_args+=(--ref "$img"); done

set +e
python3 "$SCRIPT_DIR/extract_image.py" "${extract_args[@]}" >"$outputs_file"
extract_rc=$?
set -e

if [[ "$extract_rc" -ne 0 ]]; then
  classify_refusal
  if [[ "$extract_rc" -eq 6 ]]; then
    echo "no-session: no session rollout paths were available to parse" >&2
    exit 6
  fi
  if [[ "$extract_rc" -eq 8 ]]; then
    echo "quota-or-entitlement-refused?: Codex appears to have declined image generation; check codex login and plan access" >&2
    exit 8
  fi
  echo "no-image-payload: no structured image_generation result was found for this run" >&2
  exit 7
fi

cat "$outputs_file"

if [[ "$DISPLAY_OUTPUT" -eq 1 ]]; then
  while IFS= read -r image_path; do
    [[ -n "$image_path" ]] || continue
    if command -v open >/dev/null 2>&1; then
      open "$image_path" >/dev/null 2>&1 || true
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$image_path" >/dev/null 2>&1 || true
    fi
  done < "$outputs_file"
fi
