#!/usr/bin/env bash
# check-fusion.sh — plan-fusion 사전 점검 (read-only, 아무것도 수정하지 않음)
#
# CLI Fusion: 서로 다른 모델 패밀리를 각자 CLI로 독립 실행한다.
#   GPT    → codex exec
#   Gemini → agy -p                     (agy 1.0.10: --add-dir 스코프 제한 + 프롬프트 파일 참조 절대경로 — routing-fusion.md 특이사항)
#   GLM/Kimi/DeepSeek/… → opencode run / omo run
#   Opus   → claude --print         (Judge·선택적 참가자)
# 각 백엔드 가용성 + 프로바이더 인증 매트릭스 + Judge/Synth 후보를 한 번에 점검한다.
# plan-codex-opencode/check-panels.sh 를 확장(agy·claude 추가)했다.
#
# stdout: 사람이 읽는 KEY=VALUE (값에 공백/괄호 포함 가능 — 엄격한 cut -d= 파싱은 비전제).
#   exit 0 = 위임 가능 독립 백엔드 ≥2 (Fusion 성립), exit 1 = <2 (교차 합성 불가).
set -u

# 모델명 SSOT 소비 — 라우팅 문자열·disabled 정책·Gemini 모델명을 models.lib.sh 에서 읽는다.
# models.yaml(루트 진실원)을 sync-models.sh 가 변환한 복제본(이 스킬 폴더에 배치).
# 동일한 값이 routing-fusion.md·council.md·SKILL.md 등에도 있지만, 스크립트 로직이
# 쓰는 진실원은 이 파일이다. 버전업·모델명 변경 시 models.yaml 만 고치고 sync-models.sh.
_SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
if [ -f "$_SELF_DIR/../../models.lib.sh" ]; then
  # shellcheck disable=SC1091
  . "$_SELF_DIR/../../models.lib.sh"
elif [ -f "$_SELF_DIR/models.lib.sh" ]; then
  # 루트 복제본이 없으면 스킬 폴더 자체 사본(독립 설치 시).
  # shellcheck disable=SC1091
  . "$_SELF_DIR/models.lib.sh"
fi
unset _SELF_DIR

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

# === 오케스트레이터 감지 (env 우선, argv 폴백, unknown 허용) ===
# 이 스크립트를 부른 오케스트레이터(분석·검증 주체)의 모델 패밀리를 식별한다.
# 같은 패밀리를 참가자·Judge·Synth에 쓰면 교차검증 독립성이 무너지므로(동족),
# ORCH_FAMILY에 따라 아래 집계에서 그 패밀리를 제외한다.
# ⚠️ 예외(GLM/KIMI): ORCH_FAMILY=glm|kimi이면 opencode(해당 패밀리)는 동족이나 **참가자에 필수 포함**(최소 3종 백엔드 보장).
#    역할 분리(오케스트레이터=검증 only·불가양도 / opencode 참가자=독립 풀이)로 동족 위험을 완화하고,
#    synthesis에 '동종할인(partial)' 표기를 붙인다(GLM/KIMI_MANDATORY_PARTICIPANT 시그널). Judge·Synth는 여전히 동족 회피.
# env: PLAN_FUSION_ORCHESTRATOR=glm|kimi|gpt|gemini|claude (헤드리스/cron 안전)
# argv: 첫 인자를 폴백으로 받는다(env 미설정 시). 둘 다 없으면 unknown.
ORCH_RAW="${PLAN_FUSION_ORCHESTRATOR:-${1:-}}"
ORCH_FAMILY=unknown; ORCH_BACKEND=unknown
case "$ORCH_RAW" in
  glm|glm-5*|glm4*|zai*)          ORCH_FAMILY=glm;    ORCH_BACKEND=opencode ;;
  kimi|kimi-*|moonshot|opencode-go/kimi*) ORCH_FAMILY=kimi; ORCH_BACKEND=opencode ;;
  gpt|gpt-5*|gpt5*|codex)         ORCH_FAMILY=gpt;    ORCH_BACKEND=codex ;;
  gemini|gemini-*|agy|antigravity) ORCH_FAMILY=gemini; ORCH_BACKEND=agy ;;
  claude|opus|anthropic)          ORCH_FAMILY=claude; ORCH_BACKEND=claude ;;
  ''|unknown|NONE|none)           ORCH_FAMILY=unknown; ORCH_BACKEND=unknown ;;
  *)                              ORCH_FAMILY=unknown; ORCH_BACKEND=unknown
    echo "WARN: PLAN_FUSION_ORCHESTRATOR='$ORCH_RAW' 인식불가 — unknown 취급(동족 제거 룰 비활성, 모든 패밀리 가용 후보)." >&2 ;;
