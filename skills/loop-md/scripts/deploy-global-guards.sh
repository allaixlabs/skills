#!/usr/bin/env bash
# deploy-global-guards.sh — loop-md 글로벌 가드(dod-guard + async-polling-guard)를 감지된
# 에이전트(claude/codex/zcode-opencode)의 글로벌 지침 파일에 배포/검증한다.
#
# ⚠️ 이 스크립트는 **글로벌 설정 파일**(~/.claude/CLAUDE.md, ~/.codex/AGENTS.md,
#    ~/.config/opencode/opencode.json 등)을 수정한다 — 인간 승인 영역.
#    따라서 기본은 **dry-run**(변경 계획만 출력)이고, 명시적 --apply 가 있을 때만 실제 쓴다.
#
# 가드 2종(축 분리):
#   ① dod-guard          — 완료 검증(조건부: loop.md 있을 때만). 템플릿: loop-md-guard.md.tmpl
#   ② async-polling-guard — 비동기 폴링(무조건, loop.md 유무 무관). 템플릿: async-polling-guard.md.tmpl
# 템플릿이 단일 소스(source-of-truth) — 본 스크립트는 그것을 각 에이전트 파일로 렌더링만 한다.
#
# 사용법:
#   bash deploy-global-guards.sh                # 자동 감지 + dry-run (변경 없음, 계획 출력)
#   bash deploy-global-guards.sh --apply        # 자동 감지 + 실제 배포
#   bash deploy-global-guards.sh --apply claude # 특정 에이전트만 (claude|codex|zcode)
#   bash deploy-global-guards.sh --check        # 감지 + 정합성 검증만 (exit code: 0=전부 정합, 1=불일치/누락)
#
# 출력(stdout): AGENT=<name> GUARD=<name> STATUS=<deployed|skipped|ok|mismatch> ACTION=<create|replace|none>
# 진단(stderr): 감지 결과, 누락, 정합성, 승인 게이트.
#
# 멱등: 이미 배포된 마커 블록은 템플릿으로 통째 교체(내용 변동 안전).
# read-only 모드(--check): 아무것도 쓰지 않음.
# bash 3.2(macOS 기본) 호환: 연관배열·declare -A 미사용.
set -euo pipefail

SKILL_DIR="${LOOP_MD_SKILL_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
TPL_DOD="$SKILL_DIR/templates/loop-md-guard.md.tmpl"
TPL_ASYNC="$SKILL_DIR/templates/async-polling-guard.md.tmpl"

MARK_DOD_OPEN="<!-- loop-md:dod-guard -->"
MARK_DOD_CLOSE="<!-- /loop-md:dod-guard -->"
MARK_ASYNC_OPEN="<!-- loop-md:async-polling-guard -->"
MARK_ASYNC_CLOSE="<!-- /loop-md:async-polling-guard -->"

APPLY=0
CHECK_ONLY=0
TARGET=""

# 인자 파싱
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --check) CHECK_ONLY=1 ;;
    --apply-*) TARGET="${1#--apply-}" APPLY=1 ;;   # --apply-claude 등(호환)
    claude|codex|zcode|all) TARGET="$1" ;;
    *) echo "deploy-global-guards: 알 수 없는 인자 '$1' (무시)" >&2 ;;
  esac
  shift
done
[ "$CHECK_ONLY" = 1 ] && APPLY=0

# 템플릿 존재 확인
for t in "$TPL_DOD" "$TPL_ASYNC"; do
  [ -f "$t" ] || { echo "ABORT: 템플릿 없음: $t" >&2; exit 2; }
done

# ---------- 에이전트 감지 (SKILL.md §0 표와 동일) ----------
detect_agents() {
  local found=""
  [ -d "$HOME/.claude" ] && found="$found claude"
  [ -d "$HOME/.codex" ] && found="$found codex"
  { [ -d "$HOME/.zcode" ] || [ -f "$HOME/.config/opencode/opencode.json" ]; } && found="$found zcode"
  echo "${found# }"
}

AGENTS="$(detect_agents)"
[ -z "$AGENTS" ] && { echo "감지된 에이전트 없음 — 배포 불가" >&2; exit 0; }
if [ -n "$TARGET" ] && [ "$TARGET" != "all" ]; then
  AGENTS="$TARGET"
fi
echo "# 감지된 에이전트: $AGENTS" >&2
[ "$APPLY" = 1 ] && echo "# 모드: APPLY (실제 배포)" >&2 || echo "# 모드: dry-run (변경 없음, --apply 로 실배포)" >&2

# ---------- 유틸: 마커 블록 추출 (stdin→stdout, 마커 포함) ----------
extract_block() {  # $1=file $2=open $3=close
  local f="$1" o="$2" c="$3"
  [ -f "$f" ] || return 0
  awk -v o="$o" -v c="$c" '
    $0==o {inblk=1} inblk {print} $0==c && inblk {inblk=0}
  ' "$f"
}

