#!/usr/bin/env bash
# council-worktrees.sh — git worktree 격리 헬퍼 (누수 방지 캡슐화)
# ⚠️ 이 파일은 plan-codex-opencode(정본)·plan-fusion(동기 복제본) 두 곳에 동일 내용으로 존재한다.
#    심링크가 아니라 실파일 복제다(Windows/core.symlinks 배포 호환). 수정은 정본(plan-codex-opencode)에서
#    한 뒤 plan-fusion 쪽으로 복사해 동기화하라. plan-fusion/check-fusion.sh가 두 파일 diff로 드리프트를 경고한다.
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
#   - 각 패널은 council/<slug>-<id>-<ts>-<pid>-<run> 독립 브랜치 worktree에서 작업 → 동시 충돌 0
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
  # stash create는 성공 시 커밋 SHA(40hex)를 내고, 변경 없으면 빈 출력을 낸다.
  # ⚠️ PATH의 git이 wrapper(rtk 등)면 "ok stash create" 같은 비-SHA 문자열을 내보낼 수 있다 →
  #    이를 SHA로 쓰면 council_wt_diffbase → council_wt_adopt 의 `git diff <base>`가 bad revision으로 ABORT된다.
  #    SHA 형식(40 hex)인 경우만 저장하고, 아니면 빈 값(변경 없음과 동일 취급)으로 둔다.
  case "$stash" in
    *[!0-9a-f]* | ??????????????????????????????????????) : ;;   # 40 hex 통과 (두 패턴: 비hex포함 OR 정확히 40자리)
    *) stash="" ;;                                               # 그 외(빈 문자열·wrapper 노이즈) = 변경 없음
  esac
  # 엄격히: 정확히 40자리 hex인지 재확인 (위 case는 보조)
  if ! printf '%s' "$stash" | grep -qE '^[0-9a-f]{40}$'; then stash=""; fi
  printf '%s' "$stash" > "$RUN/stash.sha"
  git -C "$ROOT" rev-parse HEAD > "$RUN/baseline.head" 2>/dev/null
  git -C "$ROOT" status --porcelain=v1 --untracked-files=all > "$RUN/baseline.status" 2>/dev/null || :
  local id wt br ok=0 fail=0
  for id in "${ids[@]}"; do
    # ts-PID-RUN 접미로 동일 slug 동시/연속 실행의 브랜치명 충돌 방지.
    # RUN basename은 mktemp -d로 런별 유니크 → 같은 초·같은 PID로 두 번 setup해도 브랜치명이 충돌하지 않는다.
    wt="$RUN/wt/$id"; br="council/${SLUG}-${id}-${ts}-$$-$(basename "$RUN")"
    mkdir -p "$RUN/$id"
    if git -C "$ROOT" worktree add -b "$br" "$wt" HEAD >>"$RUN/$id/setup.log" 2>&1; then
      echo "worktree=$wt" >> "$RUN/$id/manifest"
      echo "branch=$br"   >> "$RUN/$id/manifest"
      if [ -n "$stash" ]; then
        if git -C "$wt" stash apply "$stash" >>"$RUN/$id/setup.log" 2>&1; then :; else
          echo "WARN: stash apply 실패 (baseline 변경 미적용) in $id" >> "$RUN/$id/manifest"
          # ⚠️ 출발선(사용자 dirty) 불일치 — worktree는 쓸 수 있으나 baseline이 다름. 호출측 인지용 신호.
          echo "WT_STASH_FAIL[$id]=$wt" >&2
        fi
      fi
      echo "WT_READY[$id]=$wt"
      ok=$((ok+1))
    else
      echo "WT_FAIL[$id] — $RUN/$id/setup.log 확인" >&2
      fail=$((fail+1))
    fi
  done
  # 결과 집계: 반환값으로 성공/부분/전체실패를 신호한다(호출측이 $?로 판정 — stdout 파싱 의존 제거).
  #   0=전부 성공, 1=전부 실패, 3=부분 성공(일부 worktree 실패). 이전엔 partial이 echo만 하고 $?=0이라
  #   호출측이 stdout(WT_SETUP_RESULT=partial)을 안 보면 부분실패를 성공으로 오판했다.
  if [ "$ok" -eq 0 ]; then echo "WT_SETUP_RESULT=fail (0/$((ok+fail)))" >&2; return 1
  elif [ "$fail" -gt 0 ]; then echo "WT_SETUP_RESULT=partial ($ok/$((ok+fail)))"; return 3
  else echo "WT_SETUP_RESULT=ok ($ok/$((ok+fail)))"; return 0; fi
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
  local cleanup_failed=0 cleanup_failed_items=""
  for d in "$RUN"/wt/*; do
    [ -d "$d" ] || continue
    # keep_id worktree는 보존(호출측이 명시 보존 요청 — 미커밋 작업 유실 방지). 이전엔 keep_id가 아래 branch 루프에서
    # 브랜치만 보존하고 worktree는 여기서 force-remove해, keep_id 디렉토리의 미커밋 변경이 삭제되는 버그가 있었다.
    [ -n "$keep_id" ] && [ "$(basename "$d")" = "$keep_id" ] && continue
    if ! git -C "$ROOT" worktree remove --force "$d" 2>/dev/null; then
      cleanup_failed=$((cleanup_failed+1))
      cleanup_failed_items="${cleanup_failed_items} worktree:$d"
    fi
  done
  git -C "$ROOT" worktree prune 2>/dev/null
  for manifest in "$RUN"/*/manifest; do
    [ -f "$manifest" ] || continue
    id=$(basename "$(dirname "$manifest")")
    [ -n "$keep_id" ] && [ "$id" = "$keep_id" ] && continue
    br=$(sed -n 's/^branch=//p' "$manifest" | head -1)
    [ -n "$br" ] || continue
    case "$br" in
      council/*)
        if ! git -C "$ROOT" branch -D "$br" >/dev/null 2>&1; then
          cleanup_failed=$((cleanup_failed+1))
          cleanup_failed_items="${cleanup_failed_items} branch:$br"
        fi
        ;;
    esac
  done
  if [ "$cleanup_failed" -gt 0 ]; then
    echo "CLEANUP_FAILED=$cleanup_failed$cleanup_failed_items" >&2
    return 1   # 누수(worktree/branch 잔존)를 $?로 신호 — 이전엔 무조건 return 0이라 호출측이 누수를 못 잡았다
  fi
  return 0
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
  # 채택 전 전제 검증: diffbase·worktree 부재를 "빈 diff(변경 없음)"와 혼동하면 실패를 성공으로 오판한다.
  if [ -z "$diffbase" ]; then
    echo "ABORT: diffbase 산출 실패(stash.sha·baseline.head 부재) — 채택 불가." >&2; return 2
  fi
  if [ ! -d "$RUN/wt/$id" ]; then
    echo "ABORT: 채택 대상 worktree 없음: $RUN/wt/$id (setup 실패 가능)." >&2; return 2
  fi
  # ⚠️ stash apply가 실패한 패널은 사용자 dirty가 worktree에 반영되지 않았는데 diffbase는 stash 커밋(HEAD+dirty)이라,
  #    diff에 사용자 dirty를 되돌리는 역헝크가 섞여 ROOT에 손상 patch가 적용된다(사용자 미커밋 작업 유실 위험).
  #    setup이 manifest에 남긴 'stash apply 실패' 마커를 보고 그 패널은 채택을 거부한다(diffbase가 HEAD가 아닌 경우만 위험).
  if [ -f "$RUN/$id/manifest" ] && grep -q 'stash apply 실패' "$RUN/$id/manifest" 2>/dev/null; then
    echo "ABORT: 패널 '$id'는 stash apply 실패로 baseline 불일치(worktree에 사용자 dirty 미반영) — diffbase(stash)와 어긋나 손상 patch 위험. 채택 불가(수동 확인)." >&2
    return 2
  fi
  # ⚠️ git diff <base>는 untracked(패널이 새로 만든 파일)를 빠뜨린다 → add -A 후 인덱스 기준 diff로
  #    신규 파일까지 패치에 포함한다(조용한 누락 방지). worktree 인덱스만 건드리므로 ROOT엔 영향 없음.
  #    오류를 삼키지 않도록 stderr는 setup.log로(이전엔 2>/dev/null로 조용히 흡수).
  # ⚠️ git add/diff 종료코드를 검사한다 — index lock·권한 오류로 실패하면 final.patch가 비거나 깨지는데,
  #    아래 'if [ ! -s final.patch ]'가 그걸 "변경 없음(return 0)"으로 오판하면 채택 실패를 성공으로 둔갑시킨다.
  #    (git diff는 --exit-code 미지정이라 정상 시 항상 0, 실제 오류일 때만 nonzero → 빈 diff를 오류로 오판하지 않음.)
  git -C "$RUN/wt/$id" add -A 2>>"$RUN/$id/setup.log" || {
    echo "ABORT: '$id' git add -A 실패(index lock·권한 등) — 빈 diff를 '변경 없음'으로 오판 방지." >&2; return 2; }
  git -C "$RUN/wt/$id" --no-pager diff --cached "$diffbase" -- > "$RUN/final.patch" 2>>"$RUN/$id/setup.log" || {
    echo "ABORT: '$id' git diff 실패 — final.patch 신뢰 불가." >&2; return 2; }
  if [ ! -s "$RUN/final.patch" ]; then
    echo "NOTE: 채택 패널 '$id' 변경 없음(빈 diff) — 전제 정상, 실제로 더한 변경이 없음." >&2
    return 0
  fi
  # 머지 대신 patch apply --3way: 메인 히스토리 오염 방지 + baseline dirty 충돌을 표면화.
  # ⚠️ --3way 실패 후 plain apply 재시도는 금물 — plain은 --3way보다 엄격해 무조건 실패하고
  #    충돌 상태만 가중시킨다. 단일 --3way로 시도하고 실패 시 그대로 표면화한다.
  local baseline_status now_status
  baseline_status=$(cat "$RUN/baseline.status" 2>/dev/null || echo "")
  now_status=$(git -C "$ROOT" status --porcelain=v1 --untracked-files=all 2>/dev/null || echo "")
  if [ "$baseline_status" != "$now_status" ]; then
    echo "WARN: council 시작 후 ROOT에 새 변경 감지, --3way 충돌 가능" >&2
  fi
  if git -C "$ROOT" apply --3way "$RUN/final.patch"; then
    echo "ADOPTED: $id → $ROOT ($RUN/final.patch 적용)"
  else
    echo "APPLY_CONFLICT: $RUN/final.patch 가 깨끗이 적용되지 않음(사용자 dirty와 충돌 가능) — 수동 머지 필요." >&2
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

  # ── 실패 경로 점검 (N-B 계약: 실패가 성공으로 둔갑하지 않는지) ──
  echo "--- 실패 경로 ---"
  RUN2=$(mktemp -d "${TMPDIR:-/tmp}/cwt-run2.XXXXXX")
  if council_wt_setup "$TMP/NO_SUCH_REPO" "$RUN2" "selftest" x >/dev/null 2>&1; then setup_fail_ok="FAIL"; else setup_fail_ok="pass"; fi
  echo "SETUP_ALLFAIL_RETURNS_NONZERO=$setup_fail_ok"
  RUN3=$(mktemp -d "${TMPDIR:-/tmp}/cwt-run3.XXXXXX")
  council_wt_setup "$TMP" "$RUN3" "selftest" solo >/dev/null 2>&1
  council_wt_adopt "$TMP" "$RUN3" "ghost" >/dev/null 2>&1; rc=$?
  [ "$rc" = "2" ] && adopt_missing_ok="pass" || adopt_missing_ok="FAIL(rc=$rc)"
  echo "ADOPT_MISSING_WT_RETURNS_2=$adopt_missing_ok"
  council_wt_adopt "$TMP" "$RUN3" "solo" >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] && adopt_empty_ok="pass" || adopt_empty_ok="FAIL(rc=$rc)"
  echo "ADOPT_EMPTY_DIFF_RETURNS_0=$adopt_empty_ok"
  council_wt_cleanup "$TMP" "$RUN3"

  # ── stash-fail 패널은 adopt가 거부(rc=2) — 손상 patch 방지 가드 검증 ──
  RUN4=$(mktemp -d "${TMPDIR:-/tmp}/cwt-run4.XXXXXX")
  council_wt_setup "$TMP" "$RUN4" "selftest" sf >/dev/null 2>&1
  echo "WARN: stash apply 실패 (baseline 변경 미적용) in sf" >> "$RUN4/sf/manifest"
  council_wt_adopt "$TMP" "$RUN4" "sf" >/dev/null 2>&1; rc=$?
  [ "$rc" = "2" ] && adopt_stashfail_ok="pass" || adopt_stashfail_ok="FAIL(rc=$rc)"
  echo "ADOPT_STASHFAIL_RETURNS_2=$adopt_stashfail_ok"
  council_wt_cleanup "$TMP" "$RUN4"

  # ── cleanup keep_id가 worktree까지 보존하는지(이전 버그: 브랜치만 보존, worktree는 force-remove) ──
  RUN5=$(mktemp -d "${TMPDIR:-/tmp}/cwt-run5.XXXXXX")
  council_wt_setup "$TMP" "$RUN5" "selftest" kp >/dev/null 2>&1
  council_wt_cleanup "$TMP" "$RUN5" kp   # keep_id=kp → wt/kp 보존 기대
  [ -d "$RUN5/wt/kp" ] && cleanup_keep_ok="pass" || cleanup_keep_ok="FAIL(worktree 삭제됨)"
  echo "CLEANUP_KEEP_PRESERVES_WT=$cleanup_keep_ok"
  council_wt_cleanup "$TMP" "$RUN5"   # 이제 완전 정리

  # ── adopt+cleanup 경로(RUN3/RUN4)까지 누수 0 재검증 (이전엔 happy-path RUN 직후 캡처값만 평가 — 사각 보강) ──
  wt_leak_final=$(git -C "$TMP" worktree list | grep -c -F -e "$RUN" -e "$RUN3" -e "$RUN4" -e "$RUN5" || true)
  branch_leak_final=$(git -C "$TMP" branch --list 'council/*' | wc -l | tr -d ' ')
  echo "WORKTREE_LEAK_FINAL=$wt_leak_final  (adopt+cleanup 경로 후 0 기대)"
  echo "BRANCH_LEAK_FINAL=$branch_leak_final  (0 기대)"

  rm -rf "$TMP" "$RUN" "$RUN2" "$RUN3" "$RUN4" "$RUN5"
  if [ "$wt_leak" = "0" ] && [ "$branch_leak" = "0" ] \
     && [ "$wt_leak_final" = "0" ] && [ "$branch_leak_final" = "0" ] \
     && [ "$setup_fail_ok" = "pass" ] && [ "$adopt_missing_ok" = "pass" ] && [ "$adopt_empty_ok" = "pass" ] \
     && [ "$adopt_stashfail_ok" = "pass" ] && [ "$cleanup_keep_ok" = "pass" ]; then
    echo "SELFTEST=pass"
  else
    echo "SELFTEST=FAIL"
  fi
fi
