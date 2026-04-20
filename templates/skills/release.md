---
name: release
description: "Create a signed CLEAR release artifact set, tag code, and publish to GitHub Releases."
mode: agent
---

# CLEAR Skill: Make a Release

Use this skill when a user asks to "make a release", "cut a release", or "publish a version".

## Non-negotiables

1. Git tree must be clean before starting.
2. Release must run from `main`.
3. `./scripts/verify-ci.sh` must pass unless `--skip-verify` was explicitly requested as break-glass.
4. Release must include installer, checksum, and detached checksum signature.
5. Do not claim release complete until `gh release create` succeeds.

## Command

```bash
./scripts/release.sh --yes
```

Optional explicit version:

```bash
./scripts/release.sh --version 1.2.3 --yes
```

Dry run:

```bash
./scripts/release.sh --dry-run
```

## Required output checks

1. Tag exists: `vX.Y.Z`
2. GitHub release exists: `vX.Y.Z`
3. Assets uploaded:
   - `clear-installer-vX.Y.Z.sh`
   - `clear-installer-vX.Y.Z.sha256`
   - `clear-installer-vX.Y.Z.sha256.asc`

## Verification reminder for users

Always verify signature then checksum before running installer:

```bash
gpg --verify clear-installer-vX.Y.Z.sha256.asc clear-installer-vX.Y.Z.sha256
sha256sum -c clear-installer-vX.Y.Z.sha256
```