# ---------- 마커 블록 교체/삽입 (claude/codex 용: 단일 파일 안에 2개 블록) ----------
# $1=대상 파일 $2=open $3=close $4=템플릿파일
# 동작: 기존 블록이 있으면 통째 교체, 없으면 파일 끝에 추가. APPLY=0 이면 변경 계획만 출력.
patch_marker_in_file() {
  local f="$1" o="$2" c="$3" tpl="$4" name="$5"
  local existing newblk has_old
  [ -f "$f" ] || { echo "AGENT=$name GUARD=... STATUS=skipped ACTION=none (파일 없음: $f)"; return 0; }
  newblk="$(cat "$tpl")"
  existing="$(extract_block "$f" "$o" "$c")"
  if [ -n "$existing" ]; then
    has_old=1
    if [ "$existing" = "$newblk" ]; then
      echo "AGENT=$name GUARD=$name STATUS=ok ACTION=none (이미 정합)"
      return 0
    fi
    echo "AGENT=$name GUARD=$name STATUS=$([ $APPLY = 1 ] && echo deployed || echo pending) ACTION=replace"
  else
    has_old=0
    echo "AGENT=$name GUARD=$name STATUS=$([ $APPLY = 1 ] && echo deployed || echo pending) ACTION=create"
  fi
  [ "$CHECK_ONLY" = 1 ] && return 0
  [ "$APPLY" = 0 ] && return 0
  # 실제 적용: python3 로 안전 교체 (awk -v 는 멀티라인 문자열 newline에서 죽음 → python3 사용).
  # 마커(o..c) 구간을 새 블록으로 통째 교체(has_old) 또는 끝에 추가(create). 원자적(mktemp→mv).
  if ! command -v python3 >/dev/null 2>&1; then
    echo "WARN: python3 없음 — $f 수동 배포 필요 (마커 블록 교체)" >&2; return 0
  fi
  local tmp; tmp="$(mktemp)"
  python3 - "$f" "$tmp" "$o" "$c" "$tpl" "$has_old" <<'PY' || { echo "WARN: python 교체 실패($f) — 백업 미반영" >&2; rm -f "$tmp"; return 0; }
import sys
src, dst, o, c, tpl, has_old = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
text = open(src).read()
newblk = open(tpl).read().rstrip("\n")   # 템플릿 = 단일 소스. 끝 개행 제거 (마커 정확 치환 위해)
if has_old == "1":
    # 마커(o..c) 구간을 새 블록으로 통째 교체. non-greedy, DOTALL.
    # newblk 를 rstrip 했으므로 닫는 마커 뒤 원본 개행은 보존됨 (빈 줄 중복 방지).
    import re
    pat = re.compile(re.escape(o) + r".*?" + re.escape(c), re.DOTALL)
    if not pat.search(text):
        sys.exit("marker_not_found")  # has_old=1 인데 못 찾으면 안전하게 실패
    out = pat.sub(lambda m: newblk, text, count=1)
else:
    sep = "" if text.endswith("\n") else "\n"
    out = text + sep + newblk + "\n"
open(dst, "w").write(out)
PY
  # 백업 후 원자적 치환
  cp "$f" "$f.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  mv "$tmp" "$f"
}

# ---------- zcode/opencode 용: 별도 파일 + opencode.json 멤버십 ----------
# $1=가드 파일명(예 loop-md-guard.md) $2=템플릿 $3=가드 표시명
deploy_zcode_file() {
  local fname="$1" tpl="$2" name="$3"
  local dest="$HOME/.config/opencode/$fname"
  local cfg="$HOME/.config/opencode/opencode.json"
  [ -d "$HOME/.config/opencode" ] || { echo "AGENT=zcode GUARD=$name STATUS=skipped ACTION=none (dir 없음)"; return 0; }
  local need_file=0 need_member=0
  { [ ! -f "$dest" ] || [ "$(cat "$dest")" != "$(cat "$tpl")" ]; } && need_file=1
  # opencode.json 멤버십 확인 (단순 grep — JSON 깨져도 안전)
  if ! grep -q "\"$fname\"" "$cfg" 2>/dev/null; then need_member=1; fi

  if [ "$need_file" = 0 ] && [ "$need_member" = 0 ]; then
    echo "AGENT=zcode GUARD=$name STATUS=ok ACTION=none (이미 정합)"
    return 0
  fi
  echo "AGENT=zcode GUARD=$name STATUS=$([ $APPLY = 1 ] && echo deployed || echo pending) ACTION=sync(file=$need_file member=$need_member)"
  [ "$CHECK_ONLY" = 1 ] && return 0
  [ "$APPLY" = 0 ] && return 0
  # 파일 동기화
  [ "$need_file" = 1 ] && cp "$tpl" "$dest"
  # opencode.json 멤버십 추가 (python3 로 안전하게 — 중복 방지)
  if [ "$need_member" = 1 ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$cfg" "$fname" <<'PY' || { echo "WARN: opencode.json 멤버십 추가 실패($cfg) — 수동으로 instructions 배열에 \"$fname\" 추가" >&2; }
import json, sys
cfg, fname = sys.argv[1], sys.argv[2]
with open(cfg) as f: d = json.load(f)
arr = d.get("instructions", [])
if fname not in arr: arr.append(fname); d["instructions"] = arr
with open(cfg, "w") as f: json.dump(d, f, indent=2)
PY
  fi
}

