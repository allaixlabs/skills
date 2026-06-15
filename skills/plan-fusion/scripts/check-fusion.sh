#!/usr/bin/env bash
# check-fusion.sh — plan-fusion 사전 점검 (read-only, 아무것도 수정하지 않음)
#
# CLI Fusion: 서로 다른 모델 패밀리를 각자 CLI로 독립 실행한다.
#   GPT    → codex exec
#   Gemini → agy --print            (신규 백엔드)
#   GLM/Kimi/DeepSeek/… → opencode run / omo run
#   Opus   → claude --print         (Judge·선택적 참가자)
# 각 백엔드 가용성 + 프로바이더 인증 매트릭스 + Judge/Synth 후보를 한 번에 점검한다.
# plan-codex-opencode/check-panels.sh 를 확장(agy·claude 추가)했다.
#
# stdout: 사람이 읽는 KEY=VALUE (값에 공백/괄호 포함 가능 — 엄격한 cut -d= 파싱은 비전제).
#   exit 0 = 위임 가능 독립 백엔드 ≥2 (Fusion 성립), exit 1 = <2 (교차 합성 불가).
set -u

# agy 는 zsh 함수로 래핑될 수 있다(.zshrc). bash 스크립트에선 함수 미로드 → 바이너리를 직접 찾는다.
# 일반 설치 경로 보강(macOS Apple Silicon/Intel·Linuxbrew). ${PATH:-}로 set -u 가드.
for _p in /opt/homebrew/bin /usr/local/bin /home/linuxbrew/.linuxbrew/bin; do
  case ":${PATH:-}:" in *":$_p:"*) ;; *) [ -d "$_p" ] && PATH="$_p:${PATH:-}" ;; esac
done

# 외부 CLI 호출용 타임아웃 래퍼: timeout/gtimeout 있으면 사용, 없으면(macOS 기본 등) 직접 실행.
# 사용: _t <초> <cmd> [args...] — 네트워크/키체인/권한 지연으로 사전점검이 행되는 것 방지.
if command -v timeout  >/dev/null 2>&1; then _t() { timeout  "$@"; }
elif command -v gtimeout >/dev/null 2>&1; then _t() { gtimeout "$@"; }
else _t() { shift; "$@"; }; fi

codex_ok=0
opencode_ok=0
agy_ok=0
claude_ok=0

echo "# ── codex 백엔드 (OpenAI / GPT) — 참가자 + 기본 Synthesizer ─"
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

echo "# ── agy 백엔드 (Google / Gemini) — 신규 참가자 백엔드 ──────"
# agy: Antigravity CLI. 함수 래핑을 피해 'command agy'로 호출(바이너리 직접).
if command -v agy >/dev/null 2>&1 || [ -x /opt/homebrew/bin/agy ]; then
  echo "AGY_INSTALLED=yes"
  AGY_VER=$(command agy --version </dev/null 2>/dev/null | head -1 | tr -d '[:space:]')
  echo "AGY_VERSION=${AGY_VER:-<unknown>}"
  # 인증/응답 프록시: 'agy models'가 알려진 모델명을 반환하면 ready로 본다.
  # (진짜 인증은 첫 --print에서 확정 — 사전점검에서 토큰 소모 호출은 피한다.)
  AGY_MODELS=$(_t 25 agy models </dev/null 2>/dev/null)
  if printf '%s\n' "$AGY_MODELS" | grep -qiE 'Gemini'; then
    echo "AGY_AUTH=ok"
    echo "AGY_MODELS_SAMPLE=$(printf '%s' "$AGY_MODELS" | grep -iE 'Gemini' | head -3 | paste -sd'|' -)"
    # 기본 패널 모델이 실제 존재하는지(샘플 head -3는 정렬상 Flash만 보일 수 있어 별도 확인).
    echo "AGY_DEFAULT_MODEL_PRESENT=$(printf '%s\n' "$AGY_MODELS" | grep -qiF 'Gemini 3.1 Pro (High)' && echo yes || echo no)"
    agy_ok=1
  else
    echo "AGY_AUTH=unknown(models-empty)"
    echo "WARN: 'agy models'가 Gemini 목록을 반환하지 않음 — 인증/로그인 상태 확인('! agy' 인터랙티브 로그인)." >&2
  fi
