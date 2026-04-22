#!/usr/bin/env bash
# =============================================================================
# clear-installer.sh — Unified CLEAR installer (source-tree + self-extracting)
# =============================================================================
# Source-tree mode:
#   ./scripts/clear-installer.sh --target /path/to/project
#
# Self-extracting mode:
#   ./clear-installer-vX.Y.Z.sh --target /path/to/project
#
# Extra modes:
#   --extract <path>            Extract full payload only (self-extracting mode)
#   --install-examples <path>   Extract templates/examples only
# =============================================================================

set -euo pipefail

EXIT_USAGE=2
EXIT_PREFLIGHT=3
EXIT_RUNTIME=4
EXIT_EXTRACT=5

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

TARGET_DIR=""
DRY_RUN=false
FORCE=false
YES=false
EXTRACT_PATH=""
INSTALL_EXAMPLES_PATH=""
RUN_SETUP=true
SETUP_ONLY=false
WORK_DIR=""

error() { echo "ERR  $*" >&2; }
info() { echo "INFO $*"; }

usage() {
  cat <<'USAGE'
Usage:
  clear-installer.sh [--target <path>] [--dry-run] [--force] [--yes] [--no-setup]
  clear-installer.sh --install-examples <path> [--force]
  clear-installer.sh --extract <path> [--force]
  clear-installer.sh [--dry-run] /path/to/project

Options:
  --target <path>   Target repository path
  --dry-run         Show what would happen without modifying target files
  --force           Allow overwrite for --extract/--install-examples collisions
  --yes             Auto-confirm prompts
  --no-setup        Skip running setup wizard after install/update
  --setup-only      Run setup flow only (internal use)
  --install-examples <path>
                    Extract templates/examples to <path> and exit
  --extract <path>  Extract full embedded payload only, do not install/update
  --help            Show this help
USAGE
}

cleanup() {
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
}

has_embedded_payload() {
  awk '/^__CLEAR_PAYLOAD_BELOW__$/ { found=1; exit } END { exit(found ? 0 : 1) }' "$SCRIPT_PATH"
}

extract_payload() {
  local destination="$1"
  local marker_line

  marker_line="$(awk '/^__CLEAR_PAYLOAD_BELOW__$/ { print NR + 1; exit }' "$SCRIPT_PATH")"
  [[ -n "$marker_line" ]] || {
    error "Installer payload marker not found"
    return 1
  }

  mkdir -p "$destination"
  tail -n "+$marker_line" "$SCRIPT_PATH" | tar -xzf - -C "$destination"
}

