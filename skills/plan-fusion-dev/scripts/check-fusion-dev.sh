#!/usr/bin/env bash
# check-fusion-dev.sh — plan-fusion-dev 사전 점검 (read-only, 아무것도 수정하지 않음)
#
# 메타 체이닝 스킬: ① plan-fusion(Fusion-Research 계획) → ② plan-codex-opencode(Pipeline/Council 개발).
# 두 하위 스킬의 사전점검을 한 번에 묶어 실행하고, 양쪽 모두 가용해야 진행 가능함을 게이트한다.
#   - plan-fusion 쪽: EFFECTIVE_BACKENDS ≥ 2 (교차검증 독립 패밀리 ≥2) 가 있어야 계획 단계 합성 성립.
#   - plan-codex-opencode 쪽: codex(GPT) + opencode(GLM) 양쪽 가용이 개발 혼용의 전제.
# 둘 다 통과해야 exit 0. 어느 한쪽이라도 exit 1이면 체이닝 불가 → 안내 후 중단.
#
# stdout: KEY=VALUE (형제 스크립트 출력 + 메타 종합). exit 0=진행 가능, exit 1=불가.
set -u

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
PLAN_FUSION_DIR="$SELF_DIR/../../plan-fusion"
PLAN_CODOC_DIR="$SELF_DIR/../../plan-codex-opencode"

FUSION_CHECK="$PLAN_FUSION_DIR/scripts/check-fusion.sh"
PANELS_CHECK="$PLAN_CODOC_DIR/scripts/check-panels.sh"

if [ ! -f "$FUSION_CHECK" ]; then
  echo "FUSION_DEV_FATAL=plan-fusion 사전점검 스크립트 누락($FUSION_CHECK)" >&2
  echo "HINT: 형제 스킬 plan-fusion이 같은 레포에 있는지 확인." >&2
  exit 1
fi
if [ ! -f "$PANELS_CHECK" ]; then
  echo "FUSION_DEV_FATAL=plan-codex-opencode 사전점검 스크립트 누락($PANELS_CHECK)" >&2
  echo "HINT: 형제 스킬 plan-codex-opencode가 같은 레포에 있는지 확인." >&2
  exit 1
fi

echo "# ════════════════════════════════════════════════════════"
echo "# plan-fusion-dev 메타 점검 — 계획(plan-fusion) + 개발(plan-codex-opencode)"
echo "# ════════════════════════════════════════════════════════"

echo
echo "# ── [1/2] 계획 단계 점검: plan-fusion (Fusion-Research) ─────"
# check-fusion.sh은 exit 0(EFFECTIVE_BACKENDS≥2) / exit 1(<2). 출력은 그대로 전달.
# bash 로 호출: 형제 스크립트(check-fusion.sh)는 git 모드가 100644라 직접 실행하면 Permission denied(exit 126).
# check-panels.sh(100755)와 무관하게, 양쪽 모두 bash 로 균일하게 소싱하는 게 안전하다.
# 동족 제거는 PLAN_FUSION_ORCHESTRATOR env(check-fusion.sh 표준)가 자식 프로세스에 자동 상속되어 적용된다.
# ⚠️ GLM 예외(참가자 한정): ORCH_FAMILY=glm이면 opencode(GLM)는 동족이어도 참가자에 필수 포함 —
#    GLM_MANDATORY_PARTICIPANT=yes / PARTICIPANT_CONFLICT_RISK=partial(동종할인 synthesis 명시).
#    체이닝 계획 단계 패널이 codex·agy·glm 3종이 되어 N 기본값=3 (Judge=claude·Synth=codex는 동족 회피 유지).
FUSION_OUT=$(bash "$FUSION_CHECK" 2> >(cat >&2)); FUSION_RC=$?
# ⚠️ 프로세스 치환 >(cat >&2) 은 bash 전용(sh 불가). 스킬 실행 환경은 bash를 전제한다(다른 스크립트와 동일).
printf '%s\n' "$FUSION_OUT" | grep -E '^(EFFECTIVE_BACKENDS|ORCHESTRATOR_FAMILY|PARTICIPANT_FAMILIES|GLM_MANDATORY_PARTICIPANT|PARTICIPANT_CONFLICT_RISK|JUDGE_DEFAULT|SYNTH_DEFAULT|FUSION_CAPABILITY|MODEL_READY_GLM|CODEX_BACKEND_READY|OPENCODE_BACKEND_READY|AGY_BACKEND_READY|CLAUDE_BACKEND_READY)=' || true
echo "FUSION_CHECK_EXIT=$FUSION_RC"

