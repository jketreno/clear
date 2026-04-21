---
mode: agent
tools: ["run_in_terminal", "read_file", "apply_patch"]
model: GPT-5.3-Codex
---

# Release + README Sync

Use this prompt when asked to cut/publish a release.

## Steps

1. Run the release workflow from `.github/skills/release.md`.
2. Confirm the GitHub release exists and list uploaded assets.
3. Update README "CLEAR in 60 Seconds" by replacing only the content between `<!-- RELEASE_VERSION_START -->` and `<!-- RELEASE_VERSION_END -->`.
4. Ensure the replaced block contains the latest tag link and exact installer filename (`clear-installer-vX.Y.Z.sh`).
5. Run `./scripts/verify-ci.sh` and report pass/fail.
