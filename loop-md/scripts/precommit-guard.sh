#!/usr/bin/env bash
# precommit-guard.sh — PreToolUse(Bash) hard 가드 (옵트인).
#
# loop.md가 있는 프로젝트에서 `git commit` 을 시도하면, 그 변경이 loop-md Verify를
# 통과했는지 확인한다. 판정은 **mtime 기반**:
#   - Verify 통과 시 `.loop/last-verified` 를 touch (마커).
#   - 추적 소스(텍스트) 중 마커보다 나중에 수정된 파일이 있으면 = 검증 후 코드가 바뀜 → 차단.
#   - 마커가 없으면 = 검증 자체를 안 함 → 차단.
# (내용 해시가 아니라 mtime을 쓰는 이유: watcher·멀티프로세스가 .pyc 등을 재생성하는
#  활성 작업공간에서 git diff 내용 해시는 호출마다 흔들려 신뢰할 수 없기 때문.)
#
# 입력: PreToolUse JSON(stdin).  종료코드: 0=통과, 2=차단(stderr가 Claude에 전달됨).
# 우회: 커밋 메시지에 [skip-loop] 포함, 또는 LOOP_SKIP=1 (자가치유·긴급용).
set -u

input=$(cat 2>/dev/null || true)
cmd=$(printf '%s' "$input" | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('tool_input',{}).get('command',''))
except Exception: print('')" 2>/dev/null)

# git commit 이 아니면 무관 — 통과
printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]])git[[:space:]].*commit' || exit 0
# 긴급 우회
printf '%s' "$cmd" | grep -q 'skip-loop' && exit 0
[ "${LOOP_SKIP:-}" = "1" ] && exit 0

# git 저장소 루트 (아니면 무관)
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$root/loop.md" ] || exit 0   # loop.md 없는 프로젝트는 가드하지 않음

marker="$root/.loop/last-verified"
block() {
  cat >&2 <<MSG
⛔ loop.md DoD 가드: $1
→ '/loop-md' Verify 로 ①Pass/Fail 게이트(실행 증거)·②정량·③정성 리포트를 출력해 통과시킨 뒤 커밋하세요.
   통과 시 .loop/last-verified 가 갱신되어 커밋이 허용됩니다.
   (긴급/자동 우회: 커밋 메시지에 [skip-loop] 추가, 또는 LOOP_SKIP=1)
MSG
  exit 2
}

[ -f "$marker" ] || block "검증 마커가 없습니다(Verify 미실행)."

# 마커보다 나중에 수정된 추적 텍스트 소스 탐색 (바이너리·생성물 제외, 첫 발견 시 중단)
newer=$(cd "$root" && git ls-files 2>/dev/null \
  | grep -vE '\.(pyc|pyo|so|o|class|jar|png|jpe?g|gif|svg|pdf|ico|woff2?|ttf|map|lock)$|(^|/)(__pycache__|node_modules|vendor|dist|build|tmp|\.loop)/' \
  | while IFS= read -r f; do [ "$f" -nt "$marker" ] && { echo "$f"; break; }; done)

[ -n "$newer" ] && block "검증 후 소스가 변경되었습니다($newer 등) — 재검증이 필요합니다."
exit 0
