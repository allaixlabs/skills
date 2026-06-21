#!/usr/bin/env bash
# check-cleanup.sh — plan-fusion-dev 정리 누수 점검 (read-only, 아무것도 수정하지 않음)
#
# 체이닝 스킬은 두 개의 격리 폴더($RUN_PF 계획 · $RUN_PCO 개발)를 만들고,
# 양쪽 모두 worktree · council/* 브랜치 · ro/ 사본 디렉토리를 생성한다.
# 하위 스킬 정리 단계(council_wt_cleanup)가 wt/와 council/*만 다룬다고 가정할 수 없다 —
# REPORT 직전에 이 스크립트로 잔존 0을 **기계적으로** 확인한다(SKILL.md §5 정리 점검).
#
#   - plan-fusion/references/fusion.md §5: "council_wt_cleanup은 ro/를 다루지 않는다"
#   - council/* 브랜치·worktree는 adopt/cleanup 실패 시 남을 수 있다.
#
# 입력(env):
#   PLAN_RUN($RUN_PF) · DEV_RUN($RUN_PCO) 둘 다 또는 하나만.
#   없으면 현재 git 저장소의 worktree/council 브랜치 잔존만 점검(스케일다운).
# stdout: KEY=VALUE. exit 0=잔존 0(정상), exit 1=잔존 발견(누수 — REPORT 전 사용자 알림/수동 정리).
set -u

PLAN_RUN="${PLAN_RUN:-}"
DEV_RUN="${DEV_RUN:-}"

# 루트 git 저장소 식별 — worktree list는 gitroot 기준. SKILL_DIR은 현재 스크립트 위치.
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
# 계정 루트를 관통하는 git 저장소를 찾는다(스킬은 사용자 프로젝트 안에서 돈다).
GIT_ROOT=$(git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null || echo "")

wt_leak=0
branch_leak=0
ro_leak=0
leak_detail=""

# 1) git worktree 잔존 — council/* 경로의 worktree가 남아있으면 누수.
#    스킬이 만드는 worktree는 항상 $RUN*/wt/<id> 경로에 있다(fusion.md §1·§5).
if [ -n "$GIT_ROOT" ]; then
  # worktree list 줄 중 경로에 /wt/ 또는 /council/ 이 포함된 것 = 스킬이 만든 worktree.
  wt_lines=$(git -C "$GIT_ROOT" worktree list --porcelain 2>/dev/null | grep -E '^worktree ' | grep -E '/(wt|council)/' || true)
  if [ -n "$wt_lines" ]; then
    wt_leak=1
    leak_detail=$(printf '%s\n[worktree 누수]' "%s" "$wt_lines" "$leak_detail")
  fi
fi

# 2) council/* 브랜치 잔존 — cleanup이 브랜치 삭제를 놓치면 남는다.
if [ -n "$GIT_ROOT" ]; then
  br_lines=$(git -C "$GIT_ROOT" branch --list 'council/*' 2>/dev/null || true)
  if [ -n "$br_lines" ]; then
    branch_leak=1
    leak_detail=$(printf '%s\n[branch 누수]' "%s" "$br_lines" "$leak_detail")
  fi
fi

# 3) ro/ 디렉토리 잔존 — council_wt_cleanup이 다루지 않는 영역(fusion.md §5).
#    $RUN_PF/$RUN_PCO 경로가 전달된 경우만 점검(절대경로여야 안전).
for run in "$PLAN_RUN" "$DEV_RUN"; do
  [ -n "$run" ] || continue
  case "$run" in
    /*) ;;  # 절대경로만 — 상대경로/입력값 신뢰 금지
    *) continue ;;
  esac
  if [ -d "$run/ro" ]; then
    ro_leak=1
    leak_detail=$(printf '%s\n[ro/ 누수] %s/ro' "$leak_detail" "$run")
  fi
done

total=$((wt_leak + branch_leak + ro_leak))

echo "CLEANUP_WORKTREE_LEAK=$wt_leak"
echo "CLEANUP_BRANCH_LEAK=$branch_leak"
echo "CLEANUP_RO_LEAK=$ro_leak"
echo "CLEANUP_TOTAL_LEAK=$total"

if [ "$total" -eq 0 ]; then
  echo "CLEANUP_STATUS=clean"
  exit 0
else
  echo "CLEANUP_STATUS=LEAK(정리 누수 — REPORT 전 council_wt_cleanup 재호출 또는 수동 정리 권장)"
  # 상세는 stderr로 — stdout KEY=VALUE 파싱을 방해하지 않게.
  printf '%s\n' "$leak_detail" >&2
  exit 1
fi
