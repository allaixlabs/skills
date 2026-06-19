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

MODE="claude-hook"   # Claude Code 환경 기본. ZCode/opencode/Codex 등 Claude hook 포맷이 없는 에이전트는 --git-hook 모드(.git/hooks/pre-commit)로 호출.
msgfile=""
if [ "${1:-}" = "--git-hook" ]; then
  MODE="git-hook"
elif [ "${1:-}" = "--commit-msg" ]; then
  MODE="commit-msg"
  msgfile="${2:-}"
fi

if [ "$MODE" = "git-hook" ]; then
  cmd="git commit"
elif [ "$MODE" = "commit-msg" ]; then
  cmd="git commit"
else
  input=$(cat 2>/dev/null || true)
  if command -v python3 >/dev/null 2>&1; then
    cmd=$(printf '%s' "$input" | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('tool_input',{}).get('command',''))
except Exception: print('')" 2>/dev/null)
  else
    # python3 부재 시 휴리스틱(무해 통과 방지): 원문에서 git…commit 패턴을 직접 탐색
    cmd=$(printf '%s' "$input" | grep -oE '(^|[[:space:];|&])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)?)*[[:space:]]+commit([^[:alnum:]_-]|$)[^"\\]*' | head -1 || true)
  fi
fi

# git commit 이 아니면 무관 — 통과
is_git_commit_command() {
  if command -v python3 >/dev/null 2>&1; then
    LOOP_GIT_CMD=$1 python3 - <<'PY'
import os
import shlex
import sys

try:
    tokens = shlex.split(os.environ.get("LOOP_GIT_CMD", ""))
except ValueError:
    tokens = os.environ.get("LOOP_GIT_CMD", "").split()

i = 0
while i < len(tokens):
    token = tokens[i]
    if token == "git" or token.endswith("/git"):
        i += 1
        while i < len(tokens):
            option = tokens[i]
            if option == "-c":
                i += 2
            elif option.startswith("-c") and option != "-c":
                i += 1
            elif option in ("-C", "--git-dir", "--work-tree", "--namespace", "--config-env"):
                i += 2
            elif option.startswith("--git-dir=") or option.startswith("--work-tree=") or option.startswith("--namespace=") or option.startswith("--config-env="):
                i += 1
            elif option.startswith("-"):
                i += 1
            else:
                sys.exit(0 if option == "commit" else 1)
        sys.exit(1)
    i += 1
sys.exit(1)
PY
  else
    printf '%s' "$1" | grep -qE '(^|[^[:alnum:]_/-])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)?)*[[:space:]]+commit([^[:alnum:]_-]|$)'
  fi
}

commit_uses_all() {
  if command -v python3 >/dev/null 2>&1; then
    LOOP_GIT_CMD=$1 python3 - <<'PY'
import os
import shlex
import sys

try:
    tokens = shlex.split(os.environ.get("LOOP_GIT_CMD", ""))
except ValueError:
    tokens = os.environ.get("LOOP_GIT_CMD", "").split()

i = 0
while i < len(tokens):
    token = tokens[i]
    if token == "git" or token.endswith("/git"):
        i += 1
        while i < len(tokens):
            option = tokens[i]
            if option == "-c":
                i += 2
            elif option.startswith("-c") and option != "-c":
                i += 1
            elif option in ("-C", "--git-dir", "--work-tree", "--namespace", "--config-env"):
                i += 2
            elif option.startswith("--git-dir=") or option.startswith("--work-tree=") or option.startswith("--namespace=") or option.startswith("--config-env="):
                i += 1
            elif option.startswith("-"):
                i += 1
            else:
                if option != "commit":
                    sys.exit(1)
                i += 1
                break
        else:
            sys.exit(1)
        while i < len(tokens):
            option = tokens[i]
            if option == "--":
                break
            if option in ("-m", "--message", "-F", "--file"):
                i += 2
                continue
            if option.startswith("--message=") or option.startswith("--file="):
                i += 1
                continue
            if (option.startswith("-m") and option != "-m") or (option.startswith("-F") and option != "-F"):
                i += 1
                continue
            if option == "--all":
                sys.exit(0)
            if option.startswith("-") and not option.startswith("--") and "a" in option[1:]:
                sys.exit(0)
            i += 1
        sys.exit(1)
    i += 1
sys.exit(1)
PY
  else
    stripped=$(printf '%s' "$1" | sed -E "s/(^|[[:space:]])(-m|--message|-F|--file)(=|[[:space:]])('[^']*'|\"[^\"]*\"|[^[:space:]]+)//g")
    printf '%s' "$stripped" | grep -qE '(^|[[:space:]])-[^[:space:]]*a[^[:space:]]*([[:space:]]|$)|--all([[:space:]]|$)'
  fi
}

