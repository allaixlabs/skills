#!/usr/bin/env bash
# check-panels.sh — plan-codex-opencode 사전 점검 (read-only, 아무것도 수정하지 않음)
#
# 멀티모델 패널: codex(GPT) 백엔드 + opencode/omo(GLM·Kimi·DeepSeek·…) 백엔드의
# 가용성과 "프로바이더 인증 매트릭스"를 한 번에 점검한다.
# plan-then-codex/check-codex.sh + plan-then-opencode/check-omo.sh 로직을 통합.
#
# stdout: KEY=VALUE. exit 0 = 최소 1개 백엔드 위임 가능, exit 1 = 전부 불가.
set -u


# 외부 CLI 호출용 타임아웃 래퍼: timeout/gtimeout 있으면 사용, 없으면(macOS 기본 등) 직접 실행.
# 사용: _t <초> <cmd> [args...] — 네트워크/키체인/권한 지연으로 사전점검이 행하는 것 방지.
if command -v timeout  >/dev/null 2>&1; then _t() { timeout  "$@"; }
elif command -v gtimeout >/dev/null 2>&1; then _t() { gtimeout "$@"; }
else _t() { shift; "$@"; }; fi

codex_ok=0
opencode_ok=0

echo "# ── codex 백엔드 (OpenAI / GPT) ─────────────────────────"
if command -v codex >/dev/null 2>&1; then
  echo "CODEX_INSTALLED=yes"
  echo "CODEX_VERSION=$(codex --version 2>/dev/null | awk '{print $NF}')"
  if _t 15 codex login status >/dev/null 2>&1; then
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
OMO_RUN_BIN=""
if command -v omo >/dev/null 2>&1; then
  OMO_RUN_BIN="omo"
  echo "OMO_BIN=omo"
  echo "OMO_VERSION=$(omo --version 2>/dev/null | tr -d '[:space:]' || echo '<unknown>')"
elif command -v bunx >/dev/null 2>&1; then
  OMO_RUN_BIN="bunx oh-my-openagent"
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
    echo "OPENCODE_FLAGS_VERIFIED=no"
    echo "HINT: opencode >= 1.4.0 필요. 현재 $OC_VERSION. 'opencode upgrade' 실행." >&2
  else
    echo "OPENCODE_VERSION_OK=yes"
    OC_INSTALLED=1
    OC_RUN_HELP=$(_t 10 opencode run --help 2>&1 || _t 10 opencode --help 2>&1 || echo "")
    if printf '%s\n' "$OC_RUN_HELP" | grep -q -- '--variant' && printf '%s\n' "$OC_RUN_HELP" | grep -q -- '--format'; then
      echo "OPENCODE_FLAGS_VERIFIED=yes"
    else
      echo "OPENCODE_FLAGS_VERIFIED=no"
      echo "WARN: opencode $OC_VERSION >=1.4지만 --variant/--format 플래그를 help에서 확인하지 못했습니다. 1.16+ 업그레이드 권장." >&2
    fi
  fi
else
  echo "OPENCODE_INSTALLED=no"
  echo "OPENCODE_FLAGS_VERIFIED=no"
  echo "HINT: npm install -g opencode  (또는 brew install opencode)" >&2
fi

