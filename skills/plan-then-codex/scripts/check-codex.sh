#!/usr/bin/env bash
# check-codex.sh — plan-then-codex 사전 점검 (read-only, 아무것도 수정하지 않음)
# stdout: KEY=VALUE 형식. exit 0 = 위임 가능, exit 1 = 전제조건 미충족.
set -u

fail=0
MIN_CODEX_VERSION="0.139.0"

if command -v timeout >/dev/null 2>&1; then
  _t() { timeout "$@"; }
elif command -v gtimeout >/dev/null 2>&1; then
  _t() { gtimeout "$@"; }
else
  _t() { shift; "$@"; }
fi

version_ge() {
  IFS=. read -r a b c <<EOF
${1:-0.0.0}
EOF
  IFS=. read -r x y z <<EOF
${2:-0.0.0}
EOF
  a=${a:-0}; b=${b:-0}; c=${c:-0}; x=${x:-0}; y=${y:-0}; z=${z:-0}
  [ "$a" -gt "$x" ] || { [ "$a" -eq "$x" ] && { [ "$b" -gt "$y" ] || { [ "$b" -eq "$y" ] && [ "$c" -ge "$z" ]; }; }; }
}

# 1) Codex CLI 설치 여부
if ! command -v codex >/dev/null 2>&1; then
  echo "CODEX_INSTALLED=no"
  echo "HINT: npm install -g @openai/codex  (또는 brew install --cask codex)" >&2
  exit 1
fi
echo "CODEX_INSTALLED=yes"
CODEX_VERSION=$(_t 10 codex --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+){1,2}' | head -1 || true)
echo "CODEX_VERSION=${CODEX_VERSION:-<unknown>}"

if [ -z "$CODEX_VERSION" ] || ! version_ge "$CODEX_VERSION" "$MIN_CODEX_VERSION"; then
  echo "CODEX_VERSION_OK=no"
  echo "HINT: codex >= $MIN_CODEX_VERSION 필요. 현재 ${CODEX_VERSION:-unknown}." >&2
  fail=1
else
  echo "CODEX_VERSION_OK=yes"
fi

EXEC_HELP=$(_t 10 codex exec --help 2>&1 || true)
RESUME_HELP=$(_t 10 codex exec resume --help 2>&1 || true)
printf '%s\n' "$EXEC_HELP" | grep -q -- '-o' && echo "CODEX_EXEC_OUTPUT_FLAG=yes" || { echo "CODEX_EXEC_OUTPUT_FLAG=no"; fail=1; }
printf '%s\n' "$RESUME_HELP" | grep -q 'resume' && echo "CODEX_RESUME_HELP=yes" || { echo "CODEX_RESUME_HELP=no"; fail=1; }

# 2) 인증 상태
if _t 15 codex login status >/dev/null 2>&1; then
  echo "CODEX_AUTH=ok"
else
  LOGIN_HELP=$(_t 10 codex login --help 2>&1 || true)
  if printf '%s\n' "$LOGIN_HELP" | grep -q 'status'; then
    echo "CODEX_AUTH=missing"
    echo "HINT: 사용자에게 '! codex login' 실행을 요청할 것" >&2
  else
    echo "CODEX_AUTH=unknown(login-status-unsupported)"
    echo "HINT: codex login status 지원 여부를 확인해야 함" >&2
  fi
  fail=1
fi

# 3) config 기본값 추정 — top-level config.toml 해석일 뿐 "실효값"이 아니다.
#    (profile/override/env에 따라 달라질 수 있음 — 실효값은 codex exec 실행 배너에서 확정)
CFG="${CODEX_HOME:-$HOME/.codex}/config.toml"
if [ -f "$CFG" ]; then
  model=$(awk -F'= *' '/^model[[:space:]]*=/{gsub(/["[:space:]]/,"",$2); print $2; exit}' "$CFG")
  effort=$(awk -F'= *' '/^model_reasoning_effort[[:space:]]*=/{gsub(/["[:space:]]/,"",$2); print $2; exit}' "$CFG")
  echo "CONFIG_MODEL_ESTIMATE=${model:-<unset>}"
  echo "CONFIG_EFFORT_ESTIMATE=${effort:-<unset>}"
  echo "CONFIG_SCOPE=top-level-only"
else
  echo "CONFIG_MODEL_ESTIMATE=<no-config>"
  echo "CONFIG_EFFORT_ESTIMATE=<no-config>"
  echo "CONFIG_SCOPE=top-level-only"
fi

exit "$fail"
