#!/usr/bin/env bash
# detect-stack.sh — 프로젝트 스택을 감지해 빌드/타입체크/테스트/린트 명령어를 추출한다.
#
# 사용법:
#   bash detect-stack.sh [PROJECT_DIR]   (기본값: 현재 디렉토리)
#
# 출력: KEY=VALUE 형식 (한 줄에 하나). 미감지 키는 플레이스홀더로 남긴다.
#   STACK, PKG_MANAGER, BUILD_CMD, TYPECHECK_CMD, TEST_CMD, LINT_CMD, COVERAGE_CMD
#
# read-only: 어떤 파일도 수정하지 않는다. 매니페스트만 읽는다.
set -euo pipefail

DIR="${1:-.}"
cd "$DIR"

# 플레이스홀더 기본값 — loop.md.tmpl 의 {{...}} 와 매칭
STACK="<감지 실패: 직접 입력>"
PKG_MANAGER=""
BUILD_CMD="<빌드 명령>"
TYPECHECK_CMD="<타입체크 명령>"
TEST_CMD="<테스트 명령>"
LINT_CMD="<린트 명령>"
COVERAGE_CMD="<커버리지 명령>"

# package.json 의 scripts.<name> 존재 여부 확인 (node 우선, 없으면 grep 폴백)
has_npm_script() {
  local name="$1"
  if command -v node >/dev/null 2>&1; then
    node -e "try{const s=require('./package.json').scripts||{};process.exit(s['$name']?0:1)}catch(e){process.exit(1)}" 2>/dev/null
  else
    grep -qE "\"$name\"[[:space:]]*:" package.json 2>/dev/null
  fi
}

detect_pkg_manager() {
  if   [ -f pnpm-lock.yaml ]; then echo "pnpm"
  elif [ -f yarn.lock ];      then echo "yarn"
  elif [ -f bun.lockb ];      then echo "bun"
  else echo "npm"
  fi
}

# ---------- Node / TypeScript ----------
if [ -f package.json ]; then
  PKG_MANAGER="$(detect_pkg_manager)"
  RUN="$PKG_MANAGER run"
  [ "$PKG_MANAGER" = "npm" ] && RUN="npm run"

  STACK="Node.js"
  if [ -f tsconfig.json ]; then
    STACK="TypeScript / Node.js"
    TYPECHECK_CMD="npx tsc --noEmit"
  fi

  has_npm_script build     && BUILD_CMD="$RUN build"
  has_npm_script typecheck  && TYPECHECK_CMD="$RUN typecheck"
  has_npm_script type-check && TYPECHECK_CMD="$RUN type-check"
  has_npm_script test       && TEST_CMD="$RUN test"
  has_npm_script lint       && LINT_CMD="$RUN lint"
  has_npm_script coverage   && COVERAGE_CMD="$RUN coverage"
  has_npm_script "test:coverage" && COVERAGE_CMD="$RUN test:coverage"

  # 린트 설정 폴백
  if [ "$LINT_CMD" = "<린트 명령>" ]; then
    if   ls .eslintrc* >/dev/null 2>&1 || grep -q '"eslint"' package.json 2>/dev/null; then LINT_CMD="npx eslint ."
    elif [ -f biome.json ]; then LINT_CMD="npx biome check ."
    fi
  fi

# ---------- Rust ----------
elif [ -f Cargo.toml ]; then
  STACK="Rust"
  BUILD_CMD="cargo build"
  TYPECHECK_CMD="cargo check"
  TEST_CMD="cargo test"
  LINT_CMD="cargo clippy -- -D warnings"
  COVERAGE_CMD="cargo tarpaulin"

# ---------- Python ----------
elif [ -f pyproject.toml ] || [ -f setup.cfg ] || [ -f setup.py ]; then
  STACK="Python"
  BUILD_CMD="python -m build"
  TEST_CMD="pytest"
  COVERAGE_CMD="pytest --cov"
  # 도구 감지
  if grep -qiE "mypy" pyproject.toml setup.cfg 2>/dev/null; then TYPECHECK_CMD="mypy ."; fi
  if   grep -qiE "ruff" pyproject.toml setup.cfg 2>/dev/null; then LINT_CMD="ruff check ."
  elif grep -qiE "flake8" pyproject.toml setup.cfg 2>/dev/null; then LINT_CMD="flake8"
  fi

# ---------- Go ----------
elif [ -f go.mod ]; then
  STACK="Go"
  BUILD_CMD="go build ./..."
  TYPECHECK_CMD="go vet ./..."
  TEST_CMD="go test ./..."
  LINT_CMD="golangci-lint run"
  COVERAGE_CMD="go test -cover ./..."

# ---------- Makefile 폴백 ----------
elif [ -f Makefile ]; then
  STACK="Make 기반"
  grep -qE "^build:" Makefile     && BUILD_CMD="make build"
  grep -qE "^test:" Makefile      && TEST_CMD="make test"
  grep -qE "^lint:" Makefile      && LINT_CMD="make lint"
  grep -qE "^typecheck:" Makefile && TYPECHECK_CMD="make typecheck"
fi

# 출력
cat <<EOF
STACK=$STACK
PKG_MANAGER=$PKG_MANAGER
BUILD_CMD=$BUILD_CMD
TYPECHECK_CMD=$TYPECHECK_CMD
TEST_CMD=$TEST_CMD
LINT_CMD=$LINT_CMD
COVERAGE_CMD=$COVERAGE_CMD
EOF
