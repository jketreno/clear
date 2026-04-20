#!/usr/bin/env bash
# =============================================================================
# CLEAR update-project.sh — Bring a bootstrapped project to the latest CLEAR
# =============================================================================
# Updates agent configs, CLEAR scripts (including verify-ci.sh), and
# previously-installed skills.
#
# verify-ci.sh is CLEAR-owned and always updated safely — your project-specific
# checks live in scripts/verify-local.sh, which is never overwritten.
#
# Usage:
#   ./scripts/update-project.sh [OPTIONS] [/path/to/your-project]
#   ./scripts/update-project.sh             (updates current directory)
#   ./scripts/update-project.sh --dry-run
#   ./scripts/update-project.sh --enable-extension lizard
#   ./scripts/update-project.sh --setup-extensions
#   ./scripts/update-project.sh --self-sync ./
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

info() { echo -e "${CYAN}ℹ  ${RESET}$*"; }
success() { echo -e "${GREEN}✅ ${RESET}$*"; }
warn() { echo -e "${YELLOW}⚠  ${RESET}$*"; }
error() { echo -e "${RED}❌ ${RESET}$*" >&2; }
header() { echo -e "\n${BOLD}$*${RESET}"; }

# ── Enable an extension in a target project's extensions.yml
# Usage: enable_extension <target_dir> <extension_name>
enable_extension() {
  local target="$1"
  local ext_name="$2"
  local ext_file="$target/clear/extensions.yml"

  if [[ ! -f "$ext_file" ]]; then
    warn "Cannot enable '$ext_name': clear/extensions.yml not found in $target"
    return 1
  fi

  # Check if the extension exists in the file
  if ! grep -q "name:[[:space:]]*${ext_name}" "$ext_file"; then
    error "Unknown extension: '$ext_name'"
    echo "  Available extensions:"
    grep 'name:' "$ext_file" | sed 's/.*name:[[:space:]]*/    /' | sed 's/"//g'
    return 1
  fi

  # Check if already enabled
  local already_enabled
  already_enabled=$(awk -v name="$ext_name" '
    /name:/ && index($0, name) { found=1; next }
    found && /enabled:/ { print $2; exit }
  ' "$ext_file")

  if [[ "$already_enabled" == "true" ]]; then
    info "Extension '$ext_name' is already enabled"
    return 0
  fi

  # Enable it
  sed -i "/name:[[:space:]]*${ext_name}/,/enabled:/{s/enabled:[[:space:]]*false/enabled: true/}" "$ext_file"
  success "Enabled extension: $ext_name"
}

# ── Defaults
DRY_RUN=false
TARGET_DIR=""
ENABLE_EXTENSIONS=()
SETUP_EXTENSIONS=false
SELF_SYNC=false

# ── Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --enable-extension)
      if [[ -z "${2:-}" ]]; then
        error "--enable-extension requires an extension name (e.g., lizard, file-size)"
        exit 1
      fi
      ENABLE_EXTENSIONS+=("$2")
      shift 2
      ;;
    --setup-extensions)
      SETUP_EXTENSIONS=true
      shift
      ;;
    --self-sync)
      SELF_SYNC=true
      shift
      ;;
    --help | -h)
      echo "Usage: $(basename "$0") [OPTIONS] [/path/to/your-project]"
      echo ""
      echo "Updates a CLEAR-bootstrapped project to the latest framework templates."
      echo "Run this from the CLEAR repo when you pull a new version of CLEAR."
      echo ""
      echo "Options:"
      echo "  --dry-run                    Show what would change without writing any files"
      echo "  --enable-extension <name>    Enable an extension (e.g., lizard, file-size)"
      echo "                               Can be specified multiple times"
      echo "  --setup-extensions           Run the interactive extension setup wizard"
      echo "  --self-sync                  Allow updating this CLEAR seed repo from templates"
      echo "  --help                       Show this help"
      echo ""
      echo "What gets updated:"
      echo "  • Agent configs    .github/ (not .github/prompts/), .cursor/, .claude/,"
      echo "                     .vscode/, CLAUDE.md, .cursorrules"
      echo "  • CLEAR scripts    scripts/verify-ci.sh, setup-clear.sh,"
      echo "                     bootstrap-project.sh, update-project.sh (self)"
      echo "  • Installed skills .github/prompts/<name>.prompt.md for each skill"
      echo "                     that was previously installed from CLEAR"
      echo ""
      echo "What is never touched:"
      echo "  • clear/autonomy.yml      — your project-specific configuration"
      echo "  • clear/extensions.yml    — your project-specific extension settings"
      echo "  • scripts/verify-local.sh — your project-specific CI checks"
      echo "  • .gitignore              — your project-specific ignores"
      echo ""
      echo "Seed-repo mode:"
      echo "  By default, the script refuses to target the CLEAR seed repo itself."
      echo "  Use --self-sync to intentionally sync template-managed files into CLEAR."
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
  if [[ "$SELF_SYNC" == false ]]; then
    error "Target is the CLEAR seed repo itself."
    echo "  Use 'git pull' inside $CLEAR_ROOT to update CLEAR code."
    echo "  Use --self-sync if you intentionally want to sync template-installed files into CLEAR."
    exit 1
  fi
  warn "Self-sync mode enabled: syncing template-installed files into CLEAR seed repo."
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

  if [[ -f "$dst" ]] && diff -q "$src" "$dst" >/dev/null 2>&1; then
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
update_dir "$CLEAR_ROOT/templates/agent-configs/.github" "$TARGET_DIR/.github" "prompts"
update_dir "$CLEAR_ROOT/templates/agent-configs/.cursor" "$TARGET_DIR/.cursor"
update_dir "$CLEAR_ROOT/templates/agent-configs/.claude" "$TARGET_DIR/.claude"
update_dir "$CLEAR_ROOT/templates/agent-configs/.vscode" "$TARGET_DIR/.vscode"
update_file \
  "$CLEAR_ROOT/templates/agent-configs/CLAUDE.md" \
  "$TARGET_DIR/CLAUDE.md"