echo
echo "# ── [2/2] 개발 단계 점검: plan-codex-opencode (codex + opencode) ──"
# 개발 혼용(GPT 주축 + GLM 보조)은 두 백엔드 모두 가용해야 의미가 있다.
PANEL_OUT=$(bash "$PANELS_CHECK" 2> >(cat >&2)); PANELS_RC=$?
printf '%s\n' "$PANEL_OUT" | grep -E '^(CODEX_BACKEND_READY|OPENCODE_BACKEND_READY|PANEL_CAPABILITY|OMO_RUN_READY|MODEL_READY|PROVIDER_)' || true
echo "PANELS_CHECK_EXIT=$PANELS_RC"

echo
echo "# ── 메타 종합 (체이닝 가용성) ────────────────────────────"

# 계획 단계 가용: exit 0 = EFFECTIVE_BACKENDS≥2 (Fusion 성립).
fusion_ok=0; [ "$FUSION_RC" -eq 0 ] && fusion_ok=1
echo "FUSION_DEV_PLAN_READY=$([ "$fusion_ok" = 1 ] && echo yes || echo 'no(plan-fusion EFFECTIVE_BACKENDS<2)')"

# 개발 단계 가용: codex + opencode 둘 다 ready.
# ⚠️ 단 opencode가 openai-only면 GPT 중복이라 GLM 혼용이 성립하지 않는다 — GLM(zai) 인증 기준으로 판별.
# GLM 인증 신호는 check-fusion.sh의 MODEL_READY_GLM(yes/no) 우선, 없으면 check-panels.sh의 PROVIDER_ZAI(ok/none) 로 폴백.
# (check-fusion.sh가 런타임 실패해도 check-panels.sh는 독립 동작하므로 dev-only 판별이 안정되게.)
codex_ready=$(printf '%s\n' "$PANEL_OUT" | sed -n 's/^CODEX_BACKEND_READY=//p' | head -1)
oc_ready=$(printf '%s\n' "$PANEL_OUT" | sed -n 's/^OPENCODE_BACKEND_READY=//p' | head -1)
glm_ready=$(printf '%s\n' "$FUSION_OUT" | sed -n 's/^MODEL_READY_GLM=//p' | head -1)
[ "${glm_ready:-}" = yes ] || glm_ready=$(printf '%s\n' "$PANEL_OUT" | sed -n 's/^PROVIDER_ZAI=//p' | head -1)
# 정규화: MODEL_READY_GLM(yes) 또는 PROVIDER_ZAI(ok) 둘 다 "GLM 인증됨" — ok 로 통일해 비교.
case "${glm_ready:-}" in yes|ok) glm_auth=ok ;; *) glm_auth=no ;; esac
dev_ok=0
if [ "$codex_ready" = yes ] && [ "$oc_ready" = yes ] && [ "$glm_auth" = ok ]; then
  dev_ok=1
fi
echo "FUSION_DEV_DEV_READY=$([ "$dev_ok" = 1 ] && echo yes || echo 'no(codex+opencode+GLM(zai) 인증 필요)')"
if [ "$codex_ready" = yes ] && [ "$oc_ready" = yes ] && [ "$glm_auth" != ok ]; then
  echo "HINT: opencode는 가용하나 GLM(zai) 프로바이더 인증이 확인 안 됨 — 개발 단계 GLM 혼용에 zai 로그인 필요('opencode providers login')." >&2
fi

if [ "$fusion_ok" = 1 ] && [ "$dev_ok" = 1 ]; then
  echo "FUSION_DEV_CAPABILITY=full(계획 Fusion 성립 + 개발 GPT+GLM 혼용 가능)"
  exit 0
elif [ "$fusion_ok" = 1 ]; then
  echo "FUSION_DEV_CAPABILITY=plan-only(계획은 가능, 개발 혼용 불가 — codex/opencode/zai 설정 후 재시도)"
  echo "HINT: 계획만 plan-fusion으로 진행하고, 개발은 plan-then-codex(단일 GPT) 등으로 대체 고려." >&2
  exit 1
elif [ "$dev_ok" = 1 ]; then
  echo "FUSION_DEV_CAPABILITY=dev-only(개발은 가능, 계획 Fusion 불가 — EFFECTIVE_BACKENDS<2)"
  echo "HINT: 교차검증 독립 패밀리가 2개 미만. 백엔드를 추가(codex/agy/opencode 중)하거나, 계획을 오케스트레이터 단독으로." >&2
  exit 1
else
  echo "FUSION_DEV_CAPABILITY=none(양쪽 모두 미충족)"
  echo "HINT: plan-fusion(EFFECTIVE_BACKENDS≥2) + codex/opencode/zai 인증이 모두 필요. 형제 스킬 README 참고." >&2
  exit 1
fi