git_root_hint_from_cmd() {
  if command -v python3 >/dev/null 2>&1; then
    LOOP_GIT_CMD=$1 python3 - <<'PY'
import os
import shlex
import sys

try:
    tokens = shlex.split(os.environ.get("LOOP_GIT_CMD", ""))
except ValueError:
    tokens = os.environ.get("LOOP_GIT_CMD", "").split()

i = 0
while i < len(tokens):
    token = tokens[i]
    if token == "git" or token.endswith("/git"):
        i += 1
        while i < len(tokens):
            option = tokens[i]
            if option == "-C" and i + 1 < len(tokens):
                print(tokens[i + 1])
                sys.exit(0)
            if option == "--git-dir" and i + 1 < len(tokens):
                print(tokens[i + 1])
                sys.exit(0)
            if option.startswith("--git-dir="):
                print(option.split("=", 1)[1])
                sys.exit(0)
            if option == "-c":
                i += 2
                continue
            if option.startswith("-c") and option != "-c":
                i += 1
                continue
            if option in ("--work-tree", "--namespace", "--config-env"):
                i += 2
                continue
            if option == "--":
                sys.exit(1)
            if option == "commit":
                sys.exit(1)
            i += 1
        sys.exit(1)
    i += 1
sys.exit(1)
PY
  else
    candidate=$(printf '%s' "$1" | grep -oE '(^|[[:space:];|&])git([^;&|]*[[:space:]])(-C[[:space:]]+[^[:space:];|&]+|--git-dir(=|[[:space:]]+)[^[:space:];|&]+)' | head -1 || true)
    printf '%s\n' "$candidate" | sed -nE 's/.*-C[[:space:]]+([^[:space:];|&]+).*/\1/p; s/.*--git-dir=([^[:space:];|&]+).*/\1/p; s/.*--git-dir[[:space:]]+([^[:space:];|&]+).*/\1/p' | head -1
  fi
}

[ "$MODE" = "commit-msg" ] || is_git_commit_command "$cmd" || exit 0

# git 저장소 루트 (아니면 무관)
root_hint=""
if [ "$MODE" = "claude-hook" ]; then
  root_hint=$(git_root_hint_from_cmd "$cmd" 2>/dev/null || true)
fi
if [ -n "$root_hint" ]; then
  root=$(git -C "$root_hint" rev-parse --show-toplevel 2>/dev/null) || root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
else
  root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
fi
[ -f "$root/loop.md" ] || exit 0   # loop.md 없는 프로젝트는 가드하지 않음

# 긴급 우회 — 반드시 감사 로그를 남긴다
bypass() {
  mkdir -p "$root/.loop" 2>/dev/null
  { printf '%s bypass=%s mode=%s cmd=%s\n' "$(date '+%F %T')" "$1" "$MODE" "$cmd" >> "$root/.loop/bypass.log"; } 2>/dev/null || printf '⚠️ bypass 감사로그 기록 실패(.loop 쓰기 불가) — 우회는 진행됩니다.\n' >&2
  exit 0
}
if [ "$MODE" = "commit-msg" ]; then
  [ -n "$msgfile" ] && [ -f "$msgfile" ] && grep -q '\[skip-loop\]' "$msgfile" && bypass "skip-loop"
