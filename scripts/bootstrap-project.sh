#!/usr/bin/env bash
# bootstrap-project.sh — Copy CLEAR framework files into an existing project
#
# Usage:
#   ./scripts/bootstrap-project.sh /path/to/your-project
#   ./scripts/bootstrap-project.sh --dry-run /path/to/your-project
#   ./scripts/bootstrap-project.sh --update /path/to/your-project
#   ./scripts/bootstrap-project.sh --no-templates /path/to/your-project
#   ./scripts/bootstrap-project.sh --no-setup /path/to/your-project
#   ./scripts/bootstrap-project.sh --with-examples /path/to/your-project
#   ./scripts/bootstrap-project.sh --enable-extension lizard /path/to/your-project
#   ./scripts/bootstrap-project.sh --enable-extension file-size /path/to/your-project

set -euo pipefail

# ── Resolve the CLEAR seed repo root (the directory containing this script's parent)
CLEAR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Colours
supports_color() {
  [[ -z "${NO_COLOR:-}" ]] || return 1
  [[ "${TERM:-}" != "dumb" ]] || return 1

  if [[ -n "${FORCE_COLOR:-}" || -n "${CLICOLOR_FORCE:-}" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
    return 0
  fi

  [[ -t 1 ]] || return 1

  if command -v tput >/dev/null 2>&1; then
    local colors
    colors="$(tput colors 2>/dev/null || printf '0')"
    [[ "$colors" =~ ^[0-9]+$ ]] || return 1
    ((colors >= 8)) || return 1
  fi

  return 0
}

if supports_color; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  CYAN=''
  BOLD=''
  RESET=''
fi

info() { echo -e "${CYAN}ℹ ${RESET}$*"; }
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
UPDATE_MODE=false
INCLUDE_TEMPLATES=true
INCLUDE_EXAMPLES=false
RUN_SETUP=true
SETUP_EXTENSIONS=false
SELF_SYNC=false
TARGET_DIR=""
ENABLE_EXTENSIONS=()

# ── Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --update)
      UPDATE_MODE=true
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
    --with-examples)
      INCLUDE_EXAMPLES=true
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
      echo "Usage: $(basename "$0") [OPTIONS] /path/to/your-project"
      echo ""
      echo "Options:"
      echo "  --dry-run                    Show what would be copied without doing it"
      echo "  --update                     Update an already-bootstrapped project"
      echo "  --no-templates               Skip copying the templates/ directory"
      echo "  --no-setup                   Skip running setup-clear.sh after copying"
      echo "  --with-examples              Include example skill files (domain-specific illustrations)"
      echo "  --enable-extension <name>    Enable an extension (e.g., lizard, file-size)"
      echo "                               Can be specified multiple times"
      echo "  --setup-extensions           Interactive extension setup (update mode)"
      echo "  --self-sync                  Allow self-sync when targeting CLEAR seed repo (update mode)"
      echo "  --help                       Show this help"
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

# ── Guard: target CLEAR repo only in explicit self-sync update mode
if [[ "$TARGET_DIR" == "$CLEAR_ROOT" ]]; then
  if [[ "$UPDATE_MODE" == true && "$SELF_SYNC" == true ]]; then
    warn "Self-sync mode enabled: syncing template-managed files into CLEAR seed repo."
  else
    error "Target directory is the CLEAR seed repo itself."
    echo "  Use --update --self-sync only if you intentionally want to sync template-managed files."
    exit 1
  fi
fi

IS_BOOTSTRAPPED=false
if [[ -f "$TARGET_DIR/clear/autonomy.yml" ]]; then
  IS_BOOTSTRAPPED=true
fi

if [[ "$UPDATE_MODE" == false && "$IS_BOOTSTRAPPED" == true ]]; then
  error "Target already appears bootstrapped: $TARGET_DIR"
  echo "  Run with --update to sync to the latest CLEAR files."
  echo "  Example: $(basename "$0") --update $TARGET_DIR"
  exit 1
fi

if [[ "$UPDATE_MODE" == true && "$IS_BOOTSTRAPPED" == false ]]; then
  error "Target is not bootstrapped yet: $TARGET_DIR"
  echo "  Run without --update for first-time install."
  echo "  Example: $(basename "$0") $TARGET_DIR"
  exit 1
fi

if [[ "$UPDATE_MODE" == true ]]; then
  if [[ "$INCLUDE_TEMPLATES" == false || "$INCLUDE_EXAMPLES" == true || "$RUN_SETUP" == false ]]; then
    error "--no-templates, --with-examples, and --no-setup are bootstrap-only options."
    echo "  Remove bootstrap-only flags when using --update."
    exit 1
  fi

  # ── Tracking for update mode
  UPDATED=()
  CURRENT=()
  SKIPPED_UPDATE=()

  # update_file <src> <dst> [display-label]
  update_file() {
    local src="$1"
    local dst="$2"
    local label="${3:-${dst#"$TARGET_DIR"/}}"

    if [[ ! -f "$src" ]]; then
      warn "Source not found, skipping: $label"
      SKIPPED_UPDATE+=("$label")
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

  # update_dir <src_dir> <dst_dir> [skip_subpath]
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

  header "CLEAR Update"
  echo "  Source : $CLEAR_ROOT"
  echo "  Target : $TARGET_DIR"
  [[ "$DRY_RUN" == true ]] && warn "Dry-run mode — no files will be written."

  # 1) Agent configs (excluding .github/prompts and .gitignore)
  header "Agent configurations..."
  update_dir "$CLEAR_ROOT/templates/agent-configs/.github" "$TARGET_DIR/.github" "prompts"
  update_dir "$CLEAR_ROOT/templates/agent-configs/.cursor" "$TARGET_DIR/.cursor"
  update_dir "$CLEAR_ROOT/templates/agent-configs/.claude" "$TARGET_DIR/.claude"
  update_dir "$CLEAR_ROOT/templates/agent-configs/.vscode" "$TARGET_DIR/.vscode"
  update_file "$CLEAR_ROOT/templates/agent-configs/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"
  update_file "$CLEAR_ROOT/templates/agent-configs/.cursorrules" "$TARGET_DIR/.cursorrules"

  # 2) CLEAR-managed scripts
  header "CLEAR scripts..."
  update_file "$CLEAR_ROOT/scripts/verify-ci.sh" "$TARGET_DIR/scripts/verify-ci.sh"
  update_file "$CLEAR_ROOT/scripts/setup-clear.sh" "$TARGET_DIR/scripts/setup-clear.sh"
  update_file "$CLEAR_ROOT/scripts/bootstrap-project.sh" "$TARGET_DIR/scripts/bootstrap-project.sh"

  # 3) verify-local.sh create-if-missing (project-owned)
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

  # 4) extensions.yml create-if-missing (project-owned)
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

  # 5) Installed skills in .github/prompts
  header "Skills..."
  SKILLS_FOUND=0
  if [[ -d "$TARGET_DIR/.github/prompts" ]]; then
    while IFS= read -r prompt_file; do
      skill_name="$(basename "$prompt_file" .prompt.md)"
      src_skill=""
      if [[ -f "$CLEAR_ROOT/templates/skills/${skill_name}.md" ]]; then
        src_skill="$CLEAR_ROOT/templates/skills/${skill_name}.md"
      elif [[ -f "$CLEAR_ROOT/templates/examples/skills/${skill_name}.md" ]]; then
        src_skill="$CLEAR_ROOT/templates/examples/skills/${skill_name}.md"
      fi
      if [[ -n "$src_skill" ]]; then
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

  # 6) Enable requested extensions
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

  # 7) Interactive extension setup
  if [[ "$SETUP_EXTENSIONS" == true && "$DRY_RUN" == false ]]; then
    header "Extension Setup"

    EXT_FILE="$TARGET_DIR/clear/extensions.yml"
    if [[ ! -f "$EXT_FILE" ]]; then
      warn "No clear/extensions.yml found — skipping extension setup"
    else
      echo "Available extensions in $TARGET_DIR:"
      echo ""

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

  if [[ "$DRY_RUN" == false && -d "$TARGET_DIR/scripts" ]]; then
    chmod +x "$TARGET_DIR/scripts/"*.sh 2>/dev/null || true
  fi

  echo ""
  header "Summary"
  echo "  Updated : ${#UPDATED[@]} file(s)"
  echo "  Current : ${#CURRENT[@]} file(s) already at latest"
  echo "  Skipped : ${#SKIPPED_UPDATE[@]} file(s)"

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
  exit 0
fi

if [[ "$UPDATE_MODE" == false && ("$SETUP_EXTENSIONS" == true || "$SELF_SYNC" == true) ]]; then
  error "--setup-extensions and --self-sync require --update mode."
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

# Project-owned files: copy only if they don't exist yet (never overwritten).
# verify-ci.sh is CLEAR-owned: always copied via the scripts/ dir above.
declare -a COPY_IF_MISSING=(
  "templates/agent-configs/scripts/verify-local.sh  scripts/verify-local.sh"
  "clear/extensions.yml                             clear/extensions.yml"
)

if [[ "$INCLUDE_TEMPLATES" == true ]]; then
  COPY_ITEMS+=("templates      templates      dir")
fi

# ── Print plan
header "CLEAR Bootstrap"
echo "  Source : $CLEAR_ROOT"
echo "  Target : $TARGET_DIR"
[[ "$DRY_RUN" == true ]] && warn "Dry-run mode — no files will be written."
[[ "$INCLUDE_TEMPLATES" == false ]] && warn "Skipping templates/ directory."
[[ "$INCLUDE_EXAMPLES" == true ]] && info "Including example skill files."
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
        cp -r "$src/." "$dst/" --update=none 2>/dev/null || cp -rn "$src/." "$dst/" 2>/dev/null # no-overwrite
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
  read -r src_rel dst_rel kind <<<"$item"
  copy_item "$src_rel" "$dst_rel" "$kind"
done

# ── Copy project-owned files only if they don't exist yet
for item in "${COPY_IF_MISSING[@]}"; do
  read -r src_rel dst_rel <<<"$item"
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

# ── Remove examples if --with-examples was not specified
if [[ "$INCLUDE_TEMPLATES" == true && "$INCLUDE_EXAMPLES" == false ]]; then
  if [[ -d "$TARGET_DIR/templates/examples" ]]; then
    if [[ "$DRY_RUN" == false ]]; then
      rm -rf "$TARGET_DIR/templates/examples"
      info "Skipped examples (use --with-examples to include)"
    else
      info "Would skip examples (use --with-examples to include)"
    fi
  fi
fi

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

# ── Enable requested extensions
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