# ---------- 메인: 에이전트별 배포 ----------
mismatch=0
for ag in $AGENTS; do
  case "$ag" in
    claude)
      patch_marker_in_file "$HOME/.claude/CLAUDE.md" "$MARK_DOD_OPEN" "$MARK_DOD_CLOSE" "$TPL_DOD" "claude/dod"
      patch_marker_in_file "$HOME/.claude/CLAUDE.md" "$MARK_ASYNC_OPEN" "$MARK_ASYNC_CLOSE" "$TPL_ASYNC" "claude/async"
      ;;
    codex)
      patch_marker_in_file "$HOME/.codex/AGENTS.md" "$MARK_DOD_OPEN" "$MARK_DOD_CLOSE" "$TPL_DOD" "codex/dod"
      patch_marker_in_file "$HOME/.codex/AGENTS.md" "$MARK_ASYNC_OPEN" "$MARK_ASYNC_CLOSE" "$TPL_ASYNC" "codex/async"
      ;;
    zcode)
      deploy_zcode_file "loop-md-guard.md" "$TPL_DOD" "zcode/dod"
      deploy_zcode_file "async-polling-guard.md" "$TPL_ASYNC" "zcode/async"
      ;;
    *) echo "알 수 없는 에이전트: $ag (건너뜀)" >&2 ;;
  esac
done

# ---------- --check 모드: 정합성 요약 ----------
if [ "$CHECK_ONLY" = 1 ]; then
  echo "" >&2
  echo "# 정합성 검증 (--check)" >&2
  bad=0; total=0
  for ag in $AGENTS; do
    case "$ag" in
      claude|codex)
        if [ "$ag" = "claude" ]; then f="$HOME/.claude/CLAUDE.md"; else f="$HOME/.codex/AGENTS.md"; fi
        # ⚠️ 구분자는 '|' (마커 안에 ':'가 있어 ':' 분리 불가). IFS 로 4필드 안전 분리.
        for pair in "dod|$MARK_DOD_OPEN|$MARK_DOD_CLOSE|$TPL_DOD" "async|$MARK_ASYNC_OPEN|$MARK_ASYNC_CLOSE|$TPL_ASYNC"; do
          IFS='|' read -r g o c tpl <<<"$pair"
          total=$((total+1))
          blk="$(extract_block "$f" "$o" "$c")"
          if [ -z "$blk" ] || [ "$blk" != "$(cat "$tpl")" ]; then
            echo "  ✗ $ag/$g 불일치 또는 누락" >&2; bad=$((bad+1))
          else echo "  ✓ $ag/$g 정합" >&2; fi
        done
        ;;
      zcode)
        for pair in "dod|loop-md-guard.md|$TPL_DOD" "async|async-polling-guard.md|$TPL_ASYNC"; do
          IFS='|' read -r g fname tpl <<<"$pair"
          total=$((total+1))
          dest="$HOME/.config/opencode/$fname"
          if [ ! -f "$dest" ] || [ "$(cat "$dest")" != "$(cat "$tpl")" ]; then
            echo "  ✗ zcode/$g 불일치 또는 누락" >&2; bad=$((bad+1))
          else echo "  ✓ zcode/$g 정합" >&2; fi
        done
        # opencode.json 멤버십
        total=$((total+1))
        cfg="$HOME/.config/opencode/opencode.json"
        if grep -q '"async-polling-guard.md"' "$cfg" 2>/dev/null && grep -q '"loop-md-guard.md"' "$cfg" 2>/dev/null; then
          echo "  ✓ zcode/opencode.json 멤버십 정합" >&2
        else echo "  ✗ zcode/opencode.json 멤버십 누락" >&2; bad=$((bad+1)); fi
        ;;
    esac
  done
  echo "" >&2
  echo "# 정합: $((total-bad))/$total" >&2
  [ "$bad" -gt 0 ] && exit 1
fi

exit 0
