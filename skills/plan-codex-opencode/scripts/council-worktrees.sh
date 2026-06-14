#!/usr/bin/env bash
# council-worktrees.sh — Council-Code 모드의 git worktree 격리 헬퍼 (누수 방지 캡슐화)
#
# 같은 작업트리에 N개 패널을 동시 위임하면 파일 충돌·baseline 오염이 난다.
# 패널마다 독립 브랜치의 worktree를 만들어 물리 격리하고, 정리까지 책임진다.
#
# 사용 (source 후 함수 호출):
#   source "$SKILL_DIR/scripts/council-worktrees.sh"
#   council_wt_setup   "<ROOT>" "<RUN>" "<slug>" codex glm kimi
#   trap 'council_wt_cleanup "<ROOT>" "<RUN>"' EXIT      # 누수 방지 (프로세스 death 대비)
#   # 위임: codex exec -C "$RUN/wt/codex" ... / omo run -d "$RUN/wt/glm" ... / opencode run --dir "$RUN/wt/kimi" ...
#   council_wt_adopt   "<ROOT>" "<RUN>" "<채택 id>"      # 채택 패널 diff를 메인에 apply --3way
#   council_wt_cleanup "<ROOT>" "<RUN>"                  # 전체 worktree 제거 + prune
#
# 직접 실행하면 임시 레포에서 setup→cleanup 누수 0을 자가 점검한다 (E2E 검증용):
#   bash scripts/council-worktrees.sh
#
# 설계 원칙:
#   - 각 패널은 council/<slug>-<id>-<ts> 독립 브랜치 worktree에서 작업 → 동시 충돌 0
#   - 사용자 uncommitted 변경은 git stash create(워킹트리 불변) → 각 worktree에 apply (동일 출발선)
#   - cleanup은 worktree remove --force + prune 까지 (폴더만 지우면 .git/worktrees 에 stale 등록 잔존)
#   - 채택 브랜치는 자동 삭제하지 않는다 (호출측이 보존 여부 결정)
set -u

# council_wt_setup <ROOT> <RUN> <slug> <id...>
council_wt_setup() {
  local ROOT="$1" RUN="$2" SLUG="$3"; shift 3
  local ids=("$@")
  local ts; ts=$(date +%s 2>/dev/null || echo 0)
  mkdir -p "$RUN/wt"
  # 사용자 dirty 변경 스냅샷 (워킹트리 불변 — stash 목록에 push 하지 않음)
  local stash; stash=$(git -C "$ROOT" stash create 2>/dev/null || echo "")
  printf '%s' "$stash" > "$RUN/stash.sha"
  git -C "$ROOT" rev-parse HEAD > "$RUN/baseline.head" 2>/dev/null
  local id wt br
  for id in "${ids[@]}"; do
    wt="$RUN/wt/$id"; br="council/${SLUG}-${id}-${ts}"
    mkdir -p "$RUN/$id"
    if git -C "$ROOT" worktree add -b "$br" "$wt" HEAD >>"$RUN/$id/setup.log" 2>&1; then
      echo "worktree=$wt" >> "$RUN/$id/manifest"
      echo "branch=$br"   >> "$RUN/$id/manifest"
      if [ -n "$stash" ]; then
        git -C "$wt" stash apply "$stash" >>"$RUN/$id/setup.log" 2>&1 \
          || echo "WARN: stash apply 실패 (baseline 변경 미적용) in $id" >> "$RUN/$id/manifest"
      fi
      echo "WT_READY[$id]=$wt"
    else
      echo "WT_FAIL[$id] — $RUN/$id/setup.log 확인" >&2
    fi
  done
}

# council_wt_cleanup <ROOT> <RUN> — 모든 council worktree 제거 + stale 등록 prune
council_wt_cleanup() {
  local ROOT="$1" RUN="$2" d
  for d in "$RUN"/wt/*; do
    [ -d "$d" ] || continue
    git -C "$ROOT" worktree remove --force "$d" 2>/dev/null
  done
  git -C "$ROOT" worktree prune 2>/dev/null
  # 비채택 council/* 브랜치 삭제는 호출측에서 명시적으로 (채택 브랜치 보존 위해 자동삭제 안 함)
}

# council_wt_adopt <ROOT> <RUN> <id> — 채택 패널 변경을 메인 작업트리에 안전 반영
council_wt_adopt() {
  local ROOT="$1" RUN="$2" id="$3"
  local base now
  base=$(cat "$RUN/baseline.head" 2>/dev/null)
  now=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)
  if [ -n "$base" ] && [ "$base" != "$now" ]; then
    echo "ABORT: 메인 HEAD가 baseline에서 드리프트($base → $now). council 진행 중 메인이 바뀜 — 수동 확인 필요." >&2
    return 2
  fi
  git -C "$RUN/wt/$id" --no-pager diff "$base" -- > "$RUN/final.patch" 2>/dev/null
  if [ ! -s "$RUN/final.patch" ]; then
    echo "NOTE: 채택 패널 '$id' 변경 없음(빈 diff)." >&2
    return 0
  fi
  # 머지 대신 patch apply --3way: 메인 히스토리 오염 방지 + baseline dirty 충돌을 표면화
  if git -C "$ROOT" apply --3way "$RUN/final.patch"; then
    echo "ADOPTED: $id → $ROOT ($RUN/final.patch 적용)"
  else
    echo "APPLY_CONFLICT: $RUN/final.patch 수동 머지 필요 (사용자 dirty와 충돌 가능)" >&2
    return 1
  fi
}

# ── 직접 실행 시 dry-run 자가 점검 (임시 레포에서 setup→cleanup 누수 0 확인) ──
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  echo "[dry-run] council-worktrees.sh 자가 점검"
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/cwt-selftest.XXXXXX")
  ( cd "$TMP" && git init -q && git config user.email t@t && git config user.name t \
      && echo hello > a.txt && git add a.txt && git commit -qm init ) || { echo "git init 실패"; exit 1; }
  RUN=$(mktemp -d "${TMPDIR:-/tmp}/cwt-run.XXXXXX")
  council_wt_setup "$TMP" "$RUN" "selftest" alpha beta
  echo "--- worktree list (메인 + 2개 = 3행 기대) ---"; git -C "$TMP" worktree list
  council_wt_cleanup "$TMP" "$RUN"
  echo "--- cleanup 후 (메인 1행만 기대) ---"; git -C "$TMP" worktree list
  leak=$(git -C "$TMP" worktree list | grep -c "$RUN" || true)
  echo "LEAK_COUNT=$leak  (0이어야 정상)"
  rm -rf "$TMP" "$RUN"
  [ "$leak" = "0" ] && echo "SELFTEST=pass" || echo "SELFTEST=FAIL"
fi