update_file \
  "$CLEAR_ROOT/templates/agent-configs/.cursorrules" \
  "$TARGET_DIR/.cursorrules"

# ── 2. CLEAR-managed scripts (always updated)
header "CLEAR scripts..."
update_file "$CLEAR_ROOT/scripts/verify-ci.sh" "$TARGET_DIR/scripts/verify-ci.sh"
update_file "$CLEAR_ROOT/scripts/setup-clear.sh" "$TARGET_DIR/scripts/setup-clear.sh"
update_file "$CLEAR_ROOT/scripts/bootstrap-project.sh" "$TARGET_DIR/scripts/bootstrap-project.sh"
update_file "$CLEAR_ROOT/scripts/update-project.sh" "$TARGET_DIR/scripts/update-project.sh"

# ── 3. verify-local.sh — create only if missing (project-owned)
if [[ ! -f "$TARGET_DIR/scripts/verify-local.sh" ]]; then
  local_src="$CLEAR_ROOT/templates/agent-configs/scripts/verify-local.sh"
  if [[ -f "$local_src" ]]; then
    if [[ "$DRY_RUN" == false ]]; then
      cp "$local_src" "$TARGET_DIR/scripts/verify-local.sh"
      chmod +x "$TARGET_DIR/scripts/verify-local.sh"
      echo -e "  ${GREEN}Created ${RESET}: scripts/verify-local.sh (project-owned — add your checks here)"
    else
      echo -e "  ${CYAN}Would create${RESET}: scripts/verify-local.sh"
    fi
    UPDATED+=("scripts/verify-local.sh")
  fi
else
  echo -e "  ${CYAN}Kept    ${RESET}: scripts/verify-local.sh (project-owned)"
  CURRENT+=("scripts/verify-local.sh")
fi

# ── 4. extensions.yml — create only if missing (project-owned)
if [[ ! -f "$TARGET_DIR/clear/extensions.yml" ]]; then
  local_src="$CLEAR_ROOT/clear/extensions.yml"
  if [[ -f "$local_src" ]]; then
    if [[ "$DRY_RUN" == false ]]; then
      mkdir -p "$TARGET_DIR/clear"
      cp "$local_src" "$TARGET_DIR/clear/extensions.yml"
      echo -e "  ${GREEN}Created ${RESET}: clear/extensions.yml (project-owned — configure your extensions here)"
    else
      echo -e "  ${CYAN}Would create${RESET}: clear/extensions.yml"
    fi
    UPDATED+=("clear/extensions.yml")
  fi
else
  echo -e "  ${CYAN}Kept    ${RESET}: clear/extensions.yml (project-owned)"
  CURRENT+=("clear/extensions.yml")
fi

# ── 5. Skills — update only previously-installed ones
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

