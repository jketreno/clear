#!/usr/bin/env bash
# =============================================================================
# CLEAR update-project.sh — Bring a bootstrapped project to the latest CLEAR
# =============================================================================
# Updates agent configs, CLEAR scripts, and previously-installed skills.
# Does NOT overwrite clear/autonomy.yml (your project config) or
# scripts/verify-ci.sh (your CI customizations) unless --update-scripts is set.
#
# Usage:
#   ./scripts/update-project.sh [OPTIONS] [/path/to/your-project]
#   ./scripts/update-project.sh             (updates current directory)
#   ./scripts/update-project.sh --dry-run
#   ./scripts/update-project.sh --update-scripts
# =============================================================================

set -euo pipefail

CLEAR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}ℹ  ${RESET}$*"; }
success() { echo -e "${GREEN}✅ ${RESET}$*"; }
warn()    { echo -e "${YELLOW}⚠  ${RESET}$*"; }
error()   { echo -e "${RED}❌ ${RESET}$*" >&2; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

# ── Defaults
DRY_RUN=false
UPDATE_SCRIPTS=false
TARGET_DIR=""

# ── Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --update-scripts)
      UPDATE_SCRIPTS=true
      shift
      ;;
    --help|-h)
      echo "Usage: $(basename "$0") [OPTIONS] [/path/to/your-project]"
      echo ""
      echo "Updates a CLEAR-bootstrapped project to the latest framework templates."
      echo "Run this from the CLEAR repo when you pull a new version of CLEAR."
      echo ""
      echo "Options:"
      echo "  --dry-run          Show what would change without writing any files"
      echo "  --update-scripts   Also overwrite scripts/verify-ci.sh (normally skipped"
      echo "                     because you add your own checks to that file)"
      echo "  --help             Show this help"
      echo ""
      echo "What gets updated:"
      echo "  • Agent configs    .github/ (not .github/prompts/), .cursor/, .claude/,"
      echo "                     .vscode/, CLAUDE.md, .cursorrules"
      echo "  • CLEAR scripts    scripts/setup-clear.sh, bootstrap-project.sh,"
      echo "                     update-project.sh (self)"
      echo "  • Installed skills .github/prompts/<name>.prompt.md for each skill"
      echo "                     that was previously installed from CLEAR"
      echo ""
      echo "What is never touched:"
      echo "  • clear/autonomy.yml   — your project-specific configuration"
      echo "  • .gitignore           — your project-specific ignores"
      echo "  • scripts/verify-ci.sh — your custom CI checks (use --update-scripts"
      echo "                           to overwrite, then re-add your customizations)"
      exit 0
      ;;
    -*)
      error "Unknown option: $1"
      exit 1
      ;;
    *)
      if [[ -n "$TARGET_DIR" ]]; then
        error "Unexpected argument: $1"
        exit 1
      fi
      TARGET_DIR="$1"
      shift
      ;;
  esac
done

# ── Default target: current directory
if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="$PWD"
fi

# ── Resolve to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
  error "Directory does not exist: $TARGET_DIR"
  exit 1
}

# ── Guard: don't update the CLEAR repo itself
if [[ "$TARGET_DIR" == "$CLEAR_ROOT" ]]; then
  error "Target is the CLEAR seed repo itself."
  echo "  Use 'git pull' inside $CLEAR_ROOT to update CLEAR."
  exit 1
fi

# ── Guard: must be a bootstrapped project
if [[ ! -f "$TARGET_DIR/clear/autonomy.yml" ]]; then
  error "No clear/autonomy.yml found in: $TARGET_DIR"
  echo "  This project does not appear to have been bootstrapped yet."
  echo "  Run: $CLEAR_ROOT/scripts/bootstrap-project.sh $TARGET_DIR"
  exit 1
fi

# ── Tracking
UPDATED=()
CURRENT=()
SKIPPED=()

# ─────────────────────────────────────────────────────────────────────────────
# update_file <src> <dst> [display-label]
#   Copies src → dst if they differ. Reports status.
# ─────────────────────────────────────────────────────────────────────────────
update_file() {
  local src="$1"
  local dst="$2"
  local label="${3:-${dst#"$TARGET_DIR"/}}"

  if [[ ! -f "$src" ]]; then
    warn "Source not found, skipping: $label"
    SKIPPED+=("$label")
    return
  fi

  local dst_dir
  dst_dir="$(dirname "$dst")"

  if [[ -f "$dst" ]] && diff -q "$src" "$dst" > /dev/null 2>&1; then
    echo -e "  ${CYAN}Current ${RESET}: $label"
    CURRENT+=("$label")
    return
  fi

  if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$dst_dir"
    cp "$src" "$dst"
    echo -e "  ${GREEN}Updated ${RESET}: $label"
  else
    if [[ -f "$dst" ]]; then
      echo -e "  ${YELLOW}Would update${RESET}: $label"
    else
      echo -e "  ${CYAN}Would create${RESET}: $label"
    fi
  fi
  UPDATED+=("$label")
}

