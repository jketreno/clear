#!/usr/bin/env bash
# =============================================================================
# CLEAR setup-clear.sh — Interactive setup wizard
# =============================================================================
# Guides you through configuring CLEAR for an existing project.
# Run this once when adopting CLEAR in a new codebase.
#
# Usage:
#   ./scripts/setup-clear.sh               # configure current project
#   ./scripts/setup-clear.sh /path/to/proj  # configure a different project
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Accept an explicit project root as the first argument (used by bootstrap-project.sh)
# so we always run the latest wizard from the CLEAR repo, not the target's stale copy.
if [[ -n "${1:-}" ]]; then
  PROJECT_ROOT="$(cd "$1" && pwd)"
else
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}ℹ  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn()    { echo -e "${YELLOW}⚠  $1${NC}"; }

header() {
  echo ""
  echo -e "${BLUE}════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}════════════════════════════════════════════${NC}"
  echo ""
}

ask() {
  local question="$1"
  local default="${2:-}"
  local answer
  if [[ -n "$default" ]]; then
    printf "${CYAN}?  %s [%s]: ${NC}" "$question" "$default" >&2
  else
    printf "${CYAN}?  %s: ${NC}" "$question" >&2
  fi
  read -r answer
  echo "${answer:-$default}"
}

ask_yn() {
  local question="$1"
  local default="${2:-y}"
  local answer
  if [[ "$default" == "y" ]]; then
    printf "${CYAN}?  %s [Y/n]: ${NC}" "$question" >&2
  else
    printf "${CYAN}?  %s [y/N]: ${NC}" "$question" >&2
  fi
  read -r answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy] ]]
}

# ─── Step 1: Project name ─────────────────────────────────────────────────────

header "CLEAR Setup — Step 1: Project Info"

PROJECT_NAME=$(ask "Project name" "$(basename "$PROJECT_ROOT")")
echo ""
info "Setting up CLEAR for: $PROJECT_NAME"

# ─── Step 2: Autonomy boundaries ──────────────────────────────────────────────

header "CLEAR Setup — Step 2: Autonomy Boundaries [L]"

echo "CLEAR's Limited principle requires you to define which modules AI can"
echo "modify freely vs which need human oversight."
echo ""
echo "Autonomy levels:"
echo "  full-autonomy  — AI can modify freely (e.g., generated code, utilities)"
echo "  supervised     — AI generates, human reviews before merging"
echo "  humans-only    — No AI generation (e.g., payment logic, auth core)"
echo ""

AUTONOMY_ENTRIES=""

add_autonomy_entry() {
  local path level reason
  path=$(ask "  Path (e.g., src/utils, src/payment)")
  level=$(ask "  Level (full-autonomy / supervised / humans-only)" "supervised")
  reason=$(ask "  Reason (why this level?)")
  AUTONOMY_ENTRIES="${AUTONOMY_ENTRIES}
  - path: \"${path}\"
    level: ${level}
    reason: \"${reason}\""
}

info "Add your first autonomy boundary:"
add_autonomy_entry

while ask_yn "Add another boundary?" "y"; do
  add_autonomy_entry
done

# Write autonomy.yml
mkdir -p "$PROJECT_ROOT/clear"
cat > "$PROJECT_ROOT/clear/autonomy.yml" << AUTONOMY_EOF
# =============================================================================
# CLEAR autonomy.yml — Module Autonomy Boundaries
# =============================================================================
# CLEAR Principle: [L] Limited — Define where AI works alone vs with humans
#
# Levels:
#   full-autonomy  — AI can read, modify, and regenerate freely
#   supervised     — AI generates code, but human must review before commit
#   humans-only    — AI must NOT generate code; flag for human attention
#
# AI Instructions: Before modifying any file, check this list. If the file
# falls under a 'humans-only' path, stop and alert the user. If 'supervised',
# generate but add a review reminder. If 'full-autonomy', proceed normally.
# =============================================================================

project: "${PROJECT_NAME}"

modules:${AUTONOMY_ENTRIES}

  # ── Default for uncategorized paths ──────────────────────────────────────
  - path: "*"
    level: supervised
    reason: "Default: untagged modules require human review"
AUTONOMY_EOF

success "Created clear/autonomy.yml"

# ─── Step 3: Source of truth ──────────────────────────────────────────────────

header "CLEAR Setup — Step 3: Reality Alignment [R]"

echo "The Reality-Aligned principle requires declaring a single source of"
echo "truth for each key domain concept. When systems disagree, what wins?"
echo ""

