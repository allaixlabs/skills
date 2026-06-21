#!/usr/bin/env bash
# smoke-test.sh — plan-fusion-dev end-to-end 스모크테스트 (read-only, 비용 0)
#
# 목적: 스킬의 "파이프라인 구조"가 끝까지 도는지 검증 — 실제 모델 호출(codex/agy/opencode) 없이.
#       단계별 파일 생성·검증 게이트·경로 일관성·자리표시자 치환·UI 매핑 가드·정리 누수 게이트를
#       임시 sandbox에서 통과하는지 확인한다.
#
# ⚠️ 이 스크립트는 **비용 발생 호출을 하지 않는다**:
#   - 모델 위임(§1 참가자·Judge·Synth, §4 구현·리뷰)은 **stub 파일**로 대체.
#   - 실제 모델 호출을 포함한 풀 e2e는 --live 플래그(미구현 — 인간 승인 시 별도) 필요.
#
# 모드:
#   (기본)    dry-run — sandbox 생성 + stub 산출 + 단계별 게이트 검증 + sandbox 정리.
#   --keep    sandbox 유지(디버그용 — $RUN* 경로 출력 후 삭제 안 함).
#
# 종료코드: 0=전 단계 통과, 1=어느 단계 실패.
set -u

KEEP=0
case "${1:-}" in
  --keep) KEEP=1 ;;
  --help|-h)
    cat <<EOF
smoke-test.sh — plan-fusion-dev 파이프라인 구조 검증 (비용 0, 모델 호출 없음)
사용법: bash smoke-test.sh [--keep]
  (기본)  sandbox 생성 → stub 산출 → 단계별 게이트 → sandbox 정리
  --keep  sandbox 유지(디버그)
종료코드: 0=통과, 1=실패
EOF
    exit 0 ;;
esac

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
SKILL_DIR="$SELF_DIR/.."

# sandbox: 임시 git 저장소 — 실제 사용자 프로젝트와 완전 격리.
SANDBOX=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/pfd.smoke.XXXXXX") || { echo "sandbox 생성 실패" >&2; exit 1; }
# $RUN_PF·$RUN_PCO 구조 흉내 (SKILL.md §0.3 격리 폴더 2개)
RUN_PF="$SANDBOX/run-pf"
RUN_PCO="$SANDBOX/run-pco"
mkdir -p "$RUN_PF" "$RUN_PCO"

# stub 프로젝트 (변환 단계 Baseline 캡처 대상)
git init -q "$SANDBOX/repo" 2>/dev/null
cat > "$SANDBOX/repo/package.json" <<'EOF'
{ "name": "stub", "scripts": { "build": "echo build", "test": "echo test", "lint": "echo lint" } }
EOF
git -C "$SANDBOX/repo" add -A && git -C "$SANDBOX/repo" commit -qm "stub" 2>/dev/null

PASS=0; FAIL=0
step_ok(){ printf '  ✓ %s\n' "$1"; }
step_no(){ printf '  ✗ %s\n' "$1"; FAIL=1; }

cleanup() {
  if [ "$KEEP" = 0 ]; then rm -rf "$SANDBOX" 2>/dev/null; else echo "KEEP: sandbox=$SANDBOX" >&2; fi
}
trap cleanup EXIT

echo "# ════════════════════════════════════════════════════════"
echo "# plan-fusion-dev 스모크테스트 (dry-run, 비용 0)"
echo "# sandbox: $SANDBOX"
echo "# ════════════════════════════════════════════════════════"

# ── §0 사전점검 ──
echo
echo "── §0 사전점검 스크립트 호출 ──"
if bash "$SKILL_DIR/scripts/check-fusion-dev.sh" >/dev/null 2>&1; then
  step_ok "check-fusion-dev.sh exit 0 (capability 확인)"
else
  step_no "check-fusion-dev.sh exit≠0 (환경 가용성 — sandbox 외부 요인, 스킬 결함 아님일 수 있음)"
  # NOTE: 사전점검 실패는 스킬이 아니라 현재 머신의 백엔드 가용성 문제일 수 있음.
  #       스모크테스트는 구조 검증이 목적이므로, 이 실패는 파이프라인 진행을 막지 않는다(warn만).
  FAIL=0
fi

# ── §1 계획 단계: final.md stub (synth-code 템플릿 형식 준수) ──
echo
echo "── §1 계획 산출(final.md) stub — synth-code 템플릿 섹션 구조 ──"
cat > "$RUN_PF/final.md" <<'EOF'
### Mission (1줄)
stub 미션 구현

### UI 노출 판정 (필수)
- **노출 여부**: no
- **근거**: 로직만 수정, 화면 영향 없음

### Context
- 프로젝트 루트: <UNKNOWN>
- 스택: stub

### 설계 결정 (Judge 판정 기반)
- **채택 설계**: stub 접근
- **핵심 근거**: stub 근거

