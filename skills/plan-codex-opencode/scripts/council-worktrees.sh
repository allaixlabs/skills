#!/usr/bin/env bash
# council-worktrees.sh — Council-Code 모드의 git worktree 격리 헬퍼 (누수 방지 캡슐화)
#
# 같은 작업트리에 N개 패널을 동시 위임하면 파일 충돌·baseline 오염이 난다.
# 패널마다 독립 브랜치의 worktree를 만들어 물리 격리하고, 정리까지 책임진다.
#
# 사용 (source 후 함수 호출):
#   source "$SKILL_DIR/scripts/council-worktrees.sh"
#   council_wt_setup   "<ROOT>" "<RUN>" "<slug>" codex glm kimi
#   # 위임: codex exec -C "$RUN/wt/codex" ... / omo run -d "$RUN/wt/glm" ... / opencode run --dir "$RUN/wt/kimi" ...
#   council_wt_adopt   "<ROOT>" "<RUN>" "<채택 id>"      # 채택 패널 diff를 메인에 apply --3way
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
  [ "${#ids[@]}" -eq 0 ] && { echo "WT_FAIL: no panel ids" >&2; return 1; }
  local ts; ts=$(date +%s 2>/dev/null || echo 0)
  mkdir -p "$RUN/wt"
  # 사용자 dirty 변경 스냅샷 (워킹트리 불변 — stash 목록에 push 하지 않음)
  # ⚠️ stash create는 tracked dirty만 담는다(untracked 새 파일 제외). untracked는 worktree에
  #    전파되지 않으므로(전파하면 adopt가 패널 산출물로 오인) 감지해 경고만 한다 — 필요하면 먼저 커밋.
  if [ -n "$(git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null | head -1)" ]; then
    echo "WARN: 사용자 untracked 파일은 패널 worktree에 전파되지 않습니다(git stash create 한계). 패널 작업에 필요하면 먼저 커밋하세요." >&2
  fi
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

# council_wt_diffbase <RUN> — 패널 "순수 기여분" diff의 base 커밋을 stdout으로.
#   패널 worktree는 'HEAD + 사용자 dirty(stash)'에서 출발한다. 그래서 diff base는 HEAD가 아니라
#   그 출발점이어야 패널이 실제로 더한 변경만 나온다. stash 커밋(stash create가 만든 HEAD+dirty
#   커밋)이 정확히 그 출발점이다. 사용자 dirty가 없으면 stash.sha는 비고 → baseline.head(HEAD) 사용.
#   ⚠️ base를 무조건 HEAD로 두면 사용자 dirty가 patch에 섞여, ROOT의 기존 dirty와 충돌해
#      adopt의 apply가 통째로 실패한다(패널 산출물 유실). 종합용 diff 추출도 반드시 이 base를 쓸 것.
council_wt_diffbase() {
  local RUN="$1" stash
  stash=$(cat "$RUN/stash.sha" 2>/dev/null)
  if [ -n "$stash" ]; then printf '%s' "$stash"; else cat "$RUN/baseline.head" 2>/dev/null; fi
}