copy_file_update() {
  local src="$1"
  local dst="$2"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

copy_file_if_missing() {
  local src="$1"
  local dst="$2"
  if [[ ! -e "$dst" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
  fi
}

copy_dir_update() {
  local src_dir="$1"
  local dst_dir="$2"
  local skip_prefix="${3:-}"

  [[ -d "$src_dir" ]] || return 0

  while IFS= read -r -d '' src_file; do
    local rel
    rel="${src_file#"$src_dir"/}"
    if [[ -n "$skip_prefix" && "$rel" == "$skip_prefix"* ]]; then
      continue
    fi

    local dst_file
    dst_file="$dst_dir/$rel"
    mkdir -p "$(dirname "$dst_file")"
    cp "$src_file" "$dst_file"
  done < <(find "$src_dir" -type f -print0 | sort -z)
}

ask() {
  local question="$1"
  local default="${2:-}"
  local answer

  if [[ "$YES" == "true" ]]; then
    echo "$default"
    return 0
  fi

  if [[ -n "$default" ]]; then
    printf "?  %s [%s]: " "$question" "$default" >&2
  else
    printf "?  %s: " "$question" >&2
  fi
  read -r answer
  echo "${answer:-$default}"
}

sync_autonomy_project_name() {
  local autonomy_file="$1"
  local selected_project_name="$2"
  local escaped_project_name tmp_file

  [[ -f "$autonomy_file" ]] || return 0

  escaped_project_name="${selected_project_name//\"/\\\"}"
  tmp_file="$(mktemp)"

  awk -v project_name="$escaped_project_name" '
    BEGIN {
      replaced = 0
      inserted = 0
    }
    /^[[:space:]]*project:[[:space:]]*/ {
      if (replaced == 0) {
        print "project: \"" project_name "\""
        replaced = 1
      }
      next
    }
    /^[[:space:]]*modules:[[:space:]]*$/ {
      if (replaced == 0 && inserted == 0) {
        print "project: \"" project_name "\""
        print ""
        inserted = 1
      }
      print
      next
    }
    { print }
    END {
      if (replaced == 0 && inserted == 0) {
        print ""
        print "project: \"" project_name "\""
      }
    }
  ' "$autonomy_file" >"$tmp_file"

  if ! cmp -s "$autonomy_file" "$tmp_file"; then
    mv "$tmp_file" "$autonomy_file"
    info "Synced project name in clear/autonomy.yml: $selected_project_name"
  else
    rm -f "$tmp_file"
  fi
}

run_setup_flow() {
  local setup_target="$1"
  local setup_source_root="$2"

  local project_name
  project_name="$(ask "Project name" "$(basename "$setup_target")")"
  [[ -n "$project_name" ]] || project_name="$(basename "$setup_target")"

  mkdir -p "$setup_target/clear"
  if [[ ! -f "$setup_target/clear/autonomy.yml" ]]; then
    copy_file_if_missing "$setup_source_root/templates/agent-configs/clear/autonomy.yml" "$setup_target/clear/autonomy.yml"
  fi
  sync_autonomy_project_name "$setup_target/clear/autonomy.yml" "$project_name"

  if [[ -d "$setup_target/scripts" ]]; then
    chmod +x "$setup_target/scripts/"*.sh 2>/dev/null || true
  fi

  info "Setup completed for: $project_name"
  info "Next: review clear/autonomy.yml and run ./scripts/verify-ci.sh in your project."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET_DIR="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --yes)
      YES=true
      shift
      ;;
    --no-setup)
      RUN_SETUP=false
      shift
      ;;
    --setup-only)
      SETUP_ONLY=true
      shift
      ;;
    --install-examples)
      INSTALL_EXAMPLES_PATH="${2:-}"
      shift 2
      ;;
    --extract)
      EXTRACT_PATH="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      error "Unknown argument: $1"
      usage
      exit "$EXIT_USAGE"
      ;;
    *)
      if [[ -n "$TARGET_DIR" ]]; then
        error "Unexpected argument: $1"
        usage
        exit "$EXIT_USAGE"
      fi
      TARGET_DIR="$1"
      shift
      ;;
  esac
done

if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="$PWD"
fi

EMBEDDED_MODE=false
if has_embedded_payload; then
  EMBEDDED_MODE=true
fi

if [[ -n "$EXTRACT_PATH" && ( "$TARGET_DIR" != "$PWD" || "$DRY_RUN" == "true" || "$YES" == "true" ) ]]; then
  error "--extract cannot be combined with --target/positional target, --dry-run, or --yes"
  exit "$EXIT_USAGE"
fi

if [[ -n "$EXTRACT_PATH" && -n "$INSTALL_EXAMPLES_PATH" ]]; then
  error "--extract cannot be combined with --install-examples"
  exit "$EXIT_USAGE"
fi

if [[ "$SETUP_ONLY" == "true" && ( -n "$EXTRACT_PATH" || -n "$INSTALL_EXAMPLES_PATH" ) ]]; then
  error "--setup-only cannot be combined with --extract or --install-examples"
  exit "$EXIT_USAGE"
fi

if [[ -n "$INSTALL_EXAMPLES_PATH" && ( "$TARGET_DIR" != "$PWD" || "$DRY_RUN" == "true" || "$YES" == "true" || "$RUN_SETUP" == "false" ) ]]; then
  error "--install-examples cannot be combined with --target/positional target, --dry-run, --yes, or --no-setup"
  exit "$EXIT_USAGE"
