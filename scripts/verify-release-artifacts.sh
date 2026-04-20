#!/usr/bin/env bash
# =============================================================================
# CLEAR verify-release-artifacts.sh — Verify release signature and checksums
# =============================================================================
# Usage:
#   ./scripts/verify-release-artifacts.sh --version 1.2.3 --dir ./dist/release/v1.2.3
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./release-lib.sh
source "$SCRIPT_DIR/release-lib.sh"

VERSION=""
ARTIFACT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --dir)
      ARTIFACT_DIR="${2:-}"
      shift 2
      ;;
    --help | -h)
      cat <<'EOF'
Usage: ./scripts/verify-release-artifacts.sh --version <semver> --dir <path>

Verifies:
  1) Detached signature of checksum manifest
  2) Installer checksum integrity
EOF
      exit 0
      ;;
    *)
      rl_die 2 "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$VERSION" ]] || rl_die 2 "--version is required"
[[ -n "$ARTIFACT_DIR" ]] || rl_die 2 "--dir is required"
rl_validate_semver "$VERSION" || rl_die 2 "Invalid semantic version: $VERSION"
[[ -d "$ARTIFACT_DIR" ]] || rl_die 3 "Artifact directory not found: $ARTIFACT_DIR"

rl_require_command gpg "Install GnuPG"
rl_require_command sha256sum "Install coreutils"

INSTALLER="clear-installer-v$VERSION.sh"
CHECKSUMS="clear-installer-v$VERSION.sha256"
SIGNATURE="clear-installer-v$VERSION.sha256.asc"

[[ -f "$ARTIFACT_DIR/$INSTALLER" ]] || rl_die 3 "Missing artifact: $INSTALLER"
[[ -f "$ARTIFACT_DIR/$CHECKSUMS" ]] || rl_die 3 "Missing artifact: $CHECKSUMS"
[[ -f "$ARTIFACT_DIR/$SIGNATURE" ]] || rl_die 3 "Missing artifact: $SIGNATURE"

rl_info "Verifying detached signature over checksum manifest"
set +e
gpg --verify "$ARTIFACT_DIR/$SIGNATURE" "$ARTIFACT_DIR/$CHECKSUMS" >/dev/null 2>&1
sig_status=$?
set -e
if [[ "$sig_status" -ne 0 ]]; then
  rl_error "Signature verification failed. Abort. Re-download artifacts and confirm the trusted signing key fingerprint."
  exit 3
fi

rl_info "Verifying installer checksum"
(
  cd "$ARTIFACT_DIR"
  set +e
  sha256sum -c "$CHECKSUMS" >/dev/null 2>&1
  checksum_status=$?
  set -e
  if [[ "$checksum_status" -ne 0 ]]; then
    rl_error "Checksum verification failed. Abort. Artifact may be corrupted or tampered."
    exit 1
  fi
)

rl_ok "Release artifacts verified. You may run the installer."