# 프로바이더 인증 매트릭스 — 패널에 호명된 provider가 인증돼 있는지 0단계에서 확인.
# (omo·opencode 직접 두 경로 모두 이 opencode 자격을 공유)
if [ "$OC_INSTALLED" = "1" ]; then
  PROV=$(_t 15 opencode providers list 2>/dev/null || echo "")
  AUTH_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"
  AUTH_KEYS=""
  # 포맷 무관 추출: jq(있으면) 최상위 키 → minified/pretty 모두 안전. 줄앵커 sed는 minified JSON에서 0개 추출.
  if [ -s "$AUTH_FILE" ]; then
    command -v jq >/dev/null 2>&1 && AUTH_KEYS=$(jq -r 'keys[]?' "$AUTH_FILE" 2>/dev/null | tr '\n' ' ')
    # jq 없거나 비표준이면 grep 폴백 — 줄앵커 없이 키 패턴을 직접 잡아 minified에도 견딘다(과매칭은 무해).
    [ -n "$AUTH_KEYS" ] || AUTH_KEYS=$(grep -oE '"[A-Za-z0-9_.-]+"[[:space:]]*:' "$AUTH_FILE" 2>/dev/null | tr -d '": ' | tr '\n' ' ')
  fi
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
  # 인증 판정: ● 마커 또는 알려진 provider 키(zai/opencode-go/openai/dgrid/anthropic)가 있을 때만 ok.
  # 알려진 키가 아닌 임의 키나 마커 누락은 ok로 승격하지 않는다(fail-open 제거) — 보수적으로 false.
  if printf '%s\n' "$PROV" | grep -qE '●'; then
    echo "OPENCODE_AUTH=ok"
    opencode_ok=1
  elif printf '%s' "$AUTH_KEYS" | grep -qiE 'zai|opencode-go|openai|dgrid|anthropic'; then
    echo "OPENCODE_AUTH=ok(auth-file: 알려진 provider 키)"
    opencode_ok=1
  elif [ -n "$AUTH_KEYS" ]; then
    echo "OPENCODE_AUTH=unknown(auth-file: 알려진 provider 키 없음)"
    echo "OPENCODE_READY_CONFIDENCE=low"
    echo "WARN: auth.json에 키는 있으나 zai/opencode-go/openai 등 알려진 provider가 아님 — 기본 패널 인증 불확실." >&2
  elif printf '%s\n' "$PROV" | grep -qiE '0 credentials|no credentials|not logged in'; then
    echo "OPENCODE_AUTH=none_configured"
    echo "HINT: 'opencode providers login' 으로 프로바이더를 설정하세요." >&2
  elif [ -n "$PROV" ]; then
    echo "OPENCODE_AUTH=unknown(marker-missing)"
    echo "OPENCODE_READY_CONFIDENCE=low"
    echo "WARN: opencode provider 출력에서 인증 마커(●)를 확인하지 못했습니다 — ready로 집계하지 않고 보수적으로 미가용 처리." >&2
  else
    echo "OPENCODE_AUTH=unknown(provider-list-empty)"
    echo "WARN: opencode providers list 출력이 비어 인증 상태를 판정하지 못했습니다." >&2
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

# omo run(Sisyphus 완수보장) 경로 가용성 — opencode 인증 + 플러그인 등록 + omo 바이너리 모두 필요.
# 미준비여도 opencode run 직접 경로는 동작하므로, 백엔드 가용성(위)과 분리해 신호한다.
# OMO_RUN_BIN은 omo 직접 또는 bunx oh-my-openagent 폴백 — command -v omo만 보면 false negative.
if [ "$opencode_ok" = 1 ] && [ "$PLUGIN_OK" = yes ] && [ -n "$OMO_RUN_BIN" ]; then
  echo "OMO_RUN_READY=yes"
else
  echo "OMO_RUN_READY=no"
  echo "HINT: omo run(완수보장) 경로 미준비 — 구현 단계는 opencode run 직접 경로로 폴백하거나, '! bunx oh-my-openagent install'로 플러그인 등록 후 재점검." >&2
fi

# Council quorum = 생존 모델 패밀리 ≥2. 판정 기준은 백엔드 개수가 아니라 패밀리 수다:
# codex(GPT)와 opencode(GLM/Kimi 등)는 서로 다른 패밀리. opencode 단독이라도 그 안의 다중 모델(glm+kimi)로
# 2패밀리 Council이 성립할 수 있다(이 스크립트는 모델 다양성까지는 검증 못함 — 런타임에서 확정).
# exit 코드는 가용성 우선(≥1 백엔드면 exit 0, 차단하지 않음). 단 1패밀리만 생존하면 Council 미성립으로 안내.
if [ "$codex_ok" = 1 ] && [ "$opencode_ok" = 1 ]; then
  echo "PANEL_CAPABILITY=full(≥2 families: codex(GPT) + opencode)"
  exit 0
elif [ "$codex_ok" = 1 ]; then
  echo "PANEL_CAPABILITY=single-family(codex/GPT만 — Council 미성립)"
  echo "HINT: 단일 모델 패밀리뿐이라 교차검증 독립성이 성립하지 않습니다. Council 대신 plan-then-codex(단일 위임)를 쓰거나, opencode를 설정해 다른 패밀리를 확보하세요." >&2
  exit 0
elif [ "$opencode_ok" = 1 ]; then
  echo "PANEL_CAPABILITY=conditional(opencode 단독 — 다중 패밀리(glm+kimi)면 Council 성립, 단일 모델이면 미성립)"
  echo "HINT: opencode 안의 서로 다른 패밀리(예: glm+kimi)로 Council 독립성을 확보할 수 있습니다. 모델이 1개뿐이면 plan-then-opencode(단일 위임) 권장. codex(GPT) 추가 시 패밀리 다양성↑." >&2
  exit 0
else
  echo "PANEL_CAPABILITY=none"
  echo "HINT: 위임 가능한 백엔드가 없습니다. codex 또는 opencode 중 최소 하나를 설정하세요." >&2
  exit 1
fi