esac
echo "# ── 오케스트레이터 감지 ──────────────────────────────────"
echo "ORCHESTRATOR_INPUT=${ORCH_RAW:-<unset>}"
echo "ORCHESTRATOR_FAMILY=$ORCH_FAMILY"
echo "ORCHESTRATOR_BACKEND=$ORCH_BACKEND"

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
    # 기본 Gemini 모델명은 SSOT(M_GEMINI_CLI)에서.
    _gemini_default="${M_GEMINI_CLI:-Gemini 3.1 Pro (High)}"
    echo "AGY_DEFAULT_MODEL_PRESENT=$(printf '%s\n' "$AGY_MODELS" | grep -qiF "$_gemini_default" && echo yes || echo no)"
    unset _gemini_default
    agy_ok=1
  else
    echo "AGY_AUTH=unknown(models-empty)"
    echo "WARN: 'agy models'가 Gemini 목록을 반환하지 않음 — 인증/로그인 상태 확인('! agy' 인터랙티브 로그인)." >&2
  fi
else
  echo "AGY_INSTALLED=no"
  echo "HINT: Antigravity CLI 미설치. agy 패널은 건너뛴다(Gemini 패밀리 제외)." >&2
fi

echo "# ── claude 백엔드 (Anthropic / Opus) — 오케스트레이터가 claude 패밀리가 아닐 때 기본 Judge ─"
# ⚠️ 동족 주의: 오케스트레이터가 claude(Opus) 패밀리면 참가자·Judge·오케스트레이터가 같은 패밀리 →
#    교차검증 독립성↓·확증편향. ORCH_FAMILY=claude일 때는 families·JUDGE_DEFAULT에서 claude를 제외하고
#    다른 패밀리(codex/agy/opencode)를 Judge/참가자로 쓴다(아래 집계 로직에서 적용).
if command -v claude >/dev/null 2>&1; then
  echo "CLAUDE_INSTALLED=yes"
  echo "CLAUDE_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  echo "CLAUDE_AUTH=assumed-ok(설치만 확인 — 실제 인증/계정은 첫 --print에서 확정, 실패 시 Judge 폴백)"
  claude_ok=1
else
  echo "CLAUDE_INSTALLED=no"
  echo "HINT: 'claude' CLI 미발견 — Judge는 다른 패밀리로 폴백하거나 오케스트레이터가 직접 판정." >&2
fi

