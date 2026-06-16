#!/usr/bin/env bash
# detect-stack.sh — 프로젝트 스택을 감지해 빌드/타입체크/테스트/린트 명령어 "힌트"를 추출한다.
#
# ⚠️ 이 스크립트는 단정기가 아니라 **힌트 제공기**다. 풀스택·다중서비스 프로젝트에서는
#    누락이 있을 수 있으므로, SKILL.md 지침대로 **Claude의 직접 분석이 항상 우선**한다.
#
# 사용법:  bash detect-stack.sh [PROJECT_DIR]   (기본값: 현재 디렉토리)
#
# 출력(stdout): KEY=VALUE. 여러 스택이 잡히면 <STACK>_* 키로도 각각 출력한다.
#   DETECTED_STACKS, PRIMARY_STACK, IS_MULTISERVICE, COVERAGE_FLOOR
#   BUILD_CMD/TYPECHECK_CMD/TEST_CMD/LINT_CMD/COVERAGE_CMD  (= PRIMARY 스택 기준, 하위호환)
#   RUBY_* / NODE_* / PYTHON_* / GO_* (감지된 스택별 명령)
# 진단(stderr): 다중서비스·미감지 경고.
#
# read-only · bash 3.2(macOS 기본) 호환: 연관배열·declare -A 미사용.
set -euo pipefail

DIR="${1:-.}"
cd "$DIR"

DETECTED=""
COVERAGE_FLOOR=70

# bin/<tool> 래퍼가 있으면 그것을, 없으면 bundle exec <tool>
rb() { if [ -x "bin/$1" ]; then echo "bin/$1"; else echo "bundle exec $1"; fi; }
# package.json scripts.<name> 존재?
has_npm_script() {
  if command -v node >/dev/null 2>&1; then
    node -e "try{const s=require('./package.json').scripts||{};process.exit(s['$1']?0:1)}catch(e){process.exit(1)}" 2>/dev/null
  else grep -qE "\"$1\"[[:space:]]*:" package.json 2>/dev/null; fi
}
gem_has() { grep -qiE "(^|[^a-z])$1([^a-z]|$)" Gemfile 2>/dev/null; }

# ---------- Ruby / Rails ----------
RUBY_BUILD=""; RUBY_TYPECHECK=""; RUBY_TEST=""; RUBY_LINT=""; RUBY_SECURITY=""; RUBY_AUDIT=""; RUBY_COVERAGE=""
if [ -f Gemfile ]; then
  DETECTED="$DETECTED ruby"
  gem_has rubocop && RUBY_LINT="$(rb rubocop)"
  if [ -f bin/rails ] || gem_has rails; then
    if [ -d spec ] || gem_has rspec; then RUBY_TEST="$(rb rspec)"; else RUBY_TEST="$(rb rails) test"; fi
  elif gem_has rspec; then RUBY_TEST="$(rb rspec)"
  else RUBY_TEST="bundle exec rake test"; fi
  gem_has brakeman      && RUBY_SECURITY="$(rb brakeman) --no-pager"
  gem_has bundler-audit && RUBY_AUDIT="$(rb bundler-audit)"
  gem_has simplecov     && RUBY_COVERAGE="(SimpleCov: 테스트 실행 시 coverage/ 생성)"
  gem_has sorbet        && RUBY_TYPECHECK="$(rb srb) tc"
fi