# ─────────────────────────────────────────────────────────────────────────────
# update_dir <src_dir> <dst_dir> [skip_subpath]
#   Recursively updates all files from src_dir into dst_dir.
#   Paths starting with skip_subpath (relative to src_dir) are skipped.
# ─────────────────────────────────────────────────────────────────────────────
update_dir() {
  local src_dir="$1"
  local dst_dir="$2"
  local skip="${3:-}"

  [[ -d "$src_dir" ]] || return 0

  while IFS= read -r -d '' src_file; do
    local rel="${src_file#"$src_dir"/}"
    if [[ -n "$skip" && "$rel" == "$skip"* ]]; then
      continue
    fi
    update_file "$src_file" "$dst_dir/$rel" "$rel"
  done < <(find "$src_dir" -type f -print0 | sort -z)
}

# ─────────────────────────────────────────────────────────────────────────────

header "CLEAR Update"
echo "  Source : $CLEAR_ROOT"
echo "  Target : $TARGET_DIR"
[[ "$DRY_RUN" == true ]] && warn "Dry-run mode — no files will be written."

# ── 1. Agent configs
# Overwrite CLEAR-owned files; skip user-owned paths:
#   .github/prompts/     — user-installed skills (handled separately below)
#   .gitignore            — user-customized
header "Agent configurations..."
update_dir "$CLEAR_ROOT/templates/agent-configs/.github"  "$TARGET_DIR/.github"  "prompts"
update_dir "$CLEAR_ROOT/templates/agent-configs/.cursor"  "$TARGET_DIR/.cursor"
update_dir "$CLEAR_ROOT/templates/agent-configs/.claude"  "$TARGET_DIR/.claude"
update_dir "$CLEAR_ROOT/templates/agent-configs/.vscode"  "$TARGET_DIR/.vscode"
update_file \
  "$CLEAR_ROOT/templates/agent-configs/CLAUDE.md" \
  "$TARGET_DIR/CLAUDE.md"
update_file \
  "$CLEAR_ROOT/templates/agent-configs/.cursorrules" \
  "$TARGET_DIR/.cursorrules"

# ── 2. CLEAR-managed scripts (not user-customized)
header "CLEAR scripts..."
update_file "$CLEAR_ROOT/scripts/setup-clear.sh"       "$TARGET_DIR/scripts/setup-clear.sh"
update_file "$CLEAR_ROOT/scripts/bootstrap-project.sh" "$TARGET_DIR/scripts/bootstrap-project.sh"
update_file "$CLEAR_ROOT/scripts/update-project.sh"    "$TARGET_DIR/scripts/update-project.sh"

# ── 3. verify-ci.sh — skip by default (user adds their project's checks here)
if [[ "$UPDATE_SCRIPTS" == true ]]; then
  header "Scripts (--update-scripts)..."
  warn "Overwriting scripts/verify-ci.sh — re-add your project-specific checks after."
  update_file "$CLEAR_ROOT/scripts/verify-ci.sh" "$TARGET_DIR/scripts/verify-ci.sh"
else
  warn "Skipping scripts/verify-ci.sh (you may have added custom checks)."
  info "Use --update-scripts to overwrite it."
  SKIPPED+=("scripts/verify-ci.sh")
fi

# ── 4. Skills — update only previously-installed ones
#    A skill is "installed" if .github/prompts/<name>.prompt.md exists
#    AND templates/skills/<name>.md exists in CLEAR.
header "Skills..."
SKILLS_FOUND=0
if [[ -d "$TARGET_DIR/.github/prompts" ]]; then
  while IFS= read -r prompt_file; do
    skill_name="$(basename "$prompt_file" .prompt.md)"
    src_skill="$CLEAR_ROOT/templates/skills/${skill_name}.md"
    if [[ -f "$src_skill" ]]; then
      ((SKILLS_FOUND++)) || true
      update_file "$src_skill" "$prompt_file" ".github/prompts/${skill_name}.prompt.md"
    fi
  done < <(find "$TARGET_DIR/.github/prompts" -name "*.prompt.md" -type f | sort)

  if [[ $SKILLS_FOUND -eq 0 ]]; then
    info "No CLEAR-sourced skills installed — nothing to update."
    info "Install skills with: $CLEAR_ROOT/scripts/setup-clear.sh $TARGET_DIR"
  fi
else
  info "No .github/prompts/ directory — no skills to update."
  info "Install skills with: $CLEAR_ROOT/scripts/setup-clear.sh $TARGET_DIR"
fi

# ── Make scripts executable
if [[ "$DRY_RUN" == false && -d "$TARGET_DIR/scripts" ]]; then
  chmod +x "$TARGET_DIR/scripts/"*.sh 2>/dev/null || true
fi

# ── Summary
echo ""
header "Summary"
echo "  Updated : ${#UPDATED[@]} file(s)"
echo "  Current : ${#CURRENT[@]} file(s) already at latest"
echo "  Skipped : ${#SKIPPED[@]} file(s)"

if [[ "$DRY_RUN" == true ]]; then
  echo ""
  info "Dry run complete. Re-run without --dry-run to apply."
elif [[ ${#UPDATED[@]} -gt 0 ]]; then
  echo ""
  success "Update complete: $(basename "$TARGET_DIR")"
  info "Run 'git diff' in your project to review changes."
  info "Then run ./scripts/verify-ci.sh to confirm everything still passes."
else
  echo ""
  success "Already up to date: $(basename "$TARGET_DIR")"
fi