# ── 6. Enable requested extensions (--enable-extension)
if [[ ${#ENABLE_EXTENSIONS[@]} -gt 0 && "$DRY_RUN" == false ]]; then
  header "Enabling extensions..."
  for ext_name in "${ENABLE_EXTENSIONS[@]}"; do
    enable_extension "$TARGET_DIR" "$ext_name"
  done
elif [[ ${#ENABLE_EXTENSIONS[@]} -gt 0 && "$DRY_RUN" == true ]]; then
  header "Extensions (dry-run)"
  for ext_name in "${ENABLE_EXTENSIONS[@]}"; do
    echo -e "  ${CYAN}Would enable${RESET}: $ext_name"
  done
fi

# ── 7. Interactive extension setup (--setup-extensions)
if [[ "$SETUP_EXTENSIONS" == true && "$DRY_RUN" == false ]]; then
  header "Extension Setup"

  EXT_FILE="$TARGET_DIR/clear/extensions.yml"
  if [[ ! -f "$EXT_FILE" ]]; then
    warn "No clear/extensions.yml found — skipping extension setup"
  else
    echo "Available extensions in $TARGET_DIR:"
    echo ""

    # Parse extensions from the target project's extensions.yml
    SE_NAMES=()
    SE_DESCS=()
    SE_HINTS=()
    SE_STATES=()
    se_name="" se_desc="" se_hint="" se_state=""

    while IFS= read -r line; do
      if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.*) ]]; then
        if [[ -n "$se_name" ]]; then
          SE_NAMES+=("$se_name")
          SE_DESCS+=("$se_desc")
          SE_HINTS+=("$se_hint")
          SE_STATES+=("$se_state")
        fi
        se_name="${BASH_REMATCH[1]}"
        se_name="${se_name#\"}"
        se_name="${se_name%\"}"
        se_desc=""
        se_hint=""
        se_state=""
      elif [[ "$line" =~ ^[[:space:]]*description:[[:space:]]*(.*) ]]; then
        se_desc="${BASH_REMATCH[1]}"
        se_desc="${se_desc#\"}"
        se_desc="${se_desc%\"}"
      elif [[ "$line" =~ ^[[:space:]]*install_hint:[[:space:]]*(.*) ]]; then
        se_hint="${BASH_REMATCH[1]}"
        se_hint="${se_hint#\"}"
        se_hint="${se_hint%\"}"
      elif [[ "$line" =~ ^[[:space:]]*enabled:[[:space:]]*(.*) ]]; then
        se_state="${BASH_REMATCH[1]}"
      fi
    done <"$EXT_FILE"
    if [[ -n "$se_name" ]]; then
      SE_NAMES+=("$se_name")
      SE_DESCS+=("$se_desc")
      SE_HINTS+=("$se_hint")
      SE_STATES+=("$se_state")
    fi

    for _i in "${!SE_NAMES[@]}"; do
      local_status="disabled"
      [[ "${SE_STATES[$_i]}" == "true" ]] && local_status="ENABLED"
      printf "  %d. %-12s — %s [%s]\n" "$((_i + 1))" "${SE_NAMES[$_i]}" "${SE_DESCS[$_i]}" "$local_status"
      printf "     Install: %s\n" "${SE_HINTS[$_i]}"
      echo ""
    done

    printf "${CYAN}  Enter numbers to enable (space-separated), 'all', or press ENTER to skip: ${RESET}" >/dev/tty
    read -r SE_SELECTION </dev/tty
    echo ""

    if [[ -n "$SE_SELECTION" ]]; then
      SE_TO_ENABLE=()
      if [[ "$SE_SELECTION" == "all" ]]; then
        for _i in "${!SE_NAMES[@]}"; do
          SE_TO_ENABLE+=("${SE_NAMES[$_i]}")
        done
      else
        for _token in $SE_SELECTION; do
          if [[ "$_token" =~ ^[0-9]+$ ]]; then
            _idx=$((_token - 1))
            if [[ $_idx -ge 0 && $_idx -lt ${#SE_NAMES[@]} ]]; then
              SE_TO_ENABLE+=("${SE_NAMES[$_idx]}")
            else
              warn "No extension at position $_token — skipped"
            fi
          fi
        done
      fi

      for _ext in "${SE_TO_ENABLE[@]}"; do
        enable_extension "$TARGET_DIR" "$_ext"
      done
    else
      info "No changes — extensions unchanged"
    fi
  fi
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
