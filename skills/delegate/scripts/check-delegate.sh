#!/usr/bin/env bash

set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SELF_DIR/../.."

_t() {
  _seconds="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$_seconds" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$_seconds" "$@"
  else
    "$@"
  fi
}

usage() {
  cat <<'EOF'
usage:
  check-delegate.sh <plan-then-codex|plan-then-opencode|plan-codex-opencode|plan-fusion|plan-fusion-dev>
  check-delegate.sh --matrix
EOF
}

skill_check_script() {
  case "$1" in
    plan-then-codex) echo "check-codex.sh" ;;
    plan-then-opencode) echo "check-omo.sh" ;;
    plan-codex-opencode) echo "check-panels.sh" ;;
    plan-fusion) echo "check-fusion.sh" ;;
    plan-fusion-dev) echo "check-fusion-dev.sh" ;;
    *) return 1 ;;
  esac
}

backend_probe() {
  _name="$1"
  if _path="$(_t 3 sh -c 'command -v "$1"' sh "$_name" 2>/dev/null)"; then
    printf '%s' "$_path"
  else
    printf '<missing>'
  fi
}

backend_flag() {
  _name="$1"
  if _t 3 sh -c 'command -v "$1" >/dev/null' sh "$_name"; then
    printf 'yes'
  else
    printf 'no'
  fi
}

matrix_backend_hint() {
  case "$1" in
    plan-then-codex)
      printf 'codex=%s' "$(backend_flag codex)"
      ;;
    plan-then-opencode)
      printf 'opencode=%s omo=%s' "$(backend_flag opencode)" "$(backend_flag omo)"
      ;;
    plan-codex-opencode)
      printf 'codex=%s opencode=%s omo=%s' "$(backend_flag codex)" "$(backend_flag opencode)" "$(backend_flag omo)"
      ;;
    plan-fusion|plan-fusion-dev)
      printf 'codex=%s opencode=%s agy=%s claude=%s' "$(backend_flag codex)" "$(backend_flag opencode)" "$(backend_flag agy)" "$(backend_flag claude)"
      ;;
  esac
}

run_matrix() {
  echo "MODE=matrix"
  echo "PROBE_CODEX=$(backend_probe codex)"
  echo "PROBE_OPENCODE=$(backend_probe opencode)"
  echo "PROBE_AGY=$(backend_probe agy)"
  echo "PROBE_CLAUDE=$(backend_probe claude)"

  _installed=0
  for _skill in plan-then-codex plan-then-opencode plan-codex-opencode plan-fusion plan-fusion-dev; do
    _check_name="$(skill_check_script "$_skill")"
    _skill_file="$SKILLS_DIR/$_skill/SKILL.md"
    _check_file="$SKILLS_DIR/$_skill/scripts/$_check_name"

    if [ -f "$_skill_file" ]; then
      _skill_present=yes
    else
      _skill_present=no
    fi

    if [ -x "$_check_file" ]; then
      _check_present=yes
    elif [ -f "$_check_file" ]; then
      _check_present=yes-not-executable
    else
      _check_present=no
    fi

    if [ "$_skill_present" = yes ] && [ "$_check_present" != no ]; then
      _installed=$((_installed + 1))
      _status=installed
    else
      _status=missing
    fi

    printf 'SKILL=%s STATUS=%s SKILL_MD=%s CHECK=%s BACKENDS="%s"\n' \
      "$_skill" "$_status" "$_skill_present" "$_check_present" "$(matrix_backend_hint "$_skill")"
  done

  echo "INSTALLED_SKILLS=$_installed"
  if [ "$_installed" -gt 0 ]; then
    exit 0
  fi
  exit 1
}

run_selected() {
  _skill="$1"
  if ! _check_name="$(skill_check_script "$_skill")"; then
    echo "DELEGATE_ROUTE=unknown"
    echo "SELECTED_SKILL=$_skill"
    echo "HINT: 지원 스킬은 plan-then-codex, plan-then-opencode, plan-codex-opencode, plan-fusion, plan-fusion-dev 입니다." >&2
    exit 1
  fi

  _skill_file="$SKILLS_DIR/$_skill/SKILL.md"
  _check_file="$SKILLS_DIR/$_skill/scripts/$_check_name"

  echo "MODE=route-first"
  echo "SELECTED_SKILL=$_skill"
  echo "SKILL_MD=$_skill_file"
  echo "CHECK_SCRIPT=$_check_file"

  if [ ! -f "$_skill_file" ]; then
    echo "SKILL_INSTALLED=no"
    echo "HINT: 해당 스킬 미설치: $_skill. npx skills add allaixlabs/skills --skill $_skill --agent claude-code" >&2
    exit 1
  fi
  echo "SKILL_INSTALLED=yes"

  if [ ! -f "$_check_file" ]; then
    echo "CHECK_SCRIPT_PRESENT=no"
    echo "HINT: 해당 스킬 미설치 또는 불완전: $_skill ($_check_name 없음)." >&2
    exit 1
  fi
  echo "CHECK_SCRIPT_PRESENT=yes"

  bash "$_check_file"
}

if [ "$#" -eq 0 ]; then
  usage >&2
  exit 1
fi

case "$1" in
  --matrix)
    run_matrix
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    run_selected "$1"
    ;;
esac
