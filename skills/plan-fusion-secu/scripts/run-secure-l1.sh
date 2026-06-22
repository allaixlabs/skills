#!/usr/bin/env bash
# run-secure-l1.sh — L1 정적 분석 러너
#
# secure-coding.md §8 의 도구 매핑을 실행한다.
# 스택을 자동 감지해 적절한 도구를 조합하고, 결과를 통합 JSON으로 산출.
#
# 사용: run-secure-l1.sh <scan_root> <output_dir>
#   scan_root  — 검사 대상 코드 루트(절대경로)
#   output_dir — 산출물 디렉토리($RUN, l1-findings.json 등이 생성됨)
#
# exit code (secure-coding.md §8 규약):
#   0 = 발견 0 (PASS)
#   1 = 발견 있음 (FAIL — 보안 게이트 차단)
#   2 = 도구 자체 오류 (WARN — L2로 폴백, 산출에 표기)
#
# ⚠️ 역할 경계: 이 스크립트는 검사만 한다. 코드를 수정하지 않는다(read-only).
#    발견된 취약점의 수정은 항상 개발 백엔드(plan-codex-opencode 위임)가 한다.
set -u

_SCAN_ROOT="${1:-}"
_OUT_DIR="${2:-}"

if [ -z "$_SCAN_ROOT" ] || [ -z "$_OUT_DIR" ]; then
  echo "Usage: $0 <scan_root> <output_dir>" >&2
  exit 2
fi

[ -d "$_SCAN_ROOT" ] || { echo "ABORT: scan_root 없음('$_SCAN_ROOT')" >&2; exit 2; }
mkdir -p "$_OUT_DIR" || { echo "ABORT: output_dir 생성 실패('$_OUT_DIR')" >&2; exit 2; }

_FINDINGS="$_OUT_DIR/l1-findings.json"
_RAW="$_OUT_DIR/l1-raw"
mkdir -p "$_RAW"

# 통합 findings JSON 초기화 (배열 형태 — 각 도구 결과를 병합)
printf '[' > "$_FINDINGS"
_FIRST=1
_HAD_TOOL=0
_HAD_FINDING=0
_HAD_ERROR=0

append_finding() {  # $1=JSON 객체 문자열
  if [ "$_FIRST" -eq 1 ]; then
    printf '%s' "$1" >> "$_FINDINGS"
    _FIRST=0
  else
    printf ',%s' "$1" >> "$_FINDINGS"
  fi
}

# === 도구별 실행 ===

run_semgrep() {
  command -v semgrep >/dev/null 2>&1 || return 0
  _HAD_TOOL=1
  echo "INFO: semgrep 실행 중..." >&2
  # --config=auto 는 OWASP/SANS 룰셋 자동 선택. --json 으로 결과.
  if semgrep --config=auto --json --quiet "$_SCAN_ROOT" > "$_RAW/semgrep.json" 2>"$_RAW/semgrep.err"; then
    # 발견 수 추출 (jq 있으면, 없으면 wc)
    if command -v jq >/dev/null 2>&1; then
      _n=$(jq '.results | length' "$_RAW/semgrep.json" 2>/dev/null || echo 0)
    else
      _n=$(grep -c '"check_id"' "$_RAW/semgrep.json" 2>/dev/null || echo 0)
    fi
    if [ "${_n:-0}" -gt 0 ]; then
      _HAD_FINDING=1
      append_finding "{\"tool\":\"semgrep\",\"findings\":$_n,\"details\":\"$_RAW/semgrep.json\"}"
    fi
  else
    _HAD_ERROR=1
    append_finding "{\"tool\":\"semgrep\",\"error\":true,\"stderr\":\"$_RAW/semgrep.err\"}"
  fi
}

run_gitleaks() {
  command -v gitleaks >/dev/null 2>&1 || return 0
  _HAD_TOOL=1
  echo "INFO: gitleaks 실행 중..." >&2
  # gitleaks detect — no-git-ver-scan (git 히스토리 없는 디렉토리도 검사)
  if gitleaks detect --source "$_SCAN_ROOT" --no-git --report-format json --report-path "$_RAW/gitleaks.json" > "$_RAW/gitleaks.out" 2>&1; then
    if command -v jq >/dev/null 2>&1; then
      _n=$(jq 'length' "$_RAW/gitleaks.json" 2>/dev/null || echo 0)
    else
      _n=$(grep -c '"RuleID"' "$_RAW/gitleaks.json" 2>/dev/null || echo 0)
    fi
    if [ "${_n:-0}" -gt 0 ]; then
      _HAD_FINDING=1
      append_finding "{\"tool\":\"gitleaks\",\"findings\":$_n,\"details\":\"$_RAW/gitleaks.json\"}"
    fi
  else
    # gitleaks exit 1 = 발견 있음(정상), exit 2 = 도구 오류
    _rc=$?
    if [ "$_rc" -eq 1 ] && [ -f "$_RAW/gitleaks.json" ]; then
      _HAD_FINDING=1
      _n=$(jq 'length' "$_RAW/gitleaks.json" 2>/dev/null || echo "?")
      append_finding "{\"tool\":\"gitleaks\",\"findings\":$_n,\"details\":\"$_RAW/gitleaks.json\"}"
    else
      _HAD_ERROR=1
      append_finding "{\"tool\":\"gitleaks\",\"error\":true,\"exit\":$_rc}"
    fi
  fi
}

