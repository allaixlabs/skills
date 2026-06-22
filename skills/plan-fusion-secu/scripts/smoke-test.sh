#!/usr/bin/env bash
# smoke-test.sh — plan-fusion-secu 구조 검증 (read-only, 비용 0)
#
# 목적: 스킬 산출물의 **구조적 결함**을 모델 호출 없이 자동 잡기.
#       이번 재검토(2026-06-23)에서 kimi/codex가 잡은 결함類를 회귀 방지:
#         - SKILL.md가 호출하는 스크립트가 실제 존재하는가 (check-fusion-dev-secu 누락 회귀)
#         - 상대참조 경로가 실제 파일을 가리키는가 (SSOT 깨짐 회귀)
#         - 분배 매트릭스 집계가 항목 표와 일치하는가 (§7 산술 오류 회귀)
#         - 스크립트 문법(bash -n) 통과
#         - frontmatter 유효
#
# ⚠️ 모델 호출 없음 — 구조/정합성만. 풀 e2e는 별도(인간 승인, 비용 발생).
#
# 종료코드: 0=전 통과, 1=실패.
set -u

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
SKILL_DIR="$SELF_DIR/.."
REPO_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ✗ $1" >&2; FAIL=$((FAIL+1)); }

echo "── plan-fusion-secu smoke-test (구조 검증, 비용 0) ──"
echo ""

# === 1. SKILL.md가 참조하는 스크립트가 실제 존재하는가 ===
echo "1. SKILL.md 스크립트 참조 정합성"
for skill in plan-fusion-secu plan-fusion-dev-secu; do
  sk_md="$REPO_ROOT/skills/$skill/SKILL.md"
  [ -f "$sk_md" ] || { bad "$skill/SKILL.md 없음"; continue; }
  # scripts/XXX.sh 패턴 추출
  for ref in $(grep -oE 'scripts/[a-zA-Z0-9_-]+\.sh' "$sk_md" | sort -u); do
    # 절대/상대 경로 모두 처리: $SKILL_DIR/scripts/.. 또는 ../plan-fusion-secu/scripts/..
    for candidate in \
      "$REPO_ROOT/skills/$skill/$ref" \
      "$REPO_ROOT/skills/$skill/../plan-fusion-secu/$ref" \
      "$REPO_ROOT/skills/$skill/../plan-fusion-dev/$ref" \
      "$REPO_ROOT/skills/$skill/../plan-fusion/$ref"; do
      if [ -f "$candidate" ]; then
        ok "$skill → $ref (존재: ${candidate#$REPO_ROOT/})"
        break
      fi
    done
    # 못 찾았으면
    if [ -f "$REPO_ROOT/skills/$skill/$ref" ] || \
       [ -f "$REPO_ROOT/skills/$skill/../plan-fusion-secu/$ref" ] || \
       [ -f "$REPO_ROOT/skills/$skill/../plan-fusion-dev/$ref" ] || \
       [ -f "$REPO_ROOT/skills/$skill/../plan-fusion/$ref" ]; then :; else
      bad "$skill/SKILL.md → $ref (존재 안 함 — 치명 결함)"
    fi
  done
done
echo ""

# === 2. 상대참조 경로 정합성 ===
echo "2. SKILL.md/README 상대참조(../) 정합성"
for skill in plan-fusion-secu plan-fusion-dev-secu; do
  for doc in SKILL.md README.md; do
    f="$REPO_ROOT/skills/$skill/$doc"
    [ -f "$f" ] || continue
    # ../plan-X/ 패턴 추출 — 디렉토리 이름 전체를 잡기 (tr로 '/' 제거 금지 — 경로 깨짐)
    # grep -oE 는 '../plan-fusion/' 전체를 매칭, 그후 마지막 '/'만 제거
    while IFS= read -r ref_with_slash; do
      [ -z "$ref_with_slash" ] && continue
      # '../plan-fusion/' → 'plan-fusion' (상위 1단계 디렉토리)
      ref_name=$(printf '%s' "$ref_with_slash" | sed 's|^\.\./||; s|/$||')
      target="$REPO_ROOT/skills/$skill/../$ref_name"
      if [ -d "$target" ]; then
        ok "$skill/$doc → ../$ref_name (존재)"
      else
        bad "$skill/$doc → ../$ref_name (디렉토리 없음)"
      fi
    done < <(grep -oE '\.\./[a-z][a-z0-9-]+/' "$f" | sort -u)
  done
done
echo ""