echo "# ── opencode 백엔드 (GLM / Kimi / DeepSeek / …) ──────────"
if command -v omo >/dev/null 2>&1; then
  echo "OMO_BIN=omo"
  # ⚠️ `omo … | tr` 의 `|| echo`는 죽은 코드(tr이 빈 입력에도 exit 0) → 결과를 변수로 받아 빈값을 폴백.
  _omov=$(omo --version 2>/dev/null | tr -d '[:space:]'); echo "OMO_VERSION=${_omov:-<unknown>}"
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
  # ⚠️ 파이프 종료코드는 마지막 head(빈입력에도 exit0)라 과거 '|| echo "0.0.0"'는 죽은 코드였다
  #    (grep 미매칭이어도 head가 exit0 → || 미실행 → OC_VERSION="" 빈 문자열 출력). 변수 폴백으로 교정.
  OC_VERSION=$(opencode --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  OC_VERSION=${OC_VERSION:-0.0.0}
  echo "OPENCODE_VERSION=$OC_VERSION"
  OC_MAJOR=$(echo "$OC_VERSION" | cut -d. -f1); OC_MAJOR=${OC_MAJOR:-0}
  OC_MINOR=$(echo "$OC_VERSION" | cut -d. -f2); OC_MINOR=${OC_MINOR:-0}
  OC_PATCH=$(echo "$OC_VERSION" | cut -d. -f3); OC_PATCH=${OC_PATCH:-0}
  if [ "$OC_MAJOR" -lt 1 ] || { [ "$OC_MAJOR" -eq 1 ] && [ "$OC_MINOR" -lt 4 ]; }; then
    echo "OPENCODE_VERSION_OK=no"
    echo "HINT: opencode >= 1.4.0 필요. 현재 $OC_VERSION. 'opencode upgrade' 실행." >&2
  else
    echo "OPENCODE_VERSION_OK=yes"
    OC_INSTALLED=1
    # 하드 게이트는 ≥1.4지만, --variant/--format json/run 플래그는 1.16.2에서만 실측됐다(1.4~1.15 미검증).
    # 1.16.2 미만이면 소프트 경고 — 플래그 오류 시 upgrade 권장(opencode-cli.md 경고와 일치).
    if [ "$OC_MAJOR" -eq 1 ] && { [ "$OC_MINOR" -lt 16 ] || { [ "$OC_MINOR" -eq 16 ] && [ "$OC_PATCH" -lt 2 ]; }; }; then
      echo "OPENCODE_FLAGS_VERIFIED=no(<1.16.2 — 플래그 미실측)"
      echo "HINT: opencode $OC_VERSION는 게이트(≥1.4)는 통과하나 --variant/--format 플래그가 1.16.2에서만 실측됨. 플래그 오류 시 'opencode upgrade'." >&2
    else
      echo "OPENCODE_FLAGS_VERIFIED=yes(>=1.16.2)"
    fi
  fi
else
  echo "OPENCODE_INSTALLED=no"
  echo "HINT: npm install -g opencode  (또는 brew install opencode)" >&2
fi

if [ "$OC_INSTALLED" = "1" ]; then
  PROV=$(_t 15 opencode providers list 2>/dev/null || echo "")
  AUTH_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"
  AUTH_KEYS=""
  # ⚠️ 포맷 무관 추출: jq(있으면) 최상위 키 → minified/pretty 모두 안전. 줄앵커 sed는 minified JSON에서 0개 추출.
  if [ -s "$AUTH_FILE" ]; then
    command -v jq >/dev/null 2>&1 && AUTH_KEYS=$(jq -r 'keys[]?' "$AUTH_FILE" 2>/dev/null | tr '\n' ' ')
    # jq 없거나 비표준이면 grep 폴백 — 줄앵커 없이 키 패턴을 직접 잡아 minified에도 견딘다(과매칭은 무해).
    [ -n "$AUTH_KEYS" ] || AUTH_KEYS=$(grep -oE '"[A-Za-z0-9_.-]+"[[:space:]]*:' "$AUTH_FILE" 2>/dev/null | tr -d '": ' | tr '\n' ' ')
  fi
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

# 참가자 백엔드 수 = 교차검증 독립성의 핵심. codex(GPT)·agy(Gemini)·opencode(GLM·Kimi·DeepSeek 생태계)를 센다.
# claude(Opus)는 기본 Judge 전용이라 참가자 백엔드 카운트에서 제외(동족 주의) — 단 가용은 표기.
# ⚠️ opencode가 '교차검증 독립 패밀리'로 자격이 있는가 = openai(=GPT, codex와 중복) 외 provider 인증 여부.
#    기본 패널 GLM(zai)·Kimi(opencode-go) 등 비-GPT 프로바이더가 있어야 독립 패밀리다. openai만 인증된
#    opencode는 codex와 같은 GPT 패밀리라 교차검증 독립성에 기여하지 않으므로 families 카운트에서 뺀다
#    (opencode_ok=1이지만 openai-only면 EFFECTIVE_BACKENDS가 과대평가돼 게이트가 비독립 세트를 통과시키던 결함).
#    ${PROV:-}/${AUTH_KEYS:-}로 set -u 가드(opencode 미설치 시 AUTH_KEYS unset).
opencode_indep=0
kimi_indep=0
if [ "$opencode_ok" = 1 ]; then
  # ⚠️ anthropic 제외(재검토 #2 회귀 수정): claude가 아래에서 effective에 별도 가산되므로, opencode-anthropic을
  #    독립 패밀리로 세면 같은 Anthropic 패밀리가 이중집계돼 effective 과대평가된다. zai/opencode-go/dgrid만 독립.
  if printf '%s\n' "${PROV:-}" | grep -qiE '●.*(Z\.?AI|OpenCode Go|dgrid)' \
     || printf '%s' "${AUTH_KEYS:-}" | grep -qiE 'zai|opencode-go|dgrid'; then
    opencode_indep=1
  fi
  # kimi 패밀리는 opencode-go provider 별도 인증 단위 — glm(zai)과 다른 업스트림(provider prefix)이라
  # 별도 패밀리로 분리. 단 opencode CLI 백엔드(런타임·바이너리)는 glm과 공유 → partial-inbreed(아래 로직).
  if printf '%s\n' "${PROV:-}" | grep -qiE '●.*(OpenCode Go)' \
     || printf '%s' "${AUTH_KEYS:-}" | grep -qiE 'opencode-go'; then
    kimi_indep=1
  fi
fi
echo "OPENCODE_INDEP_FAMILY=$([ "$opencode_indep" = 1 ] && echo yes || echo 'no(openai-only이면 GPT 중복 — 독립 패밀리 아님)')"
echo "KIMI_INDEP_FAMILY=$([ "$kimi_indep" = 1 ] && echo yes || echo 'no(opencode-go 미인증 — kimi 패밀리 가용 아님)')"

# === 동족 제거: 오케스트레이터와 같은 패밀리는 참가자 카운트에서 제외 ===
# 교차검증 독립성의 핵심 — 오케스트레이터가 이미 그 패밀리를 쓰고 있으므로, 같은 패밀리를 참가자·Judge·Synth에
# 또 넣으면 동족(확증편향). 각 패밀리별로: ready 여부 + 오케스트레이터 패밀리 충돌 여부를 종합해 카운트한다.
# ⚠️ 예외: ORCH_FAMILY=glm|kimi이면 opencode(해당 패밀리)는 동족이나 참가자에서 빼지 않고 **필수 포함**(GLM/KIMI_MANDATORY_PARTICIPANT=yes).
#    역할 분리(오케스트레이터=검증 only·불가양도 / opencode 참가자=독립 풀이)로 동족 위험을 완화 + '최소 3종 백엔드' 보장.
#    동종할인(partial) 표기를 붙인다. Judge·Synth 후보에서는 종전대로 동족 회피(아래 체인·기본값 로직에서 처리).
EXCLUDED=""   # 휴먼 리딩용 제외 사유 누적
excluded_codex=0
if [ "$codex_ok" = 1 ]; then
  if [ "$ORCH_FAMILY" = gpt ]; then
    excluded_codex=1; EXCLUDED="${EXCLUDED}codex(orch=gpt) "
  fi
fi
excluded_agy=0
if [ "$agy_ok" = 1 ]; then
  if [ "$ORCH_FAMILY" = gemini ]; then
    excluded_agy=1; EXCLUDED="${EXCLUDED}agy(orch=gemini) "
  fi
fi
# ⚠️ GLM/KIMI 예외: 오케스트레이터=GLM/KIMI이더라도 opencode(해당 패밀리)는 **참가자에 필수 포함**.
# 정당화: 오케스트레이터는 검증-only(불가양도), opencode 참가자는 독립 풀이 수행 — 역할 분리로
# 동족 위험을 완화하고, "최소 3종 백엔드(codex·agy·opencode)" 다양성을 보장한다. 단 동족이므로
# synthesis/REPORT에 '동종할인(partial)' 표기를 붙인다(DeepSeek partial 선례 재사용).
# (Judge·Synth는 여전히 동족 회피 — opencode가 Judge/Synth 후보에서 빠지는 건 아래 체인·기본값 로직에서 별도 처리.)
excluded_opencode=0
glm_mandatory_participant=no
kimi_mandatory_participant=no
if [ "$opencode_indep" = 1 ]; then
  if [ "$ORCH_FAMILY" = glm ]; then
    glm_mandatory_participant=yes   # 제외하지 않고 필수 참가자로 — families 가산 유지
  fi
  if [ "$ORCH_FAMILY" = kimi ]; then
    kimi_mandatory_participant=yes  # KIMI 예외(GLM 대칭) — opencode 백엔드 필수 포함(3종 보장)
  fi
fi
excluded_claude=0
if [ "$claude_ok" = 1 ]; then
  if [ "$ORCH_FAMILY" = claude ]; then
    excluded_claude=1; EXCLUDED="${EXCLUDED}claude(orch=claude) "
  fi
fi
echo "EXCLUDED_FAMILIES=${EXCLUDED:-<none>}"
echo "ORCH_FAMILY_EXCLUDED=$([ -n "$EXCLUDED" ] && echo yes || echo no)"
# GLM/KIMI 예외 시그널 — 참가자 동종(역할 분리) 명시. synthesis/REPORT가 읽어 '동종할인' 표기.
echo "GLM_MANDATORY_PARTICIPANT=$glm_mandatory_participant"
echo "KIMI_MANDATORY_PARTICIPANT=$kimi_mandatory_participant"
if [ "$glm_mandatory_participant" = yes ]; then
  echo "PARTICIPANT_CONFLICT_RISK=partial(opencode-glm 동족·역할분리)"
elif [ "$kimi_mandatory_participant" = yes ]; then
  echo "PARTICIPANT_CONFLICT_RISK=partial(opencode-kimi 동족·역할분리)"
fi

families=0
[ "$codex_ok" = 1 ] && [ "$excluded_codex" = 0 ]    && families=$((families+1))
[ "$agy_ok" = 1 ]   && [ "$excluded_agy" = 0 ]      && families=$((families+1))
[ "$opencode_indep" = 1 ] && [ "$excluded_opencode" = 0 ] && families=$((families+1))
echo "PARTICIPANT_FAMILIES=$families (codex/agy/opencode 중 ready & 비-오케스트레이터-패밀리 — opencode 백엔드는 1로 집계(백엔드 다양성 기준); 단 GLM(zai)·Kimi(opencode-go)는 별도 provider라 동족 판정은 provider별로 적용; openai-only opencode는 GPT 중복이라 제외; 모델 다양성 ≠ 백엔드 다양성; ORCH_FAMILY와 충돌하는 패밀리는 동족이라 제외(EXCLUDED_FAMILIES 참조); ⚠️ 예외: ORCH_FAMILY=glm|kimi이면 opencode는 동족이나 **참가자에 필수 포함**(GLM/KIMI_MANDATORY_PARTICIPANT=yes, 동종할인 표기 — 역할 분리: 오케스트레이터=검증 only / 참가자=독립 풀이))"

# claude(Opus)는 오케스트레이터가 claude 패밀리가 아닐 때 한해 '참가자 후보 백엔드'로 쓸 수 있다.
# (오케스트레이터=claude면 claude를 참가자로 쓰면 동족이므로 제외 — effective 가산도 안 함.)
# 차단 판정엔 이를 포함한 값을 쓴다.
effective=$families
if [ "$claude_ok" = 1 ] && [ "$excluded_claude" = 0 ]; then effective=$((effective+1)); fi
echo "EFFECTIVE_BACKENDS=$effective (participant families + claude-as-participant 후보 — 단 ORCH_FAMILY=claude면 claude 가산 제외)"
# ④ assumed-ok 정합: claude가 effective에 가산됐으나 assumed-ok(미확정)면, 그 1개에 의존하는 effective는 잠정이다.
#    차단 게이트는 낙관적으로 effective 기준이되, case A '전부 가용' 판정은 INDEPENDENT_FAMILIES_CONFIRMED(claude 제외) 기준임을 명시한다.
if [ "$claude_ok" = 1 ] && [ "$excluded_claude" = 0 ]; then
  echo "EFFECTIVE_INCLUDES_ASSUMED=yes (claude=assumed-ok 미확정 — 첫 --print 실패 시 effective 1 감소 → degraded 가능; case A 판정은 INDEPENDENT_FAMILIES_CONFIRMED 사용)"
fi

# === 패널 확정 게이트(SKILL.md 0-2.5)용 machine-readable 신호 ===
# 호명 파싱은 오케스트레이터 몫(REQUEST_*/GATE_CASE/EXTRA_AVAILABLE/ESTIMATED_CALLS는 거기서 채운다).
# 스크립트는 '가용성'만 내보내되, assumed-ok(claude)를 case A '전부 가용'에서 제외하도록 구분한다.
echo "INDEPENDENT_FAMILIES_CONFIRMED=$families (assumed-ok claude 제외 · 오케스트레이터 패밀리 제외 — 실가용 비-동족 참가자 패밀리 수; 게이트 case A '전부 가용' 판정 기준)"
if [ "$claude_ok" = 1 ] && [ "$excluded_claude" = 0 ]; then
  echo "CLAUDE_BACKEND_CONFIRMED=no (설치만 확인된 assumed-ok — 실인증은 첫 --print에서 확정; case A에서 실가용으로 세지 말고 '⚠️미확정'으로 라벨)"
fi
# opencode 내 GLM(zai)·Kimi·DeepSeek(opencode-go)는 별도 인증 단위라 한쪽만 죽을 수 있다(case F·B 판정용).
# provider-list 마커(●)로만 확인 → auth-file 경로 등 미확인 시 보수적으로 no.
# ⚠️ Kimi·DeepSeek는 같은 opencode-go provider를 공유(routing-fusion.md 변형표 line 33·35) — 라우트별 별도 인증
#    단위가 아니므로 둘 다 opencode-go 마커 하나로 판정한다. Judge 폴백(F1)은 MODEL_READY_DEEPSEEK로 진입한다.
if [ "$opencode_ok" = 1 ]; then
  printf '%s\n' "${PROV:-}" | grep -qiE '●.*(Z\.?AI)' && echo "MODEL_READY_GLM=yes" || echo "MODEL_READY_GLM=no(zai 미인증/미확인)"
  printf '%s\n' "${PROV:-}" | grep -qiE '●.*(OpenCode Go)' && echo "MODEL_READY_KIMI=yes" || echo "MODEL_READY_KIMI=no(opencode-go 미인증/미확인)"
  printf '%s\n' "${PROV:-}" | grep -qiE '●.*(OpenCode Go)' && echo "MODEL_READY_DEEPSEEK=yes" || echo "MODEL_READY_DEEPSEEK=no(opencode-go 미인증/미확인)"
else
  echo "MODEL_READY_GLM=no(opencode 미가용)"
  echo "MODEL_READY_KIMI=no(opencode 미가용)"
  echo "MODEL_READY_DEEPSEEK=no(opencode 미가용)"
fi

# Judge/Synth 후보 신호 — 오케스트레이터 패밀리와 충돌하면 차순위로, 모두 충돌하면 self 폴백.
# 동족(오케스트레이터 패밀리 == Judge/Synth 패밀리)이면 CONFLICT_RISK=yes로 표시해 synthesis.md에 할인 명시.
#
# Judge 우선순위: claude(비-동족) > codex(비-동족) > agy(비-동족) > opencode-deepseek(동족할인)
#   > opencode-glm(비-동족·단 ORCH_FAMILY=kimi면 partial) > opencode-kimi(비-동족·단 ORCH_FAMILY=glm이면 partial) > self(비독립).
#
# ⚠️ DeepSeek 예외(F1): 참가자 집계에서는 DeepSeek를 opencode 1패밀리로 묶어 동족 제거하지만, Judge는
#    교차검증의 '제3자 판정'이라 동족이어도 '동종할인 경고'로 허용하는 게 self(오케스트레이터=동족+비독립)보다 낫다.
#    claude(기본 Judge)가 런타임에 죽은 경우(주간 한도·인증 만료 등)의 핵심 폴백 경로다.
#    DeepSeek는 Kimi와 같은 opencode-go provider(routing-fusion.md line 35) — 인증 공유하므로 MODEL_READY_DEEPSEEK로 판정.
# ⚠️ Kimi 분리: ORCH_FAMILY=glm이면 Kimi(opencode-go)는 opencode 백엔드 공유로 partial.
#    ORCH_FAMILY=kimi이면 DeepSeek(opencode-go provider 공유)가 partial. 둘은 같은 provider라 상호 partial.
deepseek_judge_ok=0
deepseek_partial_inbreed=no
kimi_judge_ok=0
kimi_partial_inbreed=no
if printf '%s\n' "${PROV:-}" | grep -qiE '●.*(OpenCode Go)' \
   || printf '%s' "${AUTH_KEYS:-}" | grep -qiE 'opencode-go'; then
  deepseek_judge_ok=1
  kimi_judge_ok=1
  if [ "$ORCH_FAMILY" = glm ]; then
    deepseek_partial_inbreed=yes   # opencode 백엔드 공유(런타임·인증) — 부분 동족
    kimi_partial_inbreed=yes       # opencode 백엔드 공유(GLM 오케스트레이터) — 부분 동족
  fi
  if [ "$ORCH_FAMILY" = kimi ]; then
    deepseek_partial_inbreed=yes   # opencode-go provider 공유(KIMI 오케스트레이터) — 부분 동족
  fi
fi

# JUDGE_FALLBACK_CHAIN: 런타임 Judge 폴백이 소비하는 후보 순서(fusion.md §3-2·§3-4).
#    "primary -> fallback1 -> fallback2 -> ... -> self" 형식. self 전 단계까지 차순위가 없으면 self.
#    각 후보는 "backend:model:conflict" 튜플 — conflict=no|partial|yes(partial=동종할인, yes=완전동족/self).

# ⚠️ #5 강제: disabledModels 는 models.yaml SSOT(disabled_models 키)에서 온다.
#    과거엔 case 문에 fable-5/mythos-5 를 하드코딩했으나, models.lib.sh 의
#    is_disabled_model 헬퍼(= SSOT MODELS_DISABLED 에서 glob 생성)로 대체.
#    새 모델을 disabled 에 추가하려면 models.yaml 만 고치고 sync-models.sh.
if ! command -v is_disabled_model >/dev/null 2>&1; then
  # models.lib.sh 미로드(레거시/독립 실행) 폴백 — 빈 집합(아무것도 금지 아님).
  is_disabled_model() { return 0; }
fi

_jchain=""
_j_self_added=0
judge_chain_append() {  # $1=허용여부(1/0) $2=backend $3=model $4=conflict
  if [ "$1" = 1 ]; then
    # ⚠️ #7: 과거 build_judge_candidate() 데드코드(정도만 있고 호출 0건, | 구분자가 실사용 : 과 불일치)는 삭제.
    if ! is_disabled_model "$3"; then
      echo "WARN: disabledModels 정책 위반(SSOT MODELS_DISABLED) — backend=$2 model=$3 후보에서 제외." >&2
      return 0
    fi
    if [ -n "$_jchain" ]; then _jchain="${_jchain} -> "; fi
    _jchain="${_jchain}${2}:${3}:${4}"
  fi
}

# 체인 구성: claude → codex → agy → opencode-deepseek(동족할인) → opencode-glm → opencode-kimi → self.
# claude/codex/agy는 비-동족일 때만(ORCH_FAMILY와 다를 때). DeepSeek는 partial 허용(GLM/KIMI 오케스트레이터도 라우트 달라 허용).
# GLM·Kimi는 별도 provider(zai vs opencode-go)라 분리 — 단 opencode 백엔드 공유로 상호 partial
# (ORCH_FAMILY=kimi→glm partial, ORCH_FAMILY=glm→kimi partial).
# 모델명은 SSOT(models.lib.sh 의 M_*_CLI)에서 — 하드코딩 금지.
_M_OPUS="${M_OPUS_CLI:-opus}"
_M_GPT="${M_GPT_CLI:-gpt-5.5}"
_M_GEMINI="${M_GEMINI_CLI:-gemini}"          # agy judge 식별용 라벨(실제 모델문자열은 아님)
_M_DEEPSEEK="${M_DEEPSEEK_CLI:-opencode-go/deepseek-v4-pro}"
_M_KIMI="${M_KIMI_CLI:-opencode-go/kimi-k2.7-code}"
_M_GLM="${M_GLM_CLI:-zai-coding-plan/glm-5.2}"
_ds_conflict=no; [ "$deepseek_partial_inbreed" = yes ] && _ds_conflict=partial
_kimi_conflict=no; [ "$kimi_partial_inbreed" = yes ] && _kimi_conflict=partial
# GLM(zai)은 ORCH_FAMILY=kimi일 때 opencode 백엔드 공유로 partial(KIMI 오케스트레이터).
_glm_conflict=no; [ "$ORCH_FAMILY" = kimi ] && [ "$opencode_indep" = 1 ] && _glm_conflict=partial
if [ "$claude_ok" = 1 ] && [ "$ORCH_FAMILY" != claude ]; then
  judge_chain_append 1 claude "$_M_OPUS" no
fi
if [ "$codex_ok" = 1 ] && [ "$ORCH_FAMILY" != gpt ]; then
  judge_chain_append 1 codex "$_M_GPT" no
fi
if [ "$agy_ok" = 1 ] && [ "$ORCH_FAMILY" != gemini ]; then
  judge_chain_append 1 agy "$_M_GEMINI" no
fi
if [ "$deepseek_judge_ok" = 1 ]; then
  judge_chain_append 1 opencode "$_M_DEEPSEEK" "$_ds_conflict"
fi
# GLM(zai) — ORCH_FAMILY≠glm일 때. ORCH_FAMILY=kimi면 opencode 백엔드 공유로 partial.
if [ "$opencode_indep" = 1 ] && [ "$ORCH_FAMILY" != glm ]; then
  judge_chain_append 1 opencode "$_M_GLM" "$_glm_conflict"
fi
# Kimi(opencode-go) — ORCH_FAMILY≠kimi일 때. ORCH_FAMILY=glm이면 opencode 백엔드 공유로 partial.
if [ "$kimi_judge_ok" = 1 ] && [ "$ORCH_FAMILY" != kimi ]; then
  judge_chain_append 1 opencode "$_M_KIMI" "$_kimi_conflict"
fi
# 차순위가 하나도 없으면 self(완전 비독립). 라벨의 패밀리는 런타임 오케스트레이터 패밀리를 따른다.
_jchain="${_jchain:-orchestrator-self:${ORCH_FAMILY:-glm}:yes}"

JUDGE_DEFAULT=""
JUDGE_CONFLICT_RISK=no
# JUDGE_DEFAULT = 체인의 첫 후보(전체 패밀리 라벨용). 충돌 라벨은 런타임이 아니라 preflight 표시용.
if [ "$claude_ok" = 1 ] && [ "$ORCH_FAMILY" != claude ]; then
  JUDGE_DEFAULT='claude(Opus)'
elif [ "$codex_ok" = 1 ] && [ "$ORCH_FAMILY" != gpt ]; then
  JUDGE_DEFAULT='codex(GPT) fallback'
elif [ "$agy_ok" = 1 ] && [ "$ORCH_FAMILY" != gemini ]; then
  JUDGE_DEFAULT='agy(Gemini) fallback'
elif [ "$deepseek_judge_ok" = 1 ]; then
  JUDGE_DEFAULT='opencode(DeepSeek v4 Pro) fallback'
  [ "$deepseek_partial_inbreed" = yes ] && JUDGE_CONFLICT_RISK=partial
elif [ "$opencode_indep" = 1 ] && [ "$ORCH_FAMILY" != glm ]; then
  JUDGE_DEFAULT='opencode(GLM) fallback'
  [ "$ORCH_FAMILY" = kimi ] && JUDGE_CONFLICT_RISK=partial   # opencode 백엔드 공유(KIMI 오케스트레이터)
elif [ "$kimi_judge_ok" = 1 ] && [ "$ORCH_FAMILY" != kimi ]; then
  JUDGE_DEFAULT='opencode(Kimi) fallback'
  [ "$kimi_partial_inbreed" = yes ] && JUDGE_CONFLICT_RISK=partial
else
  JUDGE_DEFAULT='orchestrator-self(비독립 — 가용 비-동족 백엔드 없음)'
  JUDGE_CONFLICT_RISK=yes
fi
echo "JUDGE_DEFAULT=$JUDGE_DEFAULT"
echo "JUDGE_FALLBACK_CHAIN=$_jchain"
echo "JUDGE_DEEPSEEK_READY=$([ "$deepseek_judge_ok" = 1 ] && echo yes || echo no)"
echo "JUDGE_KIMI_READY=$([ "$kimi_judge_ok" = 1 ] && echo yes || echo no)"
echo "JUDGE_CONFLICT_RISK=$JUDGE_CONFLICT_RISK (yes=Judge=오케스트레이터-self(완전동족) / partial=Judge가 오케스트레이터와 백엔드·provider 공유(opencode-deepseek/kimi/glm — 동종할인) / no=비독립 — synthesis.md 표기 기준)"

# Synth 우선순위: codex(비-동족) > claude(비-동족) > 가용 참가자 > self.
SYNTH_DEFAULT=""
SYNTH_CONFLICT_RISK=no
if [ "$codex_ok" = 1 ] && [ "$ORCH_FAMILY" != gpt ]; then
  SYNTH_DEFAULT='codex(GPT)'
elif [ "$claude_ok" = 1 ] && [ "$ORCH_FAMILY" != claude ]; then
  SYNTH_DEFAULT='claude(Opus) fallback'
elif [ "$agy_ok" = 1 ] && [ "$ORCH_FAMILY" != gemini ]; then
  SYNTH_DEFAULT='agy(Gemini) fallback'
elif [ "$opencode_indep" = 1 ] && [ "$ORCH_FAMILY" != glm ]; then
  SYNTH_DEFAULT='opencode(GLM) fallback'
elif [ "$kimi_judge_ok" = 1 ] && [ "$ORCH_FAMILY" != kimi ]; then
  SYNTH_DEFAULT='opencode(Kimi) fallback'
else
  SYNTH_DEFAULT='orchestrator-self(비독립 — 가용 비-동족 백엔드 없음)'
  SYNTH_CONFLICT_RISK=yes
fi
echo "SYNTH_DEFAULT=$SYNTH_DEFAULT"
echo "SYNTH_CONFLICT_RISK=$SYNTH_CONFLICT_RISK (yes면 Synth가 오케스트레이터-self라 동족)"

# 차단 판정은 EFFECTIVE_BACKENDS 기준(codex+claude처럼 families=1이라도 독립 2백엔드면 Fusion '가능'으로 통과).
if [ "$effective" -ge 2 ]; then
  # ⚠️ FUSION_CAPABILITY 값은 런타임 quorum(fusion.md의 참가자 family 카운트)과 일치해야 한다 — 참가자 패밀리<2면
  #    기본 패널(claude=Judge)은 런타임에서 1패밀리뿐이라 'Fusion 미성립'으로 격하된다. 그래서 families<2일 때
  #    'full'이라 말하면 preflight가 런타임과 모순된다 → 'conditional'로 표기해 claude를 '참가자'로 써야 성립함을 못박는다.
  if [ "$families" -ge 2 ]; then
    echo "FUSION_CAPABILITY=full(participant=$families, effective=$effective)"
  else
    echo "FUSION_CAPABILITY=conditional(participant=$families<2, effective=$effective — 비-오케스트레이터 패밀리를 '참가자'로 써야 교차검증 2패밀리 성립; Judge-only default면 런타임 quorum이 'Fusion 미성립'으로 격하한다)"
  fi
  if [ "$effective" -eq 2 ]; then
    echo "NOTE: 백엔드 2개 — 참가자 2 패밀리와 '독립' Judge를 동시에 둘 수 없다(한 백엔드가 참가자+Judge 겸직)."
    echo "      Judge=self(오케스트레이터) 폴백을 권장하거나, 겸직하면 synthesis.md에 '비독립 할인'을 명시하라." >&2
    if [ "$families" -lt 2 ]; then
      echo "      ⚠️ 참가자 패밀리=$families(<2): effective=2는 비-오케스트레이터 패밀리 1개 + 다른 백엔드(예: codex+claude-participant)로만 교차검증 2패밀리가 된다." >&2
      echo "        Judge-only로만 쓰이면 실제 참가자는 1패밀리뿐 → 진짜 교차검증 아님(단일 위임 격하 고려). 또 claude_ok는 설치만 확인한 assumed-ok다." >&2
    fi
  fi
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