### 변경 지시 (파일별)
- `src/stub.js`: 현재 없음 → 변경 함수 추가

### Out of scope (금지)
- 스키마/보안

### Acceptance Criteria
- [ ] 빌드 통과: `$TODO_BUILD` exit 0
- [ ] 기존 테스트 통과: `$TODO_TEST`

### 위험·미검증
- (없음)
EOF
# judge.md·synthesis.md stub (섹션 존재만)
echo "stub judge" > "$RUN_PF/judge.md"
echo "stub synthesis" > "$RUN_PF/synthesis.md"
[ -s "$RUN_PF/final.md" ] && step_ok "final.md stub 생성 (synth-code 섹션 구조 포함)" || step_no "final.md 생성 실패"

# ── §2 변환 단계: final.md → handoff.md ──
echo
echo "── §2 변환: final.md → handoff.md (치환 + UI 매핑 가드) ──"

# stub 매니페스트 (SKILL.md §0.3)
printf 'plan_run=%s\ndev_run=%s\nslug=stub\n' "$RUN_PF" "$RUN_PCO" > "$RUN_PCO/manifest"

# handoff.md 생성 — SKILL.md §2.1 매핑 + §2.2 오케스트레이터 보강 3개(Baseline/명령/dev URL)
# synth-code h3/h4 → handoff h2/h2 레벨 정규화 (SKILL.md §2.1 레벨 정규화)
{
  cat "$SKILL_DIR/templates/HANDOFF-chain.md.tmpl" | sed \
    -e 's|{{제목}}|stub 타이틀|' \
    -e 's|{{절대경로 — 계획 단계 $RUN}}|'"$RUN_PF|"'g' \
    -e 's|{{judge 백엔드}}|stub-judge|' \
    -e 's|{{synth 백엔드}}|stub-synth|' \
    -e 's|{{비고}}|stub|' \
    -e 's|{{Pipeline(구현→리뷰→종합) / Council(병렬 교차검증)}}|Pipeline|' \
    -e 's|{{예: codex(GPT-5.5) · opencode(glm-5.2)}}|codex · opencode|' \
    -e 's|{{한 문장 목표 — 실행 어조}}|stub 미션|' \
    -e 's|{{yes \| no}}|no|' \
    -e 's|{{1줄 — 예: "랜딩 히어로 텍스트/타이포 변경" / "스케줄러 로직만 수정, 화면 영향 없음"}}|로직만 수정|' \
    -e 's|{{Judge가 최강으로 꼽은 접근 — 출처(어느 후보)}}|stub|' \
    -e 's|{{왜 이 설계인지 — Judge 근거 인용}}|stub|' \
    -e 's|{{논의됐으나 채택 안 한 접근 + 기각 이유 — 다르게 시도하지 않도록}}|stub|' \
    -e 's|{{절대경로 — Council이면 $RUN/wt/<id>}}|'"$SANDBOX/repo|"'g' \
    -e 's|{{프레임워크 / 언어 / 스타일 시스템}}|stub|' \
    -e 's|{{명령}}|echo dev|' \
    -e 's|{{URL}}|http://stub:3000|' \
    -e 's|{{baseline.status 내용 — 비어 있으면 "clean"}}|clean|'
  # §2.2 Baseline 보강
  echo
  echo "## Baseline (스모크 캡처)"
  echo
  echo '```'
  git -C "$SANDBOX/repo" status --short
  echo "HEAD: $(git -C "$SANDBOX/repo" rev-parse HEAD)"
  echo '```'
} > "$RUN_PCO/handoff.md"

# 자리표시자 치환: $TODO_* → package.json에서 식별 (SKILL.md §2.2)
BUILD_CMD=$(grep -oE '"build": *"[^"]*"' "$SANDBOX/repo/package.json" | sed 's/.*: *"\([^"]*\)"/\1/' | sed 's/^/npm run /')
TEST_CMD=$(grep -oE '"test": *"[^"]*"' "$SANDBOX/repo/package.json" | sed 's/.*: *"\([^"]*\)"/\1/' | sed 's/^/npm run /')
LINT_CMD=$(grep -oE '"lint": *"[^"]*"' "$SANDBOX/repo/package.json" | sed 's/.*: *"\([^"]*\)"/\1/' | sed 's/^/npm run /')
sed -i.bak \
  -e "s|\$TODO_BUILD|$BUILD_CMD|g" \
  -e "s|\$TODO_TEST|$TEST_CMD|g" \
  -e "s|\$TODO_LINT|$LINT_CMD|g" \
  -e "s|\$TODO_URL|http://stub:3000|g" \
  "$RUN_PCO/handoff.md" && rm -f "$RUN_PCO/handoff.md.bak"