# === 3. 분배 매트릭스 집계 정합성 ===
echo "3. secure-coding.md 분배 매트릭스 집계"
SC="$REPO_ROOT/skills/plan-fusion-secu/references/secure-coding.md"
if [ -f "$SC" ]; then
  # ⚠️ 표 행(| T1-1 | ... | **L1** |)만 잡는다 — 본문 인라인 언급은 제외.
  #    정규식: | 공백 T<n>-<n> 공백 | ... | **L...** |
  if command -v python3 >/dev/null 2>&1; then
    result=$(python3 - "$SC" <<'PY'
import re, sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text(errors='replace')
counts = {}
total = 0
seen_ids = set()  # 중복 방지
for line in text.splitlines():
    # 표 행: | T1-1 | ... 형태 (본문 인라인은 | 없음)
    m = re.match(r'^\|\s*(T[1-4]-\d+)\s*\|', line)
    if not m: continue
    tid = m.group(1)
    if tid in seen_ids: continue  # ID당 1행만 (혹시 모를 중복)
    # 배정 열: **L1** 또는 **L1+L2** 등 (마지막 ** ** 강조)
    bolds = re.findall(r'\*\*([^*]+)\*\*', line)
    assigns = [b.strip() for b in bolds if re.match(r'^L[123]', b.strip())]
    if not assigns: continue
    seen_ids.add(tid)
    a_norm = assigns[0].split(',')[0].split('(')[0].strip()
    counts[a_norm] = counts.get(a_norm, 0) + 1
    total += 1
print(f"{total}|{counts.get('L1',0)}|{counts.get('L1+L2',0)}|{counts.get('L2',0)}|{counts.get('L2+L3',0)}|{counts.get('L1+L2+L3',0)}")
PY
)
    actual_total=$(echo "$result" | cut -d'|' -f1)
    if [ "$actual_total" = "43" ]; then
      ok "항목 표 집계: 43개 (정상)"
    else
      bad "항목 표 집계: ${actual_total}개 (43이어야 함)"
    fi
    l1_doc=$(grep -oE '\*\*순수 L1\*\* \| [0-9]+' "$SC" | grep -oE '[0-9]+$')
    l1l2_doc=$(grep -oE '\*\*L1\+L2 혼합\*\* \| [0-9]+' "$SC" | grep -oE '[0-9]+$')
    l1_actual=$(echo "$result" | cut -d'|' -f2)
    l1l2_actual=$(echo "$result" | cut -d'|' -f3)
    if [ "$l1_doc" = "$l1_actual" ] && [ "$l1l2_doc" = "$l1l2_actual" ]; then
      ok "§7 표 숫자가 항목 표와 일치 (L1=$l1_doc, L1+L2=$l1l2_doc)"
    else
      bad "§7 표 불일치 — L1: 문서=$l1_doc 실제=$l1_actual / L1+L2: 문서=$l1l2_doc 실제=$l1l2_actual"
    fi
  fi
fi
echo ""

# === 4. 스크립트 문법 ===
echo "4. 스크립트 bash -n"
for sh in "$REPO_ROOT"/skills/plan-fusion-secu/scripts/*.sh "$REPO_ROOT"/skills/plan-fusion-dev-secu/scripts/*.sh; do
  [ -f "$sh" ] || continue
  if bash -n "$sh" 2>/dev/null; then
    ok "$(basename "$sh") 문법 OK"
  else
    bad "$(basename "$sh") 문법 오류"
    bash -n "$sh" 2>&1 | head -3 >&2
  fi
done
echo ""

# === 5. check-fusion-secu.sh 실행 (L1 도구 감지만, FAIL 안 함) ===
echo "5. check-fusion-secu.sh 실행"
out=$(bash "$REPO_ROOT/skills/plan-fusion-secu/scripts/check-fusion-secu.sh" 2>/dev/null)
if echo "$out" | grep -q "^SECURE_MODE=yes$"; then
  ok "SECURE_MODE=yes 출력"
else
  bad "SECURE_MODE=yes 미출력"
fi
if echo "$out" | grep -qE "^SECURE_L1_CAPABILITY="; then
  cap=$(echo "$out" | grep '^SECURE_L1_CAPABILITY=' | head -1)
  ok "L1 감지: $cap"
else
  bad "SECURE_L1_CAPABILITY 미출력"
fi
echo ""

# === 6. run-secure-l1.sh 산출 JSON validity ===
echo "6. run-secure-l1.sh 산출 JSON 유효성 (의도적 취약 코드)"
T=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/secu-smoke.XXXXXX")
mkdir -p "$T/t"
# ⚠️ 시크릿 스캔(G5)에 안 걸리도록 가짜 키(표준 패턴 아님) 사용. semgrep/gitleaks는
#    pickle 역직렬화를 잡으므로 이것만으로 exit 1 유도 가능.
cat > "$T/t/v.py" <<'EOF'
import pickle
def load(d): return pickle.loads(d)
EOF
( cd "$T" && git init -q && git add -A && git commit -qm t 2>/dev/null )
bash "$REPO_ROOT/skills/plan-fusion-secu/scripts/run-secure-l1.sh" "$T/t" "$T/out" >/dev/null 2>&1
rc=$?
if [ "$rc" = "1" ]; then
  ok "취약 샘플 exit 1 (FAIL 정상)"
else
  bad "취약 샘플 exit=$rc (1이어야 함)"
fi
# JSON 유효
if [ -f "$T/out/l1-findings.json" ] && python3 -c "import json,sys; json.load(open('$T/out/l1-findings.json'))" 2>/dev/null; then
  ok "l1-findings.json valid JSON"
else
  bad "l1-findings.json invalid JSON (gitleaks ? 파손 회귀 의심)"
fi
rm -rf "$T"
echo ""

echo "═══════════════════════════════════════"
echo "smoke-test 종합: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "✅ PASS"
  exit 0
else
  echo "❌ FAIL"
  exit 1
fi
