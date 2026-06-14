#!/usr/bin/env bash
# check-panels.sh — plan-codex-opencode 사전 점검 (read-only, 아무것도 수정하지 않음)
#
# 멀티모델 패널: codex(GPT) 백엔드 + opencode/omo(GLM·Kimi·DeepSeek·…) 백엔드의
# 가용성과 "프로바이더 인증 매트릭스"를 한 번에 점검한다.
# plan-then-codex/check-codex.sh + plan-then-opencode/check-omo.sh 로직을 통합.
#
# stdout: KEY=VALUE. exit 0 = 최소 1개 백엔드 위임 가능, exit 1 = 전부 불가.
set -u

codex_ok=0
opencode_ok=0

echo "# ── codex 백엔드 (OpenAI / GPT) ─────────────────────────"
if command -v codex >/dev/null 2>&1; then
  echo "CODEX_INSTALLED=yes"
  echo "CODEX_VERSION=$(codex --version 2>/dev/null | awk '{print $NF}')"
  if codex login status >/dev/null 2>&1; then
    echo "CODEX_AUTH=ok"
    codex_ok=1
  else
    echo "CODEX_AUTH=missing"
    echo "HINT: 사용자에게 '! codex login' 실행을 요청할 것" >&2
  fi
  # config 기본값은 top-level config.toml 해석일 뿐 "실효값"이 아니다
  # (profile/override/env에 따라 달라짐 — 실효값은 codex exec 실행 배너에서 확정).
  CFG="${CODEX_HOME:-$HOME/.codex}/config.toml"
  if [ -f "$CFG" ]; then
    model=$(awk -F'= *' '/^model[[:space:]]*=/{gsub(/["[:space:]]/,"",$2); print $2; exit}' "$CFG")
    effort=$(awk -F'= *' '/^model_reasoning_effort[[:space:]]*=/{gsub(/["[:space:]]/,"",$2); print $2; exit}' "$CFG")
    echo "CODEX_CONFIG_MODEL=${model:-<unset>}"
    echo "CODEX_CONFIG_EFFORT=${effort:-<unset>}"
  else
    echo "CODEX_CONFIG_MODEL=<no-config>"
    echo "CODEX_CONFIG_EFFORT=<no-config>"
  fi
else
  echo "CODEX_INSTALLED=no"
  echo "HINT: npm install -g @openai/codex  (또는 brew install --cask codex)" >&2
fi

echo "# ── opencode 백엔드 (omo run / opencode run 직접) ───────"
# omo 바이너리 (omo run 경로용 — Sisyphus 오케스트레이션·완수보장)
if command -v omo >/dev/null 2>&1; then
  echo "OMO_BIN=omo"
  echo "OMO_VERSION=$(omo --version 2>/dev/null | tr -d '[:space:]' || echo '<unknown>')"
elif command -v bunx >/dev/null 2>&1; then
  echo "OMO_BIN=bunx oh-my-openagent"
  echo "OMO_VERSION=<bunx-resolved>"
  echo "HINT: 'omo' 별칭이 없어 bunx를 씁니다. 'npm i -g oh-my-openagent'로 단축 명령 설치 가능." >&2
else
  echo "OMO_BIN=<none>"
  echo "HINT: omo run 경로엔 bunx/bun 필요. opencode run 직접 경로는 omo 없이도 동작." >&2
fi

