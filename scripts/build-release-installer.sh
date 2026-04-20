#!/usr/bin/env bash
# =============================================================================
# CLEAR build-release-installer.sh — Build self-extracting installer artifacts
# =============================================================================
# Usage:
#   ./scripts/build-release-installer.sh --version 1.2.3
#   ./scripts/build-release-installer.sh --version 1.2.3 --output-dir dist/release
#   ./scripts/build-release-installer.sh --version 1.2.3 --no-sign
#   ./scripts/build-release-installer.sh --version 1.2.3 --signing-key ABCDEF1234
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=./release-lib.sh
source "$SCRIPT_DIR/release-lib.sh"

VERSION=""
OUTPUT_DIR="$PROJECT_ROOT/dist/release"
SIGN_ARTIFACTS=true
SIGNING_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --signing-key)
      SIGNING_KEY="${2:-}"
      shift 2
      ;;
    --no-sign)
      SIGN_ARTIFACTS=false
      shift
      ;;
    --help | -h)
      cat <<'EOF'
Usage: ./scripts/build-release-installer.sh --version <semver> [options]

Options:
  --output-dir <dir>   Output directory for release artifacts
  --signing-key <id>   GPG key ID/fingerprint for detached signature
  --no-sign            Skip detached signature generation (break-glass)
  --help               Show this help
EOF
      exit 0
      ;;
    *)
      rl_die 2 "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$VERSION" ]] || rl_die 2 "--version is required"
rl_validate_semver "$VERSION" || rl_die 2 "Invalid semantic version: $VERSION"

rl_require_command tar "Install tar"
rl_require_command sha256sum "Install coreutils"

if [[ "$SIGN_ARTIFACTS" == "true" ]]; then
  rl_require_command gpg "Install GnuPG"
fi

WORK_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

STAGE_DIR="$WORK_DIR/stage"
PAYLOAD_DIR="$STAGE_DIR/clear-dist"
mkdir -p "$PAYLOAD_DIR"

rl_info "Staging release payload"
cp -R "$PROJECT_ROOT/scripts" "$PAYLOAD_DIR/scripts"
cp -R "$PROJECT_ROOT/clear" "$PAYLOAD_DIR/clear"
cp -R "$PROJECT_ROOT/templates" "$PAYLOAD_DIR/templates"
cp -R "$PROJECT_ROOT/docs" "$PAYLOAD_DIR/docs"
cp "$PROJECT_ROOT/README.md" "$PAYLOAD_DIR/README.md"
cp "$PROJECT_ROOT/CHANGELOG.md" "$PAYLOAD_DIR/CHANGELOG.md"
cp "$PROJECT_ROOT/LICENSE" "$PAYLOAD_DIR/LICENSE"
cp "$PROJECT_ROOT/VERSION" "$PAYLOAD_DIR/VERSION"

PAYLOAD_TARBALL="$WORK_DIR/payload.tar.gz"
(
  cd "$STAGE_DIR"
  tar -czf "$PAYLOAD_TARBALL" clear-dist
)

INSTALLER_NAME="clear-installer-v$VERSION.sh"
CHECKSUM_NAME="clear-installer-v$VERSION.sha256"
SIGNATURE_NAME="clear-installer-v$VERSION.sha256.asc"

mkdir -p "$OUTPUT_DIR"
INSTALLER_PATH="$OUTPUT_DIR/$INSTALLER_NAME"
CHECKSUM_PATH="$OUTPUT_DIR/$CHECKSUM_NAME"
SIGNATURE_PATH="$OUTPUT_DIR/$SIGNATURE_NAME"

cat >"$INSTALLER_PATH" <<'EOF'
#!/usr/bin/env bash
# CLEAR self-extracting installer
set -euo pipefail

EXIT_USAGE=2
EXIT_PREFLIGHT=3
EXIT_RUNTIME=4
EXIT_EXTRACT=5

TARGET_DIR="$PWD"
DRY_RUN=false
FORCE=false
YES=false
EXTRACT_PATH=""
WORK_DIR=""

