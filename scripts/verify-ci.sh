#!/usr/bin/env bash
# =============================================================================
# CLEAR verify-ci.sh — Local CI/CD enforcement script
# =============================================================================
# Run this script before marking ANY AI-generated work as complete.
# It mirrors the checks your CI/CD pipeline runs, catching failures locally
# in seconds instead of waiting for the pipeline.
#
# CLEAR Principle: [C] Constrained — enforced, not suggested
#
# Usage:
#   ./scripts/verify-ci.sh           # Run all checks
#   ./scripts/verify-ci.sh --fast    # Skip slow checks (architecture tests)
#   ./scripts/verify-ci.sh --fix     # Auto-fix linting issues where possible
#
# AI Instructions: Run this script after generating or modifying any code.
# If it fails, fix the issues and run again. Only report work as complete
# when ALL checks pass. Never skip or bypass this script.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAST_MODE=false
FIX_MODE=false
FAILED_CHECKS=()

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --fast) FAST_MODE=true ;;
    --fix)  FIX_MODE=true ;;
  esac
done

# ─── Helpers ──────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; FAILED_CHECKS+=("$1"); }
info() { echo -e "${BLUE}ℹ  $1${NC}"; }
warn() { echo -e "${YELLOW}⚠  $1${NC}"; }
section() { echo -e "\n${BLUE}── $1 ──${NC}"; }

run_check() {
  local name="$1"
  local cmd="$2"
  info "Running: $cmd"
  if eval "$cmd"; then
    pass "$name"
    return 0
  else
    fail "$name"
    return 1
  fi
}

# ─── Project Type Detection ───────────────────────────────────────────────────

detect_project() {
  HAS_NODE=false
  HAS_PYTHON=false
  HAS_GO=false
  HAS_RUST=false
  HAS_MAKE=false

  [[ -f "$PROJECT_ROOT/package.json" ]]   && HAS_NODE=true   || true
  [[ -f "$PROJECT_ROOT/pyproject.toml" || -f "$PROJECT_ROOT/setup.py" || -f "$PROJECT_ROOT/requirements.txt" ]] && HAS_PYTHON=true || true
  [[ -f "$PROJECT_ROOT/go.mod" ]]   && HAS_GO=true   || true
  [[ -f "$PROJECT_ROOT/Cargo.toml" ]] && HAS_RUST=true  || true
  [[ -f "$PROJECT_ROOT/Makefile" ]]   && HAS_MAKE=true  || true
}

# ─── Check Groups ─────────────────────────────────────────────────────────────

check_build() {
  section "Build"

  if $HAS_NODE; then
    if [[ -f "$PROJECT_ROOT/package.json" ]]; then
      local build_script
      build_script=$(node -e "const p=require('$PROJECT_ROOT/package.json'); console.log(p.scripts && p.scripts.build ? 'build' : '')" 2>/dev/null || echo "")
      if [[ -n "$build_script" ]]; then
        run_check "npm build" "cd '$PROJECT_ROOT' && npm run build 2>&1" || true
      else
        info "No build script found in package.json — skipping"
      fi
    fi
  fi

  if $HAS_PYTHON; then
    run_check "Python syntax check" "python3 -m compileall '$PROJECT_ROOT' -q 2>&1 | head -20" || true
  fi

  if $HAS_GO; then
    run_check "Go build" "cd '$PROJECT_ROOT' && go build ./... 2>&1" || true
  fi

  if $HAS_RUST; then
    run_check "Cargo build" "cd '$PROJECT_ROOT' && cargo build 2>&1" || true
  fi

  # ── ADD YOUR PROJECT-SPECIFIC BUILD COMMANDS BELOW ──
  # Example: run_check "Generate protos" "cd '$PROJECT_ROOT' && make proto 2>&1"
  # Example: run_check "Generate types" "cd '$PROJECT_ROOT' && npm run gen:types 2>&1"
}

check_lint() {
  section "Linting"

  if $HAS_NODE; then
    local fix_flag=""
    $FIX_MODE && fix_flag="--fix"

    if node -e "require('$PROJECT_ROOT/node_modules/.bin/eslint')" 2>/dev/null; then
      run_check "ESLint" "cd '$PROJECT_ROOT' && npx eslint . $fix_flag 2>&1" || true
    elif [[ -f "$PROJECT_ROOT/.eslintrc.js" || -f "$PROJECT_ROOT/.eslintrc.json" || -f "$PROJECT_ROOT/eslint.config.js" ]]; then
      warn "ESLint config found but ESLint not installed. Run: npm install"
    fi

    if node -e "require('$PROJECT_ROOT/node_modules/.bin/prettier')" 2>/dev/null; then
      local prettier_flag="--check"
      $FIX_MODE && prettier_flag="--write"
      run_check "Prettier" "cd '$PROJECT_ROOT' && npx prettier $prettier_flag . 2>&1" || true
    fi

    if node -e "require('$PROJECT_ROOT/node_modules/typescript')" 2>/dev/null; then
      run_check "TypeScript (no-emit)" "cd '$PROJECT_ROOT' && npx tsc --noEmit 2>&1" || true
    fi
  fi

  if $HAS_PYTHON; then
    if command -v ruff &>/dev/null; then
      local fix_flag=""
      $FIX_MODE && fix_flag="--fix"
      run_check "Ruff" "cd '$PROJECT_ROOT' && ruff check $fix_flag . 2>&1" || true
    elif command -v flake8 &>/dev/null; then
      run_check "Flake8" "cd '$PROJECT_ROOT' && flake8 . 2>&1" || true
    fi

    if command -v mypy &>/dev/null; then
      run_check "Mypy" "cd '$PROJECT_ROOT' && mypy . 2>&1" || true
    fi
  fi

  if $HAS_GO; then
    run_check "Go vet" "cd '$PROJECT_ROOT' && go vet ./... 2>&1" || true
    if command -v golint &>/dev/null; then
      run_check "Golint" "cd '$PROJECT_ROOT' && golint ./... 2>&1" || true
    fi
  fi

  # ── ADD YOUR PROJECT-SPECIFIC LINT COMMANDS BELOW ──
}