council_wt_cleanup() {
  local ROOT="$1" RUN="$2" keep_id="${3:-}" d manifest id br
  for d in "$RUN"/wt/*; do
    [ -d "$d" ] || continue
    git -C "$ROOT" worktree remove --force "$d" 2>/dev/null
  done
  git -C "$ROOT" worktree prune 2>/dev/null
  for manifest in "$RUN"/*/manifest; do
    [ -f "$manifest" ] || continue
    id=$(basename "$(dirname "$manifest")")
    [ -n "$keep_id" ] && [ "$id" = "$keep_id" ] && continue
    br=$(sed -n 's/^branch=//p' "$manifest" | head -1)
    [ -n "$br" ] || continue
    case "$br" in
      council/*) git -C "$ROOT" branch -D "$br" >/dev/null 2>&1 || true ;;
    esac
  done
}

# council_wt_adopt <ROOT> <RUN> <id> — 채택 패널 변경을 메인 작업트리에 안전 반영
council_wt_adopt() {
  local ROOT="$1" RUN="$2" id="$3"
  local base now diffbase
  base=$(cat "$RUN/baseline.head" 2>/dev/null)
  now=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)
  # 드리프트 체크는 HEAD 기준(메인이 council 중 움직였는지) — diff base와는 별개.
  if [ -n "$base" ] && [ "$base" != "$now" ]; then
    echo "ABORT: 메인 HEAD가 baseline에서 드리프트($base → $now). council 진행 중 메인이 바뀜 — 수동 확인 필요." >&2
    return 2
  fi
  # diff base는 패널 worktree의 출발점(stash 있으면 stash 커밋, 없으면 HEAD) — 사용자 dirty가
  # patch에 섞여 ROOT 기존 dirty와 충돌하는 것을 막는다. 상세는 council_wt_diffbase 주석.
  diffbase=$(council_wt_diffbase "$RUN")
  # ⚠️ git diff <base>는 untracked(패널이 새로 만든 파일)를 빠뜨린다 → add -A 후 인덱스 기준 diff로
  #    신규 파일까지 패치에 포함한다(조용한 누락 방지). worktree 인덱스만 건드리므로 ROOT엔 영향 없음.
  git -C "$RUN/wt/$id" add -A >/dev/null 2>&1
  git -C "$RUN/wt/$id" --no-pager diff --cached "$diffbase" -- > "$RUN/final.patch" 2>/dev/null
  if [ ! -s "$RUN/final.patch" ]; then
    echo "NOTE: 채택 패널 '$id' 변경 없음(빈 diff)." >&2
    return 0
  fi
  # 머지 대신 patch apply --3way: 메인 히스토리 오염 방지 + baseline dirty 충돌을 표면화
  if git -C "$ROOT" apply --3way "$RUN/final.patch" 2>/dev/null \
     || git -C "$ROOT" apply "$RUN/final.patch"; then
    echo "ADOPTED: $id → $ROOT ($RUN/final.patch 적용)"
  else
    echo "APPLY_CONFLICT: $RUN/final.patch 수동 머지 필요 (사용자 dirty와 충돌 가능)" >&2
    return 1
  fi
}

# ── 직접 실행 시 dry-run 자가 점검 (임시 레포에서 setup→cleanup 누수 0 확인) ──
if [ -n "${BASH_SOURCE:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then  # zsh엔 BASH_SOURCE 없음 → source 시 self-test 스킵
  echo "[dry-run] council-worktrees.sh 자가 점검"
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/cwt-selftest.XXXXXX")
  ( cd "$TMP" && git init -q && git config user.email t@t && git config user.name t \
      && echo hello > a.txt && git add a.txt && git commit -qm init ) || { echo "git init 실패"; exit 1; }
  RUN=$(mktemp -d "${TMPDIR:-/tmp}/cwt-run.XXXXXX")
  council_wt_setup "$TMP" "$RUN" "selftest" alpha beta
  echo "--- worktree list (메인 + 2개 = 3행 기대) ---"; git -C "$TMP" worktree list
  council_wt_cleanup "$TMP" "$RUN"
  echo "--- cleanup 후 (메인 1행만 기대) ---"; git -C "$TMP" worktree list
  wt_leak=$(git -C "$TMP" worktree list | grep -c "$RUN" || true)
  branch_leak=$(git -C "$TMP" branch --list 'council/*' | wc -l | tr -d ' ')
  echo "WORKTREE_LEAK_COUNT=$wt_leak  (0이어야 정상)"
  echo "BRANCH_LEAK_COUNT=$branch_leak  (0이어야 정상)"
  rm -rf "$TMP" "$RUN"
  [ "$wt_leak" = "0" ] && [ "$branch_leak" = "0" ] && echo "SELFTEST=pass" || echo "SELFTEST=FAIL"
fi