error() { echo "ERR  $*" >&2; }
info() { echo "INFO $*"; }

usage() {
  cat <<'USAGE'
Usage:
  clear-installer.sh [--target <path>] [--dry-run] [--force] [--yes]
  clear-installer.sh --extract <path> [--force]

Options:
  --target <path>   Target repository path (default: current directory)
  --dry-run         Show what would happen without modifying target files
  --force           Allow overwrite for --extract collisions
  --yes             Auto-confirm prompts
  --extract <path>  Extract payload only, do not install/update
  --help            Show this help
USAGE
}

cleanup() {
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
}

extract_payload() {
  local destination="$1"
  local marker_line
  marker_line="$(awk '/^__CLEAR_PAYLOAD_BELOW__$/ { print NR + 1; exit }' "$0")"
  [[ -n "$marker_line" ]] || {
    error "Installer payload marker not found"
    return 1
  }

  mkdir -p "$destination"
  tail -n "+$marker_line" "$0" | tar -xzf - -C "$destination"
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
    --extract)
      EXTRACT_PATH="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      error "Unknown argument: $1"
      usage
      exit "$EXIT_USAGE"
      ;;
  esac
done

if [[ -n "$EXTRACT_PATH" && ( "$TARGET_DIR" != "$PWD" || "$DRY_RUN" == "true" || "$YES" == "true" ) ]]; then
  error "--extract cannot be combined with --target, --dry-run, or --yes"
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

PAYLOAD_ROOT="$WORK_DIR/clear-dist"
[[ -d "$PAYLOAD_ROOT" ]] || {
  error "Extracted payload is missing clear-dist"
  exit "$EXIT_RUNTIME"
}

if [[ ! -d "$TARGET_DIR" ]]; then
  error "Target directory does not exist: $TARGET_DIR"
  exit "$EXIT_RUNTIME"
fi

if [[ -f "$TARGET_DIR/clear/autonomy.yml" ]]; then
  info "Detected existing CLEAR project. Running update workflow."
  UPDATE_CMD=("$PAYLOAD_ROOT/scripts/update-project.sh")
  if [[ "$DRY_RUN" == "true" ]]; then
    UPDATE_CMD+=("--dry-run")
  fi
  UPDATE_CMD+=("$TARGET_DIR")
  "${UPDATE_CMD[@]}" || {
    error "Update workflow failed"
    exit "$EXIT_RUNTIME"
  }
else
  info "Detected fresh target. Running bootstrap workflow."
  BOOTSTRAP_CMD=("$PAYLOAD_ROOT/scripts/bootstrap-project.sh" "--no-setup")
  if [[ "$DRY_RUN" == "true" ]]; then
    BOOTSTRAP_CMD+=("--dry-run")
  fi
  BOOTSTRAP_CMD+=("$TARGET_DIR")
  "${BOOTSTRAP_CMD[@]}" || {
    error "Bootstrap workflow failed"
    exit "$EXIT_RUNTIME"
  }
fi

info "Installer completed successfully"
echo "RESULT success mode=install-or-update"
exit 0

__CLEAR_PAYLOAD_BELOW__
EOF

cat "$PAYLOAD_TARBALL" >>"$INSTALLER_PATH"
chmod +x "$INSTALLER_PATH"

(
  cd "$OUTPUT_DIR"
  sha256sum "$INSTALLER_NAME" >"$CHECKSUM_NAME"
)

if [[ "$SIGN_ARTIFACTS" == "true" ]]; then
  gpg_args=(--batch --yes --armor --detach-sign --output "$SIGNATURE_PATH")
  if [[ -n "$SIGNING_KEY" ]]; then
    gpg_args+=(--local-user "$SIGNING_KEY")
  fi
  gpg "${gpg_args[@]}" "$CHECKSUM_PATH"
  rl_ok "Created detached signature: $SIGNATURE_PATH"
else
  rl_warn "Signature generation disabled (--no-sign)."
fi

rl_ok "Created installer: $INSTALLER_PATH"
rl_ok "Created checksums: $CHECKSUM_PATH"