fi

if [[ -n "$EXTRACT_PATH" && "$EMBEDDED_MODE" != "true" ]]; then
  error "--extract requires an embedded payload (release installer artifact)"
  exit "$EXIT_USAGE"
fi

if [[ -n "$EXTRACT_PATH" ]]; then
  if [[ -e "$EXTRACT_PATH" ]]; then
    if [[ -d "$EXTRACT_PATH" && -n "$(ls -A "$EXTRACT_PATH" 2>/dev/null)" && "$FORCE" != "true" ]]; then
      error "Extraction path exists and is not empty. Use --force to allow overwrite."
      exit "$EXIT_EXTRACT"
    fi
    if [[ ! -d "$EXTRACT_PATH" ]]; then
      error "Extraction path exists and is not a directory: $EXTRACT_PATH"
      exit "$EXIT_EXTRACT"
    fi
  fi

  mkdir -p "$EXTRACT_PATH"
  extract_payload "$EXTRACT_PATH" || {
    error "Extraction failed"
    exit "$EXIT_EXTRACT"
  }

  info "Extraction complete: $EXTRACT_PATH"
  echo "RESULT success mode=extract"
  exit 0
fi

SOURCE_ROOT=""
if [[ "$EMBEDDED_MODE" == "true" ]]; then
  command -v tar >/dev/null 2>&1 || {
    error "Required tool not found: tar"
    exit "$EXIT_PREFLIGHT"
  }
  command -v mktemp >/dev/null 2>&1 || {
    error "Required tool not found: mktemp"
    exit "$EXIT_PREFLIGHT"
  }

  WORK_DIR="$(mktemp -d)"
  trap cleanup EXIT INT TERM

  extract_payload "$WORK_DIR" || {
    error "Failed to extract installer payload"
    exit "$EXIT_EXTRACT"
  }

  SOURCE_ROOT="$WORK_DIR/clear-dist"
  [[ -d "$SOURCE_ROOT" ]] || {
    error "Extracted payload is missing clear-dist"
    exit "$EXIT_RUNTIME"
  }
else
  SOURCE_ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
fi

if [[ -n "$INSTALL_EXAMPLES_PATH" ]]; then
  EXAMPLES_SOURCE="$SOURCE_ROOT/templates/examples"
  [[ -d "$EXAMPLES_SOURCE" ]] || {
    error "Examples source not found: $EXAMPLES_SOURCE"
    exit "$EXIT_RUNTIME"
  }

  if [[ -e "$INSTALL_EXAMPLES_PATH" ]]; then
    if [[ -d "$INSTALL_EXAMPLES_PATH" && -n "$(ls -A "$INSTALL_EXAMPLES_PATH" 2>/dev/null)" && "$FORCE" != "true" ]]; then
      error "Examples path exists and is not empty. Use --force to allow overwrite."
      exit "$EXIT_EXTRACT"
    fi
    if [[ ! -d "$INSTALL_EXAMPLES_PATH" ]]; then
      error "Examples path exists and is not a directory: $INSTALL_EXAMPLES_PATH"
      exit "$EXIT_EXTRACT"
    fi
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    info "Dry run: would copy templates/examples/* to $INSTALL_EXAMPLES_PATH"
    echo "RESULT success mode=install-examples dry-run=true"
    exit 0
  fi

  mkdir -p "$INSTALL_EXAMPLES_PATH"
  cp -r "$EXAMPLES_SOURCE/." "$INSTALL_EXAMPLES_PATH/"
  info "Examples installed: $INSTALL_EXAMPLES_PATH"
  echo "RESULT success mode=install-examples"
  exit 0
fi

if [[ "$SETUP_ONLY" == "true" ]]; then
  run_setup_flow "$TARGET_DIR" "$SOURCE_ROOT"
  echo "RESULT success mode=setup-only"
  exit 0