else
  echo "AGY_INSTALLED=no"
  echo "HINT: Antigravity CLI 미설치. agy 패널은 건너뛴다(Gemini 패밀리 제외)." >&2
fi

echo "# ── claude 백엔드 (Anthropic / Opus) — 기본 Judge ─────────"
# ⚠️ 동족 주의: 오케스트레이터가 Opus다. Opus를 참가자로도 쓰면 Judge=참가자=오케스트레이터가
#    같은 패밀리 → 교차검증 독립성↓·확증편향. 기본은 Judge 전용 권장(라우팅 문서 참조).
if command -v claude >/dev/null 2>&1; then
  echo "CLAUDE_INSTALLED=yes"
  echo "CLAUDE_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  echo "CLAUDE_AUTH=assumed-ok(설치만 확인 — 실제 인증/계정은 첫 --print에서 확정, 실패 시 Judge 폴백)"
  claude_ok=1
else
  echo "CLAUDE_INSTALLED=no"
  echo "HINT: 'claude' CLI 미발견 — Judge는 다른 패밀리로 폴백하거나 Claude 오케스트레이터가 직접 판정." >&2
fi

echo "# ── opencode 백엔드 (GLM / Kimi / DeepSeek / …) ──────────"
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

if [ "$OC_INSTALLED" = "1" ]; then
  PROV=$(_t 15 opencode providers list 2>/dev/null || echo "")
  AUTH_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"
  AUTH_KEYS=""
  [ -s "$AUTH_FILE" ] && AUTH_KEYS=$(sed -n 's/^[[:space:]]*"\([^"]*\)".*/\1/p' "$AUTH_FILE" | tr '\n' ' ')
  check_prov() {
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
  printf '%s\n' "$PROV" | grep -qiE '●.*(Z\.?AI)' || echo "HINT: default GLM 패널 불가 — PROVIDER_ZAI=none 또는 미인증(zai provider 로그인 필요)." >&2
  printf '%s\n' "$PROV" | grep -qiE '●.*(OpenCode Go)' || echo "HINT: default Kimi 패널 불가 — PROVIDER_OPENCODE_GO=none 또는 미인증(opencode-go provider 로그인 필요)." >&2
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
    opencode_ok=1
  elif printf '%s\n' "$PROV" | grep -qiE '0 credentials|no credentials|not logged in'; then
    echo "OPENCODE_AUTH=none_configured"
    echo "HINT: 'opencode providers login' 으로 프로바이더를 설정하세요." >&2
  elif [ -n "$PROV" ]; then
    echo "OPENCODE_AUTH=unknown(marker-missing)"
    echo "OPENCODE_READY_CONFIDENCE=low"
    echo "WARN: opencode provider 출력에서 인증 마커(●)를 확인하지 못했습니다 — ready로 집계하나 신뢰도 낮음." >&2
    opencode_ok=1
  else
    echo "OPENCODE_AUTH=unknown(provider-list-empty)"
    echo "WARN: opencode providers list 출력이 비어 인증 상태를 판정하지 못했습니다." >&2
  fi
else
  echo "OPENCODE_AUTH=unknown(opencode-missing)"
fi

# oh-my-openagent 플러그인 등록 (omo run 경로에서만 필요)
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

echo "# ── council-worktrees.sh 동기화 점검 (정본↔복제본 — 심링크 대신 실파일 복제) ──"
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
CANON_WT="$SELF_DIR/../../plan-codex-opencode/scripts/council-worktrees.sh"
if [ -f "$CANON_WT" ] && [ -f "$SELF_DIR/council-worktrees.sh" ]; then
  if cmp -s "$SELF_DIR/council-worktrees.sh" "$CANON_WT"; then
    echo "COUNCIL_WT_SYNC=ok"
  else
    echo "COUNCIL_WT_SYNC=DRIFT"
    echo "WARN: council-worktrees.sh가 정본(plan-codex-opencode)과 다릅니다 — 정본에서 수정 후 복사해 동기화하세요." >&2
  fi
else
  echo "COUNCIL_WT_SYNC=standalone(정본 미발견 — 복제본 단독 사용)"
fi

echo "# ── 종합 (Fusion 가용성) ────────────────────────────────"
echo "CODEX_BACKEND_READY=$([ "$codex_ok" = 1 ] && echo yes || echo no)"
echo "AGY_BACKEND_READY=$([ "$agy_ok" = 1 ] && echo yes || echo no)"
echo "OPENCODE_BACKEND_READY=$([ "$opencode_ok" = 1 ] && echo yes || echo no)"
echo "CLAUDE_BACKEND_READY=$([ "$claude_ok" = 1 ] && echo yes || echo no)"

if [ "$opencode_ok" = 1 ] && [ "$PLUGIN_OK" = yes ] && command -v omo >/dev/null 2>&1; then
  echo "OMO_RUN_READY=yes"
else
  echo "OMO_RUN_READY=no"
  echo "HINT: omo run(완수보장) 경로 미준비 — 구현 단계는 opencode run 직접 경로로 폴백 가능." >&2
fi

# 참가자 백엔드 수 = 교차검증 독립성의 핵심. codex(GPT)·agy(Gemini)·opencode(GLM/Kimi 생태계)를 센다.
# claude(Opus)는 기본 Judge 전용이라 참가자 백엔드 카운트에서 제외(동족 주의) — 단 가용은 표기.
families=0
[ "$codex_ok" = 1 ]    && families=$((families+1))
[ "$agy_ok" = 1 ]      && families=$((families+1))
[ "$opencode_ok" = 1 ] && families=$((families+1))
echo "PARTICIPANT_FAMILIES=$families (codex/agy/opencode 중 ready 백엔드 수 — GLM·Kimi 등 동일 opencode 모델은 1로 집계; 모델 다양성 ≠ 백엔드 다양성; claude는 기본 Judge 전용이라 제외)"
# claude(Opus)는 기본 Judge 전용이라 families에서 제외하지만, highEnd/codeSecurity 등 Opus가 '참가자'인
# 프리셋에선 독립 백엔드(GPT vs Opus는 서로 다른 패밀리)로 쓸 수 있다. 차단 판정엔 이를 포함한 값을 쓴다.
# (claude를 참가자로 쓰면 Judge는 비-claude로 — JUDGE_DEFAULT 폴백 참조.)
effective=$families
[ "$claude_ok" = 1 ] && effective=$((effective+1))
echo "EFFECTIVE_BACKENDS=$effective (participant families + claude-as-participant 후보)"

# Judge/Synth 후보 신호
echo "JUDGE_DEFAULT=$([ "$claude_ok" = 1 ] && echo 'claude(Opus)' || { [ "$codex_ok" = 1 ] && echo 'codex(GPT) fallback' || echo 'Claude-orchestrator self'; })"
echo "SYNTH_DEFAULT=$([ "$codex_ok" = 1 ] && echo 'codex(GPT)' || { [ "$claude_ok" = 1 ] && echo 'claude(Opus) fallback' || echo 'best-participant'; })"

# 차단 판정은 EFFECTIVE_BACKENDS 기준(codex+claude처럼 families=1이라도 독립 2백엔드면 Fusion 성립).
if [ "$effective" -ge 2 ]; then
  echo "FUSION_CAPABILITY=full(participant=$families, effective=$effective)"
  exit 0
elif [ "$effective" -eq 1 ]; then
  echo "FUSION_CAPABILITY=degraded(1 backend)"
  echo "HINT: 위임 가능한 독립 백엔드가 1개뿐 — CLI Fusion의 교차검증 독립성이 성립하지 않습니다. 단일 위임이면" >&2
  echo "      plan-then-codex/plan-then-opencode를, 2 백엔드 확보가 목표면 누락 백엔드를 설정하세요." >&2
  exit 1
else
  echo "FUSION_CAPABILITY=none"
  echo "HINT: 위임 가능한 백엔드가 없습니다. codex·agy·opencode·claude 중 최소 2개를 설정하세요." >&2
  exit 1
fi