else
  printf '%s' "$cmd" | grep -q '\[skip-loop\]' && bypass "skip-loop"
fi
[ "${LOOP_SKIP:-}" = "1" ] && bypass "LOOP_SKIP=1"

# docs/loop-md/ 디렉토리 전체 커밋(lessons.md 외 메타 문서 포함)은 게이트 면제
# 지식 증류·메타 기록은 검증 대상 작업이 아니다. (FAIL 라운드 중에도 허용)
# 단 -a/-am/--all 커밋은 unstaged 작업 파일까지 쓸려 들어가므로 claude-hook 모드에서는 면제하지 않는다.
staged=$(git -C "$root" diff --cached --name-only 2>/dev/null)
if [ -n "$staged" ] && [ "$(printf '%s\n' "$staged" | grep -cv '^docs/loop-md/')" -eq 0 ]; then
  if [ "$MODE" = "git-hook" ] || ! commit_uses_all "$cmd"; then
    exit 0
  fi
fi

marker="$root/.loop/last-verified"
block() {
  printf '⛔ loop.md DoD 가드: %s\n' "$1" >&2
  printf "→ '/loop-md' Verify 로 ①Pass/Fail 게이트(실행 증거)·②정량·③정성 리포트를 통과시킨 뒤 커밋하세요.\n" >&2
  printf '   통과 시 .loop/last-verified 마커가 갱신되어 커밋이 허용됩니다.\n' >&2
  if [ "$MODE" = "git-hook" ]; then
   printf '   (긴급 우회: 이 hook(pre-commit)은 커밋 메시지를 읽지 못해 `[skip-loop]`가 동작하지 않습니다 → `LOOP_SKIP=1`을 쓰거나 `commit-msg` hook을 설치하세요. .loop/bypass.log 에 기록됨)\n' >&2
  else
   printf '   (긴급 우회: `[skip-loop]`(커밋 메시지) 또는 `LOOP_SKIP=1`로 우회 가능. .loop/bypass.log 에 기록됨)\n' >&2
  fi
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
if [ "$MODE" = "git-hook" ] || ! commit_uses_all "$cmd"; then
  git -C "$root" diff --quiet 2>/dev/null \
    || block "스테이징되지 않은 변경이 있습니다 — 부분 커밋은 검증과 불일치합니다. 전부 스테이징하거나 stash 후 재검증하세요."
fi

# mtime 검사 — 마커보다 나중에 수정된 추적 텍스트 소스 탐색 (바이너리·생성물 제외, 첫 발견 시 중단)
# lockfile(.lock)은 제외하지 않는다 — 의존성 변경도 DoD 검증 대상이다.
# ⚠️ 2차 content 검증: mtime은 checkout/stash/restore 시 현재 시각으로 갱신돼 노이즈 차단을 유발한다(bypass.log
#    수십 건 참조). 그래서 mtime 히트 시 git diff --quiet로 실제 내용 변화를 2차 확인한다 —
#    내용 변화 없으면 통과(checkout/stash 노이즈), 내용 변화 있을 때만 차단(정당).
newer=$(cd "$root" && git -c core.quotePath=false ls-files 2>/dev/null \
  | grep -vE '\.(pyc|pyo|so|o|class|jar|png|jpe?g|gif|svg|pdf|ico|woff2?|ttf|map)$|(^|/)(__pycache__|node_modules|vendor|dist|build|tmp|\.loop)/' \
  | while IFS= read -r f; do [ "$f" -nt "$marker" ] && { echo "$f"; break; }; done)

if [ -n "$newer" ]; then
  # mtime이 늦은 파일이 있어도, 실제 내용이 HEAD와 다른지 2차 확인 (mtime 노이즈 필터).
  if git -C "$root" diff --quiet HEAD -- $newer 2>/dev/null; then
    : # mtime만 흔들림(checkout/stash/restore) — 내용 변화 없음 → 통과
  else
    block "검증 후 소스가 변경되었습니다($newer 등) — 재검증이 필요합니다."
  fi
fi
exit 0
