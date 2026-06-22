#!/usr/bin/env bash
# check-fusion-dev-secu.sh — plan-fusion-dev-secu 사전 점검 (read-only)
#
# 기존 plan-fusion-dev/scripts/check-fusion-dev.sh 을 래핑(복제 아님 — SSOT).
# 추가로 SECURE_MODE 강제 + L1 정적 분석 도구 감지를 더한다.
#
# 래핑 전략: check-fusion-dev.sh 의 모든 출력을 통과시키고, 그 뒤에 -secu 전용 출력을 덧붙인다.
# SECURE/L1 부분은 plan-fusion-secu/scripts/check-fusion-secu.sh 의 동일 로직을 재사용(중복 구현 금지 —
# 그 스크립트가 이미 도구 감지를 다룬다).
#
# exit 코드: check-fusion-dev.sh 과 동일(0=성립 / 1=불성립).
set -u

# === 경로 해석 ===
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SKILL_DIR="$(cd "$_SELF_DIR/.." && pwd)"
_REPO_ROOT="$(cd "$_SKILL_DIR/../.." && pwd)"
_BASE_DEV_CHECK="$_REPO_ROOT/skills/plan-fusion-dev/scripts/check-fusion-dev.sh"
_SECU_CHECK="$_REPO_ROOT/skills/plan-fusion-secu/scripts/check-fusion-secu.sh"

if [ ! -f "$_BASE_DEV_CHECK" ]; then
  echo "ABORT: 기반 check-fusion-dev.sh 없음('$_BASE_DEV_CHECK') — plan-fusion-dev 스킬이 같은 레포에 있어야 한다." >&2
  exit 1
fi
if [ ! -f "$_SECU_CHECK" ]; then
  echo "ABORT: check-fusion-secu.sh 없음('$_SECU_CHECK') — plan-fusion-secu 스킬이 같은 레포에 있어야 한다." >&2
  exit 1
fi

# === 1. 기반 check-fusion-dev.sh 실행 (모든 출력 통과) ===
# 이 스크립트는 내부적으로 plan-fusion/check-fusion.sh + plan-codex-opencode/check-panels.sh 를 모두 호출하므로
# 백엔드 가용성·오케스트레이터 감지·Judge/Synth 후보·GLM 인증을 한 번에 점검한다.
bash "$_BASE_DEV_CHECK" "$@"
_base_rc=$?

if [ "$_base_rc" -ne 0 ]; then
  exit "$_base_rc"
fi

# === 2. SECURE_MODE + L1 도구 감지 (check-fusion-secu.sh 재사용) ===
# check-fusion-secu.sh 는 내부적으로 plan-fusion/check-fusion.sh 도 호출하므로 중복 실행되지만,
# SECURE/L1 감지 부분만 필요하므로 전체 출력에서 해당 섹션만 발췌해 덧붙인다.
echo ""
echo "# ── plan-fusion-dev-secu 확장 (SECURE_MODE + L1 도구) ──────────"
# check-fusion-secu.sh 실행 후 'SECURE_MODE' 이후 라인만 추출(기반 점검 중복 출력 제거)
_secu_out=$(bash "$_SECU_CHECK" 2>/dev/null)
# 'SECURE_MODE=yes' 라인부터 끝까지
echo "$_secu_out" | awk '/^SECURE_MODE=/{flag=1} flag{print}'

exit 0