# ---------- Node / TypeScript ----------
NODE_BUILD=""; NODE_TYPECHECK=""; NODE_TEST=""; NODE_LINT=""; NODE_COVERAGE=""
if [ -f package.json ]; then
  DETECTED="$DETECTED node"
  pm="npm"; [ -f pnpm-lock.yaml ] && pm="pnpm"; [ -f yarn.lock ] && pm="yarn"; [ -f bun.lockb ] && pm="bun"
  RUN="$pm run"; [ "$pm" = npm ] && RUN="npm run"
  case "$pm" in pnpm) EXEC="pnpm exec";; yarn) EXEC="yarn";; bun) EXEC="bunx";; *) EXEC="npx";; esac
  [ -f tsconfig.json ] && NODE_TYPECHECK="$EXEC tsc --noEmit"
  has_npm_script build      && NODE_BUILD="$RUN build"
  has_npm_script typecheck  && NODE_TYPECHECK="$RUN typecheck"
  has_npm_script test       && NODE_TEST="$RUN test"
  has_npm_script lint       && NODE_LINT="$RUN lint"
  has_npm_script coverage   && NODE_COVERAGE="$RUN coverage"
  if [ -z "$NODE_BUILD" ] && grep -q '"vite"' package.json 2>/dev/null; then NODE_BUILD="$EXEC vite build"; fi
  if [ -z "$NODE_LINT" ]; then
    if ls .eslintrc* >/dev/null 2>&1 || grep -q '"eslint"' package.json 2>/dev/null; then NODE_LINT="$EXEC eslint ."
    elif [ -f biome.json ]; then NODE_LINT="$EXEC biome check ."; fi
  fi
fi

# ---------- Python ----------
PYTHON_BUILD=""; PYTHON_TYPECHECK=""; PYTHON_TEST=""; PYTHON_LINT=""; PYTHON_COVERAGE=""
PYDIR=""
if [ -f pyproject.toml ] || [ -f setup.cfg ] || [ -f setup.py ] || [ -f pyrightconfig.json ]; then PYDIR="."; fi
# 서브디렉토리 Python 서비스도 1뎁스 탐색 (예: pii_service/)
if [ -z "$PYDIR" ]; then
  for d in */; do
    if [ -f "${d}pyproject.toml" ] || [ -f "${d}pyrightconfig.json" ]; then PYDIR="${d%/}"; break; fi
  done
fi
if [ -n "$PYDIR" ]; then
  DETECTED="$DETECTED python"
  PFX=""; [ "$PYDIR" != "." ] && PFX="cd '$PYDIR' && "
  PYTHON_TEST="${PFX}pytest"
  PYTHON_COVERAGE="${PFX}pytest --cov"
  if [ -f "$PYDIR/pyrightconfig.json" ]; then PYTHON_TYPECHECK="${PFX}pyright"
  elif grep -qiE '^\[tool\.mypy\]|^[[:space:]]*mypy([[:space:]]|=|$)' "$PYDIR"/pyproject.toml "$PYDIR"/setup.cfg 2>/dev/null; then PYTHON_TYPECHECK="${PFX}mypy ."; fi
  if   grep -qiE '^\[tool\.ruff\]|^[[:space:]]*ruff([[:space:]]|=|$)' "$PYDIR"/pyproject.toml 2>/dev/null; then PYTHON_LINT="${PFX}ruff check ."
  elif grep -qiE '^\[flake8\]|^[[:space:]]*flake8([[:space:]]|=|$)' "$PYDIR"/pyproject.toml "$PYDIR"/setup.cfg 2>/dev/null; then PYTHON_LINT="${PFX}flake8"; fi
fi

# ---------- Go ----------
GO_BUILD=""; GO_TYPECHECK=""; GO_TEST=""; GO_LINT=""; GO_COVERAGE=""
if [ -f go.mod ]; then
  DETECTED="$DETECTED go"
  GO_BUILD="go build ./..."; GO_TYPECHECK="go vet ./..."; GO_TEST="go test ./..."
  GO_LINT="golangci-lint run"; GO_COVERAGE="go test -cover ./..."
fi

DETECTED="$(echo "$DETECTED" | xargs)"   # trim
NSTACK=$(echo "$DETECTED" | wc -w | tr -d ' ')

# 주 스택 결정: 백엔드 우선 (ruby > python > go > node)
PRIMARY=""
for s in ruby python go node; do case " $DETECTED " in *" $s "*) PRIMARY="$s"; break;; esac; done

ph() { [ -n "$1" ] && echo "$1" || echo "<$2>"; }

