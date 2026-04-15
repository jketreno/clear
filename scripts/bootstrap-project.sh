#!/usr/bin/env bash
# bootstrap-project.sh — Copy CLEAR framework files into an existing project
#
# Usage:
#   ./scripts/bootstrap-project.sh /path/to/your-project
#   ./scripts/bootstrap-project.sh --dry-run /path/to/your-project
#   ./scripts/bootstrap-project.sh --no-templates /path/to/your-project
#   ./scripts/bootstrap-project.sh --no-setup /path/to/your-project

set -euo pipefail

# ── Resolve the CLEAR seed repo root (the directory containing this script's parent)
CLEAR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}ℹ ${RESET}$*"; }
success() { echo -e "${GREEN}✅ ${RESET}$*"; }
warn()    { echo -e "${YELLOW}⚠  ${RESET}$*"; }
error()   { echo -e "${RED}❌ ${RESET}$*" >&2; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

# ── Defaults
DRY_RUN=false
INCLUDE_TEMPLATES=true
RUN_SETUP=true
TARGET_DIR=""

# ── Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --no-templates)
      INCLUDE_TEMPLATES=false
      shift
      ;;
    --no-setup)
      RUN_SETUP=false
      shift
      ;;
    --help|-h)
      echo "Usage: $(basename "$0") [OPTIONS] /path/to/your-project"
      echo ""
      echo "Options:"
      echo "  --dry-run        Show what would be copied without doing it"
      echo "  --no-templates   Skip copying the templates/ directory (architecture tests, skills, linting)"
      echo "  --no-setup       Skip running setup-clear.sh after copying"
      echo "  --help           Show this help"
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

# ── Require a target directory
if [[ -z "$TARGET_DIR" ]]; then
  error "No target project directory specified."
  echo "  Usage: $(basename "$0") [OPTIONS] /path/to/your-project"
  echo "  Run $(basename "$0") --help for full usage."
  exit 1
fi

# ── Resolve to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
  error "Target directory does not exist: $TARGET_DIR"
  exit 1
}

# ── Guard: don't bootstrap into the CLEAR repo itself
if [[ "$TARGET_DIR" == "$CLEAR_ROOT" ]]; then
  error "Target directory is the CLEAR seed repo itself. Choose a different project."
  exit 1
fi

# ── Define what gets copied: (source_relative_path destination_relative_path is_directory)
#
# Agent configs live under templates/agent-configs/ so they are distinct from
# the configs the CLEAR project itself uses when developing this seed repo.
declare -a COPY_ITEMS=(
  "scripts                          scripts        dir"
  "clear                            clear          dir"
  "templates/agent-configs/.github  .github        dir"
  "templates/agent-configs/.cursor  .cursor        dir"
  "templates/agent-configs/.claude  .claude        dir"
  "templates/agent-configs/.vscode  .vscode        dir"
  "templates/agent-configs/CLAUDE.md      CLAUDE.md      file"
  "templates/agent-configs/.cursorrules   .cursorrules   file"
  "templates/agent-configs/.gitignore     .gitignore     file"
)

# verify-local.sh is project-owned: copy only if it doesn't exist yet.
# verify-ci.sh is CLEAR-owned: always copied via the scripts/ dir above.
declare -a COPY_IF_MISSING=(
  "templates/agent-configs/scripts/verify-local.sh  scripts/verify-local.sh"
)

if [[ "$INCLUDE_TEMPLATES" == true ]]; then
  COPY_ITEMS+=("templates      templates      dir")
fi

# ── Print plan
header "CLEAR Bootstrap"
echo "  Source : $CLEAR_ROOT"
echo "  Target : $TARGET_DIR"
[[ "$DRY_RUN"  == true ]] && warn "Dry-run mode — no files will be written."
[[ "$INCLUDE_TEMPLATES" == false ]] && warn "Skipping templates/ directory."
echo ""

# ── Track results
COPIED=()
SKIPPED=()
CONFLICTS=()