run_trufflehog() {
  # gitleaks 가 있으면 생략(중복) — 없을 때만.
  command -v trufflehog >/dev/null 2>&1 || return 0
  command -v gitleaks >/dev/null 2>&1 && return 0
  _HAD_TOOL=1
  echo "INFO: trufflehog 실행 중..." >&2
  if trufflehog filesystem --dir "$_SCAN_ROOT" --json > "$_RAW/trufflehog.jsonl" 2>"$_RAW/trufflehog.err"; then
    _n=$(grep -c '"DetectorName"' "$_RAW/trufflehog.jsonl" 2>/dev/null || echo 0)
    if [ "${_n:-0}" -gt 0 ]; then
      _HAD_FINDING=1
      append_finding "{\"tool\":\"trufflehog\",\"findings\":$_n,\"details\":\"$_RAW/trufflehog.jsonl\"}"
    fi
  else
    _HAD_ERROR=1
    append_finding "{\"tool\":\"trufflehog\",\"error\":true}"
  fi
}

run_dep_scan() {
  # 스택 감지
  if [ -f "$_SCAN_ROOT/package-lock.json" ] || [ -f "$_SCAN_ROOT/yarn.lock" ]; then
    command -v npm >/dev/null 2>&1 || return 0
    _HAD_TOOL=1
    echo "INFO: npm audit 실행 중..." >&2
    ( cd "$_SCAN_ROOT" && npm audit --json > "$_RAW/npm-audit.json" 2>"$_RAW/npm-audit.err" )
    if [ -s "$_RAW/npm-audit.json" ]; then
      if command -v jq >/dev/null 2>&1; then
        _vuln=$(jq '.metadata.vulnerabilities.total // 0' "$_RAW/npm-audit.json" 2>/dev/null || echo 0)
      else
        _vuln=$(grep -o '"total":[0-9]*' "$_RAW/npm-audit.json" | head -1 | grep -o '[0-9]*' || echo 0)
      fi
      if [ "${_vuln:-0}" -gt 0 ]; then
        _HAD_FINDING=1
        append_finding "{\"tool\":\"npm-audit\",\"vulnerabilities\":$_vuln,\"details\":\"$_RAW/npm-audit.json\"}"
      fi
    fi
  elif [ -f "$_SCAN_ROOT/Pipfile.lock" ] || [ -f "$_SCAN_ROOT/requirements.txt" ] || [ -f "$_SCAN_ROOT/pyproject.toml" ]; then
    command -v pip-audit >/dev/null 2>&1 || return 0
    _HAD_TOOL=1
    echo "INFO: pip-audit 실행 중..." >&2
    if pip-audit -r "${_SCAN_ROOT}/requirements.txt" -f json -o "$_RAW/pip-audit.json" 2>"$_RAW/pip-audit.err" \
       || [ -f "$_SCAN_ROOT/pyproject.toml" ]; then
      if [ -s "$_RAW/pip-audit.json" ]; then
        _n=$(jq '.dependencies | length' "$_RAW/pip-audit.json" 2>/dev/null || grep -c '"name"' "$_RAW/pip-audit.json" || echo 0)
        if [ "${_n:-0}" -gt 0 ]; then
          _HAD_FINDING=1
          append_finding "{\"tool\":\"pip-audit\",\"vulnerabilities\":$_n,\"details\":\"$_RAW/pip-audit.json\"}"
        fi
      fi
    fi
  elif [ -f "$_SCAN_ROOT/Cargo.lock" ]; then
    command -v cargo >/dev/null 2>&1 || return 0
    _HAD_TOOL=1
    echo "INFO: cargo audit 실행 중..." >&2
    ( cd "$_SCAN_ROOT" && cargo audit --json > "$_RAW/cargo-audit.json" 2>"$_RAW/cargo-audit.err" )
    if [ -s "$_RAW/cargo-audit.json" ]; then
      _n=$(jq '.vulnerabilities | length' "$_RAW/cargo-audit.json" 2>/dev/null || grep -c '"advisory"' "$_RAW/cargo-audit.json" || echo 0)
      if [ "${_n:-0}" -gt 0 ]; then
        _HAD_FINDING=1
        append_finding "{\"tool\":\"cargo-audit\",\"vulnerabilities\":$_n,\"details\":\"$_RAW/cargo-audit.json\"}"
      fi
    fi
  fi
}

# === 실행 ===
run_semgrep
run_gitleaks
run_trufflehog
run_dep_scan

printf ']' >> "$_FINDINGS"

# === exit code 결정 (secure-coding.md §8 규약) ===
if [ "$_HAD_TOOL" -eq 0 ]; then
  echo "WARN: L1 도구가 하나도 가동 안 됨 — L2로 폴백." >&2
  echo '{"status":"no-tool","fallback":"L2"}' > "$_OUT_DIR/l1-summary.json"
  exit 2
fi

# 요약 산출
cat > "$_OUT_DIR/l1-summary.json" <<EOF
{
  "status": "$([ "$_HAD_FINDING" -eq 1 ] && echo FAIL || echo PASS)",
  "had_error": $([ "$_HAD_ERROR" -eq 1 ] && echo true || echo false),
  "findings_file": "$_FINDINGS",
  "raw_dir": "$_RAW"
}
EOF

if [ "$_HAD_FINDING" -eq 1 ]; then
  echo "FAIL: L1 보안 취약점 발견 — $_FINDINGS 참조." >&2
  exit 1
elif [ "$_HAD_ERROR" -eq 1 ]; then
  echo "WARN: 도구 오류 일부 발생 — L2로 폴백 권장." >&2
  exit 2
else
  echo "PASS: L1 발견 0." >&2
  exit 0
fi