check_tests() {
  section "Tests"

  if $HAS_NODE; then
    local test_script
    test_script=$(node -e "const p=require('$PROJECT_ROOT/package.json'); console.log(p.scripts && p.scripts.test ? 'test' : '')" 2>/dev/null || echo "")
    if [[ -n "$test_script" ]]; then
      run_check "npm test" "cd '$PROJECT_ROOT' && npm test 2>&1" || true
    fi
  fi

  if $HAS_PYTHON; then
    if command -v pytest &>/dev/null; then
      run_check "pytest" "cd '$PROJECT_ROOT' && pytest --tb=short -q 2>&1" || true
    fi
  fi

  if $HAS_GO; then
    run_check "Go test" "cd '$PROJECT_ROOT' && go test ./... 2>&1" || true
  fi

  if $HAS_RUST; then
    run_check "Cargo test" "cd '$PROJECT_ROOT' && cargo test 2>&1" || true
  fi

  # ── ADD YOUR PROJECT-SPECIFIC TEST COMMANDS BELOW ──
}

check_architecture() {
  section "Architecture Tests"

  if $FAST_MODE; then
    warn "Architecture tests skipped (--fast mode)"
    return 0
  fi

  if $HAS_NODE; then
    local arch_script
    arch_script=$(node -e "const p=require('$PROJECT_ROOT/package.json'); console.log(p.scripts && p.scripts['test:architecture'] ? 'test:architecture' : '')" 2>/dev/null || echo "")
    if [[ -n "$arch_script" ]]; then
      run_check "Architecture tests" "cd '$PROJECT_ROOT' && npm run test:architecture 2>&1" || true
    fi
  fi

  if $HAS_PYTHON; then
    if [[ -d "$PROJECT_ROOT/tests/architecture" ]]; then
      run_check "Architecture tests (pytest)" "cd '$PROJECT_ROOT' && pytest tests/architecture/ --tb=short -q 2>&1" || true
    fi
  fi

  # ── ADD YOUR ARCHITECTURE TEST COMMANDS BELOW ──
  # These are the tests that enforce structural rules — see templates/architecture-tests/
  # Example: run_check "API rate limiting" "cd '$PROJECT_ROOT' && npx jest tests/architecture/api-rules.test.js 2>&1"
}

check_autonomy() {
  section "CLEAR Autonomy Boundaries"

  if [[ -f "$PROJECT_ROOT/clear/autonomy.yml" ]]; then
    pass "autonomy.yml found"

    # Check for humans-only paths — warn if git staging area contains any
    if command -v git &>/dev/null && git -C "$PROJECT_ROOT" rev-parse --git-dir &>/dev/null; then
      local staged_files
      staged_files=$(git -C "$PROJECT_ROOT" diff --cached --name-only 2>/dev/null || echo "")
      if [[ -n "$staged_files" ]]; then
        # Read humans-only paths from autonomy.yml (basic grep, no yaml parser required)
        while IFS= read -r humans_path; do
          humans_path=$(echo "$humans_path" | sed 's/.*path: //' | tr -d '"' | tr -d "'")
          if echo "$staged_files" | grep -q "$humans_path"; then
            warn "Staged file matches humans-only path: $humans_path"
            warn "Review clear/autonomy.yml before committing AI-generated changes to this path."
          fi
        done < <(grep -A2 "level: humans-only" "$PROJECT_ROOT/clear/autonomy.yml" 2>/dev/null | grep "path:" || true)
      fi
    fi
  else
    warn "clear/autonomy.yml not found — run scripts/setup-clear.sh to configure autonomy boundaries"
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
  echo -e "${BLUE}════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  CLEAR — Local CI/CD Verification          ${NC}"
  echo -e "${BLUE}════════════════════════════════════════════${NC}"

  cd "$PROJECT_ROOT"
  detect_project

  info "Project root: $PROJECT_ROOT"
  $HAS_NODE   && info "Detected: Node.js"
  $HAS_PYTHON && info "Detected: Python"
  $HAS_GO     && info "Detected: Go"
  $HAS_RUST   && info "Detected: Rust"
  $FAST_MODE  && warn "Fast mode: architecture tests skipped"
  $FIX_MODE   && warn "Fix mode: auto-fixing lint issues where possible"

  check_build
  check_lint
  check_tests
  check_architecture
  check_autonomy

  echo ""
  echo -e "${BLUE}════════════════════════════════════════════${NC}"
  if [[ ${#FAILED_CHECKS[@]} -eq 0 ]]; then
    echo -e "${GREEN}✅ All checks passed — work is complete.${NC}"
    echo -e "${GREEN}   You may now commit your changes.${NC}"
    exit 0
  else
    echo -e "${RED}❌ ${#FAILED_CHECKS[@]} check(s) failed:${NC}"
    for check in "${FAILED_CHECKS[@]}"; do
      echo -e "${RED}   • $check${NC}"
    done
    echo ""
    echo -e "${RED}   Fix the issues above and run this script again.${NC}"
    echo -e "${RED}   Work is NOT complete until all checks pass.${NC}"
    exit 1
  fi
}

main "$@"