SOURCES_OF_TRUTH=""

declare -a CONCEPTS=()
declare -a SOURCES=()
declare -a SYSTEMS=()

add_source_of_truth() {
  local concept source system
  concept=$(ask "  Domain concept (e.g., User, Order, Subscription)")
  source=$(ask "  Source of truth (e.g., database schema, Stripe, protobuf)")
  system=$(ask "  System/file that defines it (e.g., stripe.subscriptions, schema.prisma)")
  SOURCES_OF_TRUTH="${SOURCES_OF_TRUTH}
  - concept: \"${concept}\"
    source_of_truth: \"${source}\"
    defined_in: \"${system}\""
}

if ask_yn "Add a source of truth declaration?" "y"; then
  add_source_of_truth
  while ask_yn "Add another?" "n"; do
    add_source_of_truth
  done

  # Append to autonomy-adjacent reality file
  cat >> "$PROJECT_ROOT/clear/autonomy.yml" << REALITY_EOF

# =============================================================================
# Reality Alignment — Sources of Truth
# =============================================================================
# AI Instructions: When generating code that touches any of these concepts,
# derive from the declared source. Never invent a representation.
# If implementations conflict, the source_of_truth wins.

sources_of_truth:${SOURCES_OF_TRUTH}
REALITY_EOF

  success "Added sources of truth to clear/autonomy.yml"
fi

# ─── Step 4: verify-ci.sh ─────────────────────────────────────────────────────

header "CLEAR Setup — Step 4: CI Verification [C]"

echo "The Constrained principle requires a local verification script that"
echo "mirrors your CI/CD pipeline. scripts/verify-ci.sh is already provided."
echo ""

if ask_yn "Make scripts/verify-ci.sh executable now?" "y"; then
  chmod +x "$PROJECT_ROOT/scripts/verify-ci.sh"
  chmod +x "$PROJECT_ROOT/scripts/setup-clear.sh"
  success "Scripts are now executable"
fi

echo ""
info "Custom checks you might want to add to scripts/verify-ci.sh:"
echo "  • Your linter (ESLint, Ruff, etc.)"
echo "  • Your test runner (Jest, pytest, go test)"
echo "  • Architecture tests (see templates/architecture-tests/)"
echo "  • Code generation checks (proto, OpenAPI, etc.)"
echo ""
info "Look for the '── ADD YOUR PROJECT-SPECIFIC ... ──' comments in verify-ci.sh"

# ─── Step 5: AI tool configuration ────────────────────────────────────────────

header "CLEAR Setup — Step 5: AI Tool Configuration"

echo "CLEAR works best when your AI tools know about the rules."
echo ""
echo "Already included in this project:"
echo "  • .github/copilot-instructions.md  — GitHub Copilot / VS Code"
echo "  • CLAUDE.md                        — Claude Code"
echo "  • .cursor/rules/                   — Cursor"
echo ""
echo "Next steps per tool:"
echo "  VS Code/Copilot: The .github/copilot-instructions.md is auto-read."
echo "  Claude Code:     The CLAUDE.md in project root is auto-read."
echo "  Cursor:          The .cursor/rules/*.mdc files are applied automatically."
echo ""
echo "See docs/ai-tools/ for detailed setup guides."

# ─── Step 6: First experiment ─────────────────────────────────────────────────

header "CLEAR Setup — Step 6: Your First Experiment"

echo "The fastest way to see CLEAR working is to pick ONE existing code"
echo "review comment that you write every PR."
echo ""
echo "Ask your AI:"
echo "  'Turn this code review rule into an architecture test:"
echo "   [YOUR MOST COMMON REVIEW COMMENT]'"
echo "  'Add it to scripts/verify-ci.sh'"
echo ""
echo "See docs/getting-started.md for the full step-by-step guide."
echo "See templates/architecture-tests/ for examples."

# ─── Summary ─────────────────────────────────────────────────────────────────

header "Setup Complete"

echo "Created/configured:"
echo "  ✅ clear/autonomy.yml          — autonomy boundaries"
echo "  ✅ scripts/verify-ci.sh        — CI enforcement script"
echo ""
echo "Next steps:"
echo "  1. Review clear/autonomy.yml and adjust boundaries for your codebase"
echo "  2. Open scripts/verify-ci.sh and add your project-specific checks"
echo "  3. Run ./scripts/verify-ci.sh to see which checks pass/fail today"
echo "  4. Read docs/getting-started.md for the full workflow"
echo ""
success "CLEAR is configured for: $PROJECT_NAME"