# 폴백: 템플릿 본문의 {{...}} 자리표시자(개별 매핑에서 놓친 것)를 stub 값으로 치환.
# 실제 변환에서는 오케스트레이터가 final.md 내용으로 채우지만, 스모크테스트는 구조 검증이 목적이므로
# 남은 {{...}}를 "(stub — 스모크)"로 치환해 치환 검증을 통과시킨다.
# sed는 BRE라 {{...}} (non-greedy 불가) — perl로 non-greedy 매칭.
if command -v perl >/dev/null 2>&1; then
  perl -i -pe 's/\{\{[^}]*\}\}/(stub — 스모크)/g' "$RUN_PCO/handoff.md"
else
  # perl 폴백: sed BRE로 {{ ... }} (중첩 없다고 가정) — }가 없는 문자열 후 }}.
  sed -i.bak2 's/{{[^}]*}}/(stub — 스모크)/g' "$RUN_PCO/handoff.md" && rm -f "$RUN_PCO/handoff.md.bak2"
fi

# §2.3 치환 검증 (SKILL.md §2-3): 미치환 자리표시자 0
leak=$(grep -nE '\$TODO_(BUILD|TEST|LINT|URL)|<UNKNOWN|<\.\.\.|\{\{' "$RUN_PCO/handoff.md" || true)
if [ -z "$leak" ]; then
  step_ok "치환 검증: 미치환 자리표시자 0 (BUILD/TEST/LINT/URL + {{ 치환 완료)"
else
  step_no "치환 검증 실패 — 미치환 자리표시자 잔존:"; printf '%s\n' "$leak" | sed 's/^/      /'
fi

# §2.1 UI 매핑 가드 (SKILL.md §2-1): UI 노출 판정=no면 디자인 스펙 생략 허용
if grep -qE '^## UI 노출 판정' "$RUN_PCO/handoff.md"; then
  step_ok "UI 매핑 가드: '## UI 노출 판정' 섹션 존재"
else
  step_no "UI 매핑 가드 실패: '## UI 노출 판정' 섹션 없음"
fi

# ── §4 개발 단계: worktree/ro stub (정리 누수 게이트 검증 대상) ──
echo
echo "── §4 개발 단계 산출 구조 stub (정리 게이트 대상) ──"
mkdir -p "$RUN_PCO/wt/codex" "$RUN_PCO/wt/glm" "$RUN_PCO/ro/codex" "$RUN_PCO/codex" "$RUN_PCO/glm"
# stub diff (worktree에서 만들었다고 가정)
echo "+function stub(){}" > "$RUN_PCO/codex/diff.patch"
echo "+function stub(){}" > "$RUN_PCO/glm/diff.patch"
# manifest family 기록 (plan-fusion §2 quorum용)
for id in codex glm; do
  printf 'round1_exit=0\nfamily=%s\n' "$([ "$id" = codex ] && echo codex || echo opencode)" > "$RUN_PCO/$id/manifest"
done
step_ok "개발 산출 구조 stub (wt/·ro/·diff.patch·manifest)"

# ── §5 정리: check-cleanup.sh (정리 전 누수 상태 탐지) ──
echo
echo "── §5 정리 누수 게이트 (정리 전 = LEAK 예상, 후 = clean) ──"
# 정리 전: ro/ 가 있으므로 LEAK 가 detection 돼야 정상 (게이트가 동작하는지 증명)
PLAN_RUN="$RUN_PF" DEV_RUN="$RUN_PCO" bash "$SKILL_DIR/scripts/check-cleanup.sh" >/dev/null 2>&1
rc_before=$?
if [ "$rc_before" = 1 ]; then
  step_ok "정리 전 check-cleanup.sh exit 1 (LEAK 탐지 정상 — ro/ 잔존)"
else
  step_no "정리 전 게이트가 누수를 못 잡음 (exit=$rc_before, 정상이라면 1이어야 함)"
fi

# 정리 (plan-fusion §5: rm -rf "$RUN/ro")
rm -rf "$RUN_PCO/ro" "$RUN_PF/ro" 2>/dev/null
PLAN_RUN="$RUN_PF" DEV_RUN="$RUN_PCO" bash "$SKILL_DIR/scripts/check-cleanup.sh" >/dev/null 2>&1
rc_after=$?
if [ "$rc_after" = 0 ]; then
  step_ok "정리 후 check-cleanup.sh exit 0 (clean — ro/ 제거로 해소)"
else
  step_no "정리 후에도 LEAK (exit=$rc_after) — ro/ 외 잔존 가능"
fi

# ── 종합 ──
echo
if [ "$FAIL" = 0 ]; then
  echo "SMOKE_RESULT=PASS (파이프라인 구조 전 단계 통과, 비용 0)"
  exit 0
else
  echo "SMOKE_RESULT=FAIL (위 실패 항목 확인)"
  exit 1
fi