if [ -n "$PRIMARY" ]; then
  P="$(echo "$PRIMARY" | tr a-z A-Z)"
  eval "BUILD_CMD=\${${P}_BUILD:-}"; eval "TYPECHECK_CMD=\${${P}_TYPECHECK:-}"
  eval "TEST_CMD=\${${P}_TEST:-}";  eval "LINT_CMD=\${${P}_LINT:-}"; eval "COVERAGE_CMD=\${${P}_COVERAGE:-}"
  STACK_LABEL="$PRIMARY"
else
  BUILD_CMD=""; TYPECHECK_CMD=""; TEST_CMD=""; LINT_CMD=""; COVERAGE_CMD=""; STACK_LABEL="<감지 실패: 직접 입력>"
fi

IS_MULTI="no"; [ "$NSTACK" -gt 1 ] && IS_MULTI="yes"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  MANIFESTS=$(git ls-files 2>/dev/null \
    | grep -E '(^|/)(package\.json|Gemfile|go\.mod|pyproject\.toml|setup\.cfg)$' \
    | grep -vE '(^|/)(node_modules|vendor)/' | head -20) || true
else
  MANIFESTS=$(find . -maxdepth 4 \( -name node_modules -o -name vendor -o -name .git \) -prune -o \
    -type f \( -name package.json -o -name Gemfile -o -name go.mod -o -name pyproject.toml \) -print 2>/dev/null \
    | sed 's|^\./||' | head -20) || true
fi
if [ -n "${MANIFESTS:-}" ]; then
  MANIFEST_COUNT="$(printf '%s\n' "$MANIFESTS" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
  [ "${MANIFEST_COUNT:-0}" -ge 2 ] && IS_MULTI="yes"
fi

# ----- 진단 (stderr) -----
if [ "$IS_MULTI" = yes ]; then
  echo "경고: 다중 스택/서비스 감지($DETECTED). 단일 BUILD_CMD 등은 주 스택($PRIMARY) 기준이다." >&2
  echo "      각 서비스 명령은 <STACK>_* 키를 참고해 loop.md에 모두 종합하라." >&2
fi
[ -z "$DETECTED" ] && echo "주의: 알려진 스택 매니페스트를 못 찾음 → loop.md 명령을 직접 채우세요." >&2

# ----- 출력 (stdout) -----
# printf 사용 — heredoc은 임시파일을 만들어 read-only 샌드박스(Codex 등)에서 실패한다.
printf 'DETECTED_STACKS=%s\n'  "$DETECTED"
printf 'PRIMARY_STACK=%s\n'    "$STACK_LABEL"
printf 'IS_MULTISERVICE=%s\n'  "$IS_MULTI"
printf 'COVERAGE_FLOOR=%s\n'   "$COVERAGE_FLOOR"
printf 'BUILD_CMD=%s\n'        "$(ph "$BUILD_CMD" 빌드 명령)"
printf 'TYPECHECK_CMD=%s\n'    "$(ph "$TYPECHECK_CMD" 타입체크 명령)"
printf 'TEST_CMD=%s\n'         "$(ph "$TEST_CMD" 테스트 명령)"
printf 'LINT_CMD=%s\n'         "$(ph "$LINT_CMD" 린트 명령)"
printf 'COVERAGE_CMD=%s\n'     "$(ph "$COVERAGE_CMD" 커버리지 명령)"

[ -n "${MANIFESTS:-}" ] && printf 'MANIFEST_PATHS=%s\n' "$(printf '%s' "$MANIFESTS" | tr '\n' ' ')"

# 감지된 스택별 상세 (다중일 때 Claude가 종합용으로 사용)
for s in $DETECTED; do
  S="$(echo "$s" | tr a-z A-Z)"
  for f in BUILD TYPECHECK TEST LINT SECURITY AUDIT COVERAGE; do
    eval "v=\${${S}_${f}:-}"; [ -n "${v:-}" ] && echo "${S}_${f}_CMD=$v"
  done
done

exit 0   # 마지막 [ -n ] && 패턴의 비-0 상태가 스크립트 종료코드로 새는 것 방지
