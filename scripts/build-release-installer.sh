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
mkdir -p "$PAYLOAD_DIR/scripts"
cp "$PROJECT_ROOT/scripts/clear-installer.sh" "$PAYLOAD_DIR/scripts/clear-installer.sh"
mkdir -p "$PAYLOAD_DIR/clear"
cp "$PROJECT_ROOT/clear/principles.md" "$PAYLOAD_DIR/clear/principles.md"
cp "$PROJECT_ROOT/clear/extensions.yml" "$PAYLOAD_DIR/clear/extensions.yml"
cp -R "$PROJECT_ROOT/install" "$PAYLOAD_DIR/install"
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

cp "$PROJECT_ROOT/scripts/clear-installer.sh" "$INSTALLER_PATH"
echo "" >>"$INSTALLER_PATH"
echo "__CLEAR_PAYLOAD_BELOW__" >>"$INSTALLER_PATH"

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
