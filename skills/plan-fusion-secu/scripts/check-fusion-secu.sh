#!/usr/bin/env bash
# check-fusion-secu.sh — plan-fusion-secu 사전 점검 (read-only)
#
# 기존 plan-fusion/scripts/check-fusion.sh 을 래핑(복제 아님 — SSOT).
# 추가로 SECURE_MODE 강제 + L1 정적 분석 도구 감지를 더한다.
#
# 래핑 전략: check-fusion.sh 의 모든 출력(KEY=VALUE)을 그대로 stdout 으로 통과시키고,
# 그 뒤에 -secu 전용 출력(SECURE_MODE·L1 도구 가용성)을 덧붙인다.
# 이렇게 하면 check-fusion.sh 의 버그 수정이 자동으로 반영되고, 드리프트가 없다.
#
# exit 코드: check-fusion.sh 과 동일(0=성립 / 1=불성립).
#   단, L1 도구가 하나도 없으면 SECURE_L1_CAPABILITY=minimal 로 경고만(WARN — L2로 폴백 가능).
set -u

# === 경로 해석 ===
# 이 스크립트 위치에서 형제 스킬(plan-fusion)의 check-fusion.sh 를 찾는다.
# makeskill 레포 구조: skills/plan-fusion-secu/scripts/check-fusion-secu.sh
#                  → skills/plan-fusion/scripts/check-fusion.sh (형제 참조)
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SKILL_DIR="$(cd "$_SELF_DIR/.." && pwd)"
_REPO_ROOT="$(cd "$_SKILL_DIR/../.." && pwd)"
_BASE_CHECK="$_REPO_ROOT/skills/plan-fusion/scripts/check-fusion.sh"

if [ ! -f "$_BASE_CHECK" ]; then
  echo "ABORT: 기반 check-fusion.sh 없음('$_BASE_CHECK') — plan-fusion 스킬이 같은 레포에 있어야 한다." >&2
  exit 1
fi

# === 1. 기반 check-fusion.sh 실행 (모든 출력 통과) ===
# argv/env를 그대로 전달 — 사용자가 PLAN_FUSION_ORCHESTRATOR=glm 등을 설정하면 동일하게 적용.
bash "$_BASE_CHECK" "$@"
_base_rc=$?

# 기반이 exit 1(Fusion 불성립)이면 L1 감지를 할 필요 없이 그대로 종료.
if [ "$_base_rc" -ne 0 ]; then
  exit "$_base_rc"
fi

# === 2. SECURE_MODE 강제 선언 ===
# plan-fusion-secu 로 들어온 시점 자체가 보안 의도이므로 SECURE_MODE 는 항상 yes.
# (기존 plan-fusion 과 달리 "조건부 발동"이 아니라 "항상 발동" — 별도 스킬이니까.)
echo ""
echo "# ── plan-fusion-secu 확장 (SECURE_MODE + L1 도구) ──────────"
echo "SECURE_MODE=yes"
echo "SECURE_REASON=별도 -secu 스킬 진입 = 보안 검증 의도 (L1+L2 항상, codeSecurity/명시 시 L3 추가)"

# === 3. L1 정적 분석 도구 가용성 감지 ===
# 어느 도구를 돌릴 수 있는지 감지한다. run-secure-l1.sh 이 이 결과를 소비해 스택에 맞춰 조합.

# 3-1. 범용 도구 (모든 스택)
_L1_TOOLS=""
_L1_MISSING=""

check_tool() {  # $1=명령 $2=표시명
  if command -v "$1" >/dev/null 2>&1; then
    _L1_TOOLS="$_L1_TOOLS $2"
    echo "L1_TOOL_$2=ok"
  else
    _L1_MISSING="$_L1_MISSING $2"
    echo "L1_TOOL_$2=missing"
  fi
}

check_tool semgrep SEMGREP
check_tool gitleaks GITLEAKS
check_tool trufflehog TRUFFLEHOG

# 3-2. 언어별 의존성 스캐너 (스택 감지)
echo ""
echo "# ── 의존성 스캐너 (스택 감지 기반) ──"
# 작업 디렉토리는 argv 나 cwd 에서 추론 — 기본은 cwd.
_SCAN_ROOT="${PLAN_FUSION_SECU_SCAN_ROOT:-.}"

if [ -f "$_SCAN_ROOT/package-lock.json" ] || [ -f "$_SCAN_ROOT/yarn.lock" ]; then
  echo "DEP_STACK=node"
  check_tool npm NPM_AUDIT
elif [ -f "$_SCAN_ROOT/Pipfile.lock" ] || [ -f "$_SCAN_ROOT/requirements.txt" ] || [ -f "$_SCAN_ROOT/pyproject.toml" ]; then
  echo "DEP_STACK=python"
  check_tool pip-audit PIP_AUDIT
  check_tool safety SAFETY
elif [ -f "$_SCAN_ROOT/Cargo.lock" ]; then
  echo "DEP_STACK=rust"
  check_tool cargo CARGO_AUDIT
elif [ -f "$_SCAN_ROOT/Gemfile.lock" ]; then
  echo "DEP_STACK=ruby"
  check_tool bundle BUNDLE_AUDIT
elif [ -f "$_SCAN_ROOT/go.sum" ]; then
  echo "DEP_STACK=go"
  check_tool govulncheck GOVULNCHECK
else
  echo "DEP_STACK=none(의존성 파일 미감지 — CVE 스캔 생략, L1은 semgrep/gitleaks만)"
fi

# === 4. L1 능력 요약 ===
# 최소 1개 도구가 있으면 L1 가동 가능. 없으면 minimal 경고(차단 아님 — L2로 폴백).
_L1_COUNT=$(printf '%s' "$_L1_TOOLS" | wc -w | tr -d ' ')
if [ "$_L1_COUNT" -ge 1 ]; then
  echo "SECURE_L1_CAPABILITY=full(도구:$_L1_TOOLS)"
else
  echo "SECURE_L1_CAPABILITY=minimal(L1 도구 0개 — L2로 폴백, 보안 검증 품질 저하 경고)"
  echo "WARN: L1 정적 분석 도구가 하나도 없습니다. semgrep + gitleaks 설치를 권장." >&2
  # 차단은 안 함 — L2(LLM 판단)만으로도 기본 보안 평가는 가능(품질은 낮음).
fi

# 누락 도구 안내
if [ -n "${_L1_MISSING// /}" ]; then
  echo "L1_MISSING=($_L1_MISSING) — 설치 시 커버리지 확장. 필수는 아님(L1Count≥1이면 가동)."
fi

# exit 0 (기반이 통과했으므로)
exit 0