copy_item() {
  local src_rel="$1"
  local dst_rel="$2"
  local kind="$3"

  local src="$CLEAR_ROOT/$src_rel"
  local dst="$TARGET_DIR/$dst_rel"

  # Source must exist
  if [[ ! -e "$src" ]]; then
    warn "Source not found, skipping: $src_rel"
    SKIPPED+=("$src_rel")
    return
  fi

  if [[ -e "$dst" ]]; then
    # Destination exists — offer to merge/skip
    if [[ "$kind" == "dir" ]]; then
      if [[ "$DRY_RUN" == false ]]; then
        echo -e "  ${YELLOW}Exists${RESET}: $dst_rel/ — merging (existing files preserved)"
        cp -r "$src/." "$dst/" --update=none 2>/dev/null || cp -rn "$src/." "$dst/" 2>/dev/null   # no-overwrite
      else
        echo -e "  ${YELLOW}Would merge${RESET}: $dst_rel/ (existing files preserved)"
      fi
      CONFLICTS+=("$dst_rel/")
    else
      echo -e "  ${YELLOW}Exists${RESET}: $dst_rel — skipping (keep your version)"
      SKIPPED+=("$dst_rel")
    fi
    return
  fi

  # Destination does not exist — copy freely
  if [[ "$DRY_RUN" == false ]]; then
    if [[ "$kind" == "dir" ]]; then
      cp -r "$src" "$dst"
    else
      cp "$src" "$dst"
    fi
    echo -e "  ${GREEN}Copied${RESET} : $dst_rel"
  else
    echo -e "  ${CYAN}Would copy${RESET}: $dst_rel"
  fi
  COPIED+=("$dst_rel")
}

header "Copying files..."
for item in "${COPY_ITEMS[@]}"; do
  read -r src_rel dst_rel kind <<< "$item"
  copy_item "$src_rel" "$dst_rel" "$kind"
done

# ── Copy project-owned files only if they don't exist yet
for item in "${COPY_IF_MISSING[@]}"; do
  read -r src_rel dst_rel <<< "$item"
  local_src="$CLEAR_ROOT/$src_rel"
  local_dst="$TARGET_DIR/$dst_rel"
  if [[ -e "$local_dst" ]]; then
    echo -e "  ${YELLOW}Exists${RESET}: $dst_rel — keeping your version"
    SKIPPED+=("$dst_rel")
  elif [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$(dirname "$local_dst")"
    cp "$local_src" "$local_dst"
    echo -e "  ${GREEN}Copied${RESET} : $dst_rel (project-owned — CLEAR will not overwrite)"
    COPIED+=("$dst_rel")
  else
    echo -e "  ${CYAN}Would copy${RESET}: $dst_rel (project-owned — CLEAR will not overwrite)"
    COPIED+=("$dst_rel")
  fi
done

# ── Make scripts executable
if [[ "$DRY_RUN" == false ]]; then
  if [[ -d "$TARGET_DIR/scripts" ]]; then
    chmod +x "$TARGET_DIR/scripts/"*.sh 2>/dev/null || true
    echo -e "  ${GREEN}chmod +x${RESET}: scripts/*.sh"
  fi
fi

# ── Summary
echo ""
header "Summary"
echo "  Copied   : ${#COPIED[@]} item(s)"
echo "  Skipped  : ${#SKIPPED[@]} item(s) (already exist, your version kept)"
echo "  Merged   : ${#CONFLICTS[@]} director(ies) (new files added, existing preserved)"

if [[ "${#CONFLICTS[@]}" -gt 0 ]]; then
  echo ""
  warn "Merged directories — review for conflicts:"
  for c in "${CONFLICTS[@]}"; do
    echo "    $c"
  done
fi

# ── Optionally run setup wizard
if [[ "$DRY_RUN" == true ]]; then
  echo ""
  info "Dry run complete. Re-run without --dry-run to apply."
  exit 0
fi

echo ""
if [[ "$RUN_SETUP" == true ]]; then
  header "Running setup wizard..."
  echo "  This will configure clear/autonomy.yml for your project."
  echo "  (Press Ctrl-C to skip and run it later with: ./scripts/setup-clear.sh)"
  echo ""
  # Run CLEAR's own setup-clear.sh (not the target's potentially stale copy)
  # and pass the target directory so it configures the right project.
  bash "$CLEAR_ROOT/scripts/setup-clear.sh" "$TARGET_DIR"
else
  success "Files copied. Run the setup wizard when ready:"
  echo "  cd $TARGET_DIR && ./scripts/setup-clear.sh"
fi
