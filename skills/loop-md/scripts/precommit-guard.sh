#!/usr/bin/env bash
# precommit-guard.sh — DoD hard 가드 (옵트인). 두 가지 모드:
#   ① Claude PreToolUse(Bash) hook 모드(기본): stdin JSON에서 command 추출.
#      `git commit --no-verify` 도 잡는다(명령 문자열 검사라서).
#   ② git pre-commit hook 모드(--git-hook): .git/hooks/pre-commit 에서 호출.
#      어떤 에이전트(Codex/Claude/사람)든 셸 git commit 시 발동 — 에이전트 불문 대칭 강제.
#      단 --no-verify 는 git hook 자체를 건너뛰므로 ①과 병행을 권장.
#
# 판정(위협 모델 = 부주의한 완료 선언 차단이지, 악의적 위조 방지가 아니다):
#   - 마커 없음 → 차단 (Verify 미실행)
#   - 마커에 기록된 HEAD ≠ 현재 HEAD → 차단 (브랜치 전환/rebase 후 stale 마커)
#   - 스테이징 밖 변경 존재 → 차단 (부분 커밋은 worktree 전체 기준 검증과 불일치)
#   - 마커보다 나중에 수정된 추적 소스 존재 → 차단 (검증 후 코드 변경; mtime 기반 —
#     내용 해시 대신 mtime을 쓰는 이유: watcher가 산출물을 재생성하는 활성 작업공간에서
#     내용 해시는 호출마다 흔들리기 때문)
#
# 입력: ①은 PreToolUse JSON(stdin), ②는 인자 --git-hook.
# 종료코드: 0=통과, 2=차단(stderr 메시지 전달).
# 우회: 커밋 메시지에 [skip-loop], 또는 LOOP_SKIP=1 — 우회는 .loop/bypass.log 에 감사 기록.
set -u

MODE="claude-hook"
[ "${1:-}" = "--git-hook" ] && MODE="git-hook"

if [ "$MODE" = "git-hook" ]; then
  cmd="git commit"
else
  input=$(cat 2>/dev/null || true)
  if command -v python3 >/dev/null 2>&1; then
    cmd=$(printf '%s' "$input" | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('tool_input',{}).get('command',''))
except Exception: print('')" 2>/dev/null)
  else
    # python3 부재 시 휴리스틱(무해 통과 방지): 원문에서 git…commit 패턴을 직접 탐색
    cmd=$(printf '%s' "$input" | grep -oE 'git[^"\\]*commit[^"\\]*' | head -1 || true)
  fi
fi

# git commit 이 아니면 무관 — 통과
printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]])git[[:space:]].*commit' || exit 0

# git 저장소 루트 (아니면 무관)
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$root/loop.md" ] || exit 0   # loop.md 없는 프로젝트는 가드하지 않음

# 긴급 우회 — 반드시 감사 로그를 남긴다
bypass() {
  mkdir -p "$root/.loop" 2>/dev/null
  printf '%s bypass=%s mode=%s cmd=%s\n' "$(date '+%F %T')" "$1" "$MODE" "$cmd" >> "$root/.loop/bypass.log" 2>/dev/null
  exit 0
}
printf '%s' "$cmd" | grep -q 'skip-loop' && bypass "skip-loop"
[ "${LOOP_SKIP:-}" = "1" ] && bypass "LOOP_SKIP=1"

marker="$root/.loop/last-verified"
block() {
  printf '⛔ loop.md DoD 가드: %s\n' "$1" >&2
  printf "→ '/loop-md' Verify 로 ①Pass/Fail 게이트(실행 증거)·②정량·③정성 리포트를 통과시킨 뒤 커밋하세요.\n" >&2
  printf '   통과 시 .loop/last-verified 마커가 갱신되어 커밋이 허용됩니다.\n' >&2
  printf '   (긴급 우회: 커밋 메시지에 [skip-loop] 또는 LOOP_SKIP=1 — .loop/bypass.log 에 기록됨)\n' >&2
  exit 2
}

[ -f "$marker" ] || block "검증 마커가 없습니다(Verify 미실행)."

# HEAD 일치 검사 — 브랜치 전환/rebase 후 stale 마커 차단 (빈 마커=구버전은 mtime만 검사)
verified_head=$(head -1 "$marker" 2>/dev/null || true)
cur_head=$(git -C "$root" rev-parse HEAD 2>/dev/null || true)
if [ -n "$verified_head" ] && [ -n "$cur_head" ] && [ "$verified_head" != "$cur_head" ]; then
  block "검증 시점 HEAD(${verified_head%"${verified_head#???????}"}…)와 현재 HEAD(${cur_head%"${cur_head#???????}"}…)가 다릅니다 — 브랜치 전환/rebase 후 재검증 필요."
fi

# 부분 스테이징 차단 — 검증은 worktree 전체 기준이므로 스테이징 밖 변경이 남으면 커밋 내용≠검증 내용.
# (claude-hook 모드의 `git commit -a/-am/--all`은 커밋 시점에 전부 스테이징되므로 예외.
#  git-hook 모드는 -a 스테이징 후 발동하므로 검사가 정확.)
if [ "$MODE" = "git-hook" ] || ! printf '%s' "$cmd" | grep -qE '(^|[[:space:]])-(a|am)([[:space:]]|$)|--all([[:space:]]|$)'; then
  git -C "$root" diff --quiet 2>/dev/null \
    || block "스테이징되지 않은 변경이 있습니다 — 부분 커밋은 검증과 불일치합니다. 전부 스테이징하거나 stash 후 재검증하세요."
fi

# mtime 검사 — 마커보다 나중에 수정된 추적 텍스트 소스 탐색 (바이너리·생성물 제외, 첫 발견 시 중단)
# lockfile(.lock)은 제외하지 않는다 — 의존성 변경도 DoD 검증 대상이다.
newer=$(cd "$root" && git ls-files 2>/dev/null \
  | grep -vE '\.(pyc|pyo|so|o|class|jar|png|jpe?g|gif|svg|pdf|ico|woff2?|ttf|map)$|(^|/)(__pycache__|node_modules|vendor|dist|build|tmp|\.loop)/' \
  | while IFS= read -r f; do [ "$f" -nt "$marker" ] && { echo "$f"; break; }; done)

[ -n "$newer" ] && block "검증 후 소스가 변경되었습니다($newer 등) — 재검증이 필요합니다."
exit 0