fi

if [[ ! -d "$TARGET_DIR" ]]; then
  error "Target directory does not exist: $TARGET_DIR"
  exit "$EXIT_RUNTIME"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  info "Dry run: would install/update CLEAR files in $TARGET_DIR"
  info "Dry run: scripts copied to target include verify-ci.sh only (verify-local.sh create-if-missing)"
  echo "RESULT success mode=install-or-update dry-run=true"
  exit 0
fi

if [[ -f "$TARGET_DIR/clear/autonomy.yml" ]]; then
  info "Detected existing CLEAR project. Running update workflow."
else
  info "Detected fresh target. Running bootstrap workflow."
fi

# CLEAR-managed files (always updated)
copy_file_update "$SOURCE_ROOT/scripts/verify-ci.sh" "$TARGET_DIR/scripts/verify-ci.sh"
copy_file_update "$SOURCE_ROOT/clear/principles.md" "$TARGET_DIR/clear/principles.md"
copy_dir_update "$SOURCE_ROOT/templates/agent-configs/.github" "$TARGET_DIR/.github" "prompts"
copy_dir_update "$SOURCE_ROOT/templates/agent-configs/.cursor" "$TARGET_DIR/.cursor"
copy_dir_update "$SOURCE_ROOT/templates/agent-configs/.claude" "$TARGET_DIR/.claude"
copy_dir_update "$SOURCE_ROOT/templates/agent-configs/.vscode" "$TARGET_DIR/.vscode"
copy_file_update "$SOURCE_ROOT/templates/agent-configs/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"
copy_file_update "$SOURCE_ROOT/templates/agent-configs/.cursorrules" "$TARGET_DIR/.cursorrules"

# Project-owned files (create-if-missing)
copy_file_if_missing "$SOURCE_ROOT/templates/agent-configs/scripts/verify-local.sh" "$TARGET_DIR/scripts/verify-local.sh"
copy_file_if_missing "$SOURCE_ROOT/templates/agent-configs/clear/autonomy.yml" "$TARGET_DIR/clear/autonomy.yml"
copy_file_if_missing "$SOURCE_ROOT/clear/extensions.yml" "$TARGET_DIR/clear/extensions.yml"
copy_file_if_missing "$SOURCE_ROOT/templates/agent-configs/.gitignore" "$TARGET_DIR/.gitignore"

# Templates copied without examples as part of onboarding
if [[ -d "$SOURCE_ROOT/templates" ]]; then
  copy_dir_update "$SOURCE_ROOT/templates" "$TARGET_DIR/templates"
  if [[ -d "$TARGET_DIR/templates/examples" ]]; then
    rm -rf "$TARGET_DIR/templates/examples"
  fi
fi

# Keep already-installed generic skills current.
if [[ -d "$TARGET_DIR/.github/prompts" ]]; then
  while IFS= read -r prompt_file; do
    skill_name="$(basename "$prompt_file" .prompt.md)"
    src_skill=""
    if [[ -f "$SOURCE_ROOT/templates/skills/${skill_name}.md" ]]; then
      src_skill="$SOURCE_ROOT/templates/skills/${skill_name}.md"
    fi
    if [[ -n "$src_skill" ]]; then
      cp "$src_skill" "$prompt_file"
    fi
  done < <(find "$TARGET_DIR/.github/prompts" -name "*.prompt.md" -type f | sort)
fi

if [[ -d "$TARGET_DIR/scripts" ]]; then
  chmod +x "$TARGET_DIR/scripts/"*.sh 2>/dev/null || true
fi

if [[ "$RUN_SETUP" == "true" ]]; then
  info "Running setup wizard..."
  run_setup_flow "$TARGET_DIR" "$SOURCE_ROOT"
else
  info "Setup wizard skipped (--no-setup)."
fi

info "Installer completed successfully"
echo "RESULT success mode=install-or-update"
exit 0
