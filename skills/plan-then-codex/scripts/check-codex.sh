#!/usr/bin/env bash
# check-codex.sh — plan-then-codex 사전 점검 (프로젝트를 수정하지 않음; /tmp 작업 폴더만 생성)
# stdout: KEY=VALUE 형식. exit 0 = 위임 가능, exit 1 = 전제조건 미충족.
set -u

fail=0

# 1) Codex CLI 설치 여부
if ! command -v codex >/dev/null 2>&1; then
  echo "CODEX_INSTALLED=no"
  echo "HINT: npm install -g @openai/codex  (또는 brew install --cask codex)" >&2
  exit 1
fi
echo "CODEX_INSTALLED=yes"
echo "CODEX_VERSION=$(codex --version 2>/dev/null | awk '{print $NF}')"

# 2) 인증 상태
if codex login status >/dev/null 2>&1; then
  echo "CODEX_AUTH=ok"
else
  echo "CODEX_AUTH=missing"
  echo "HINT: 사용자에게 '! codex login' 실행을 요청할 것" >&2
  fail=1
fi

# 3) config 기본값 (model / effort) — 플래그 생략 시 적용될 값
CFG="${CODEX_HOME:-$HOME/.codex}/config.toml"
if [ -f "$CFG" ]; then
  model=$(awk -F'= *' '/^model[[:space:]]*=/{gsub(/["[:space:]]/,"",$2); print $2; exit}' "$CFG")
  effort=$(awk -F'= *' '/^model_reasoning_effort[[:space:]]*=/{gsub(/["[:space:]]/,"",$2); print $2; exit}' "$CFG")
  echo "DEFAULT_MODEL=${model:-<unset>}"
  echo "DEFAULT_EFFORT=${effort:-<unset>}"
else
  echo "DEFAULT_MODEL=<no-config>"
  echo "DEFAULT_EFFORT=<no-config>"
fi

# 4) 작업 디렉터리 준비
mkdir -p /tmp/codex-handoff 2>/dev/null && echo "HANDOFF_DIR=/tmp/codex-handoff"

exit "$fail"
