---
name: release
description: "Create a signed CLEAR release artifact set, tag code, and publish to GitHub Releases (repo-local workflow)."
mode: agent
---

# CLEAR Repo Skill: Make a Release

Use this skill when a user asks to "make a release", "cut a release", or "publish a version" for this repository.

## Non-negotiables

1. Git tree must be clean before starting.
2. Release must run from `main`.
3. `./scripts/verify-ci.sh` must pass unless `--skip-verify` was explicitly requested as break-glass.
4. Release must include installer, checksum, and detached checksum signature.
5. Do not claim release complete until `gh release create` succeeds.
6. After publishing, update README's "CLEAR in 60 Seconds" version block by replacing only the content between:
   - `<!-- RELEASE_VERSION_START -->`
   - `<!-- RELEASE_VERSION_END -->`
7. The updated block must include:
   - the new version label `vX.Y.Z`
   - a link to `https://github.com/jketreno/clear/releases/tag/vX.Y.Z`
   - minimal install commands with exact installer filename for that version

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
4. README content between `RELEASE_VERSION_START` and `RELEASE_VERSION_END` is updated to `vX.Y.Z`.

## README tagged block template (post-release)

Replace only the content between the tag markers with:

~~~markdown
<!-- RELEASE_VERSION_START -->
**Install the latest release (vX.Y.Z):**

[Download CLEAR vX.Y.Z](https://github.com/jketreno/clear/releases/tag/vX.Y.Z)

```bash
curl -fsSLO https://github.com/jketreno/clear/releases/download/vX.Y.Z/clear-installer-vX.Y.Z.sh
bash clear-installer-vX.Y.Z.sh --target /path/to/your-project
```
<!-- RELEASE_VERSION_END -->
~~~