# opencode 설치/버전 (omo·opencode 직접 두 경로 공통 전제)
OC_INSTALLED=0
PROV=""
if command -v opencode >/dev/null 2>&1; then
  echo "OPENCODE_INSTALLED=yes"
  OC_VERSION=$(opencode --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")
  echo "OPENCODE_VERSION=$OC_VERSION"
  OC_MAJOR=$(echo "$OC_VERSION" | cut -d. -f1); OC_MAJOR=${OC_MAJOR:-0}
  OC_MINOR=$(echo "$OC_VERSION" | cut -d. -f2); OC_MINOR=${OC_MINOR:-0}
  if [ "$OC_MAJOR" -lt 1 ] || { [ "$OC_MAJOR" -eq 1 ] && [ "$OC_MINOR" -lt 4 ]; }; then
    echo "OPENCODE_VERSION_OK=no"
    echo "HINT: opencode >= 1.4.0 필요. 현재 $OC_VERSION. 'opencode upgrade' 실행." >&2
  else
    echo "OPENCODE_VERSION_OK=yes"
    OC_INSTALLED=1
  fi
else
  echo "OPENCODE_INSTALLED=no"
  echo "HINT: npm install -g opencode  (또는 brew install opencode)" >&2
fi

# 프로바이더 인증 매트릭스 — 패널에 호명된 provider가 인증돼 있는지 0단계에서 확인.
# (omo·opencode 직접 두 경로 모두 이 opencode 자격을 공유)
if [ "$OC_INSTALLED" = "1" ]; then
  PROV=$(opencode providers list 2>/dev/null || echo "")
  check_prov() {  # $1=표시키 $2=grep 패턴 (인증된 provider는 ●로 표시됨)
    if printf '%s\n' "$PROV" | grep -qiE "●.*($2)"; then
      echo "PROVIDER_$1=ok"
    else
      echo "PROVIDER_$1=none"
    fi
  }
  check_prov OPENAI       'OpenAI'
  check_prov ZAI          'Z\.?AI'
  check_prov OPENCODE_GO  'OpenCode Go'
  check_prov DGRID        'dgrid'
  if printf '%s\n' "$PROV" | grep -qE '●'; then
    echo "OPENCODE_AUTH=ok"
    opencode_ok=1
  else
    echo "OPENCODE_AUTH=none_configured"
    echo "HINT: 'opencode providers login' 으로 프로바이더를 설정하세요." >&2
  fi
else
  echo "OPENCODE_AUTH=unknown(opencode-missing)"
fi

# oh-my-openagent 플러그인 등록 (omo run 경로에서만 필요 — opencode 직접 경로는 불필요)
OC_CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
PLUGIN_OK=no
for cfg in "$OC_CFG_DIR/opencode.json" "$OC_CFG_DIR/config.json" "$(pwd)/opencode.json" "$(pwd)/.opencode/opencode.json"; do
  if [ -f "$cfg" ] && grep -qE '"oh-my-openagent"|"oh-my-opencode"' "$cfg" 2>/dev/null; then
    PLUGIN_OK=yes
    echo "OMO_PLUGIN_REGISTERED=yes ($cfg)"
    break
  fi
done
if [ "$PLUGIN_OK" = "no" ]; then
  echo "OMO_PLUGIN_REGISTERED=no"
  echo "HINT: omo run 경로를 쓰려면 '! bunx oh-my-openagent install' 실행 (opencode 직접 경로는 불필요)." >&2
fi

echo "# ── 종합 ────────────────────────────────────────────────"
echo "CODEX_BACKEND_READY=$([ "$codex_ok" = 1 ] && echo yes || echo no)"
echo "OPENCODE_BACKEND_READY=$([ "$opencode_ok" = 1 ] && echo yes || echo no)"

if [ "$codex_ok" = 1 ] && [ "$opencode_ok" = 1 ]; then
  echo "PANEL_CAPABILITY=full(2 backends)"
  exit 0
elif [ "$codex_ok" = 1 ] || [ "$opencode_ok" = 1 ]; then
  echo "PANEL_CAPABILITY=partial(1 backend)"
  echo "HINT: 1개 백엔드만 가용. 교차검증(council)은 백엔드 1개라도 그 안의 여러 모델(예: glm+kimi)로 가능하나, 서로 다른 패밀리 확보를 위해 2개 백엔드 권장." >&2
  exit 0
else
  echo "PANEL_CAPABILITY=none"
  echo "HINT: 위임 가능한 백엔드가 없습니다. codex 또는 opencode 중 최소 하나를 설정하세요." >&2
  exit 1
fi
