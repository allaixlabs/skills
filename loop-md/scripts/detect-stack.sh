#!/usr/bin/env bash
# detect-stack.sh — 프로젝트 스택을 감지해 빌드/타입체크/테스트/린트 명령어를 추출한다.
#
# 사용법:
#   bash detect-stack.sh [PROJECT_DIR]   (기본값: 현재 디렉토리)
#
# 출력(stdout): KEY=VALUE 형식 (한 줄에 하나). 미감지 키는 플레이스홀더로 남긴다.
#   STACK, PKG_MANAGER, IS_MONOREPO, BUILD_CMD, TYPECHECK_CMD, TEST_CMD, LINT_CMD, COVERAGE_CMD
# 진단(stderr): monorepo 경고, 미감지 키 요약 (조용한 통과 방지).
#
# read-only: 어떤 파일도 수정하지 않는다. 매니페스트만 읽는다.
set -euo pipefail

DIR="${1:-.}"
cd "$DIR"

# 플레이스홀더 기본값 — loop.md.tmpl 의 {{...}} 와 매칭
STACK="<감지 실패: 직접 입력>"
PKG_MANAGER=""
IS_MONOREPO="no"
BUILD_CMD="<빌드 명령>"
TYPECHECK_CMD="<타입체크 명령>"
TEST_CMD="<테스트 명령>"
LINT_CMD="<린트 명령>"
COVERAGE_CMD="<커버리지 명령>"

# package.json 의 scripts.<name> 존재 여부 (node 우선, 없으면 grep 폴백)
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

# 패키지매니저별 바이너리 실행기 (폴백 명령에 사용 — npx 하드코딩 금지)
pkg_exec() {
  case "$1" in
    pnpm) echo "pnpm exec" ;;
    yarn) echo "yarn" ;;       # yarn 은 yarn <bin> 으로 로컬 bin 실행
    bun)  echo "bunx" ;;
    *)    echo "npx" ;;
  esac
}

# ---------- Node / TypeScript ----------
if [ -f package.json ]; then
  PKG_MANAGER="$(detect_pkg_manager)"
  RUN="$PKG_MANAGER run"; [ "$PKG_MANAGER" = "npm" ] && RUN="npm run"
  EXEC="$(pkg_exec "$PKG_MANAGER")"

  STACK="Node.js"
  if [ -f tsconfig.json ]; then
    STACK="TypeScript / Node.js"
    TYPECHECK_CMD="$EXEC tsc --noEmit"
  fi

  has_npm_script build      && BUILD_CMD="$RUN build"
  has_npm_script typecheck  && TYPECHECK_CMD="$RUN typecheck"
  has_npm_script type-check && TYPECHECK_CMD="$RUN type-check"
  has_npm_script test       && TEST_CMD="$RUN test"
  has_npm_script lint       && LINT_CMD="$RUN lint"
  has_npm_script coverage        && COVERAGE_CMD="$RUN coverage"
  has_npm_script "test:coverage" && COVERAGE_CMD="$RUN test:coverage"

  if [ "$LINT_CMD" = "<린트 명령>" ]; then
    if   ls .eslintrc* >/dev/null 2>&1 || grep -q '"eslint"' package.json 2>/dev/null; then LINT_CMD="$EXEC eslint ."
    elif [ -f biome.json ]; then LINT_CMD="$EXEC biome check ."
    fi
  fi

  # monorepo 감지 (워크스페이스)
  if [ -f pnpm-workspace.yaml ] || grep -q '"workspaces"' package.json 2>/dev/null; then
    IS_MONOREPO="yes"
    echo "경고: monorepo(워크스페이스)로 보입니다. 루트 매니페스트만 감지했습니다." >&2
    echo "      각 워크스페이스 패키지별로 빌드/테스트 명령을 loop.md 에서 보완하세요." >&2
  fi

# ---------- Rust ----------
elif [ -f Cargo.toml ]; then
  STACK="Rust"
  BUILD_CMD="cargo build"
  TYPECHECK_CMD="cargo check"
  TEST_CMD="cargo test"
  LINT_CMD="cargo clippy -- -D warnings"
  COVERAGE_CMD="cargo tarpaulin"
  if grep -qE '^\[workspace\]' Cargo.toml 2>/dev/null; then
    IS_MONOREPO="yes"
    echo "경고: Cargo workspace 입니다. 명령에 --workspace 추가를 고려하세요." >&2
  fi

# ---------- Python ----------
elif [ -f pyproject.toml ] || [ -f setup.cfg ] || [ -f setup.py ]; then
  STACK="Python"
  BUILD_CMD="python -m build"
  TEST_CMD="pytest"
  COVERAGE_CMD="pytest --cov"
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
  if [ -f go.work ]; then
    IS_MONOREPO="yes"
    echo "경고: go.work 멀티모듈 워크스페이스입니다." >&2
  fi

# ---------- Makefile 폴백 ----------
elif [ -f Makefile ]; then
  STACK="Make 기반"
  grep -qE "^build:" Makefile     && BUILD_CMD="make build"
  grep -qE "^test:" Makefile      && TEST_CMD="make test"
  grep -qE "^lint:" Makefile      && LINT_CMD="make lint"
  grep -qE "^typecheck:" Makefile && TYPECHECK_CMD="make typecheck"
fi

# 미감지 키 요약 (stderr) — 조용한 통과 방지
MISSING=""
for kv in "BUILD_CMD=$BUILD_CMD" "TYPECHECK_CMD=$TYPECHECK_CMD" "TEST_CMD=$TEST_CMD" "LINT_CMD=$LINT_CMD" "COVERAGE_CMD=$COVERAGE_CMD"; do
  case "$kv" in *"<"*">"*) MISSING="$MISSING ${kv%%=*}";; esac
done
if [ -n "$MISSING" ]; then
  echo "주의: 자동 감지 실패한 명령:$MISSING → loop.md 에서 직접 채우세요." >&2
fi

# 출력 (stdout)
cat <<EOF
STACK=$STACK
PKG_MANAGER=$PKG_MANAGER
IS_MONOREPO=$IS_MONOREPO
BUILD_CMD=$BUILD_CMD
TYPECHECK_CMD=$TYPECHECK_CMD
TEST_CMD=$TEST_CMD
LINT_CMD=$LINT_CMD
COVERAGE_CMD=$COVERAGE_CMD
EOF
