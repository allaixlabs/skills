#!/usr/bin/env bash
# check-omo.sh — plan-then-opencode 사전 점검 (read-only, 아무것도 수정하지 않음)
# stdout: KEY=VALUE 형식. exit 0 = 위임 가능, exit 1 = 전제조건 미충족.
set -u

fail=0

# 1) omo / oh-my-openagent 설치 여부
if command -v omo >/dev/null 2>&1; then
  OMO_BIN="omo"
  echo "OMO_BIN=omo"
  echo "OMO_VERSION=$(omo --version 2>/dev/null | tr -d '[:space:]' || echo '<unknown>')"
elif command -v bunx >/dev/null 2>&1; then
  OMO_BIN="bunx oh-my-openagent"
  echo "OMO_BIN=bunx oh-my-openagent"
  echo "OMO_VERSION=<bunx-resolved>"
  echo "HINT: 'omo' 별칭이 없어 bunx를 씁니다. 'npm i -g oh-my-openagent'로 단축 명령 설치 가능." >&2
else
  echo "OMO_INSTALLED=no"
  echo "HINT: bunx 또는 bun이 필요합니다. https://bun.sh 설치 후 'bunx oh-my-openagent install'" >&2
  exit 1
fi
echo "OMO_INSTALLED=yes"

# 2) opencode 설치 여부 및 버전
if ! command -v opencode >/dev/null 2>&1; then
  echo "OPENCODE_INSTALLED=no"
  echo "HINT: npm install -g opencode  (또는 brew install opencode)" >&2
  exit 1
fi
echo "OPENCODE_INSTALLED=yes"
OC_VERSION=$(opencode --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")
echo "OPENCODE_VERSION=$OC_VERSION"

# opencode >= 1.4.0 요구 (oh-my-openagent doctor 기준)
OC_MAJOR=$(echo "$OC_VERSION" | cut -d. -f1)
OC_MINOR=$(echo "$OC_VERSION" | cut -d. -f2)
if [ "$OC_MAJOR" -lt 1 ] || { [ "$OC_MAJOR" -eq 1 ] && [ "$OC_MINOR" -lt 4 ]; }; then
  echo "OPENCODE_VERSION_OK=no"
  echo "HINT: opencode >= 1.4.0 필요. 현재 $OC_VERSION. 'opencode upgrade' 실행." >&2
  fail=1
else
  echo "OPENCODE_VERSION_OK=yes"
fi

# 3) oh-my-openagent 플러그인 등록 확인 (opencode.json 또는 config.json)
OC_CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
PLUGIN_OK=no
for cfg in "$OC_CFG_DIR/opencode.json" "$OC_CFG_DIR/config.json" "$(pwd)/opencode.json" "$(pwd)/.opencode/opencode.json"; do
  if [ -f "$cfg" ] && grep -qE '"oh-my-openagent"|"oh-my-opencode"' "$cfg" 2>/dev/null; then
    PLUGIN_OK=yes
    echo "OMO_PLUGIN_REGISTERED=yes (in $cfg)"
    break
  fi
done
if [ "$PLUGIN_OK" = "no" ]; then
  echo "OMO_PLUGIN_REGISTERED=no"
  echo "HINT: oh-my-openagent가 opencode에 등록되지 않았습니다. '! bunx oh-my-openagent install' 실행." >&2
  fail=1
fi

# 4) opencode 인증 상태 (간접 확인 — providers 목록으로 판단)
if opencode providers 2>&1 | grep -qiE 'authenticated|api.key|provider'; then
  echo "OPENCODE_AUTH=ok"
else
  echo "OPENCODE_AUTH=unknown"
  echo "HINT: 'opencode providers' 로 인증 상태를 확인하세요." >&2
fi

exit "$fail"
