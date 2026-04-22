# Changelog

All notable user-facing changes to this project are documented in this file.

## v1.1.0 - 2026-04-21

### Changed

- **Namespace consolidation:** All installed files now live under `clear/` instead of scattered across `scripts/` and `templates/`. This prevents collisions with existing project directories.
  - `scripts/verify-ci.sh` → `clear/verify-ci.sh`
  - `scripts/verify-local.sh` → `clear/verify-local.sh`
  - `templates/` → `clear/templates/`, `clear/examples/`, `clear/docs/`
- Templates, examples, and documentation are now installed into target projects so all config file references resolve to actual files.
- Unified installer now uses `install/` source layout that maps 1:1 to what gets installed.
- Setup wizard and installer behavior improvements: tighter verification rules, generic autonomy template, and better nested file handling.
- Examples moved out of onboarding bootstrap flow — available separately via `--install-examples`.

## v1.0.0 - 2026-04-21

Initial public release prepared from repository history (no prior release tags found).

### Added

- CLEAR framework foundation with the five principles: Constrained, Limited, Ephemeral, Assertive, and Reality-Aligned.
- Bootstrap and setup workflow for existing projects with autonomy boundaries and source-of-truth onboarding.
- Unified install and update path via the CLEAR installer.
- Local CI enforcement script (`scripts/verify-ci.sh`) plus project-owned extension points (`scripts/verify-local.sh`).
- Optional extension system and interactive extension setup support.
- Generic and example AI skills, including release prep and autonomy bootstrap guidance.
- Release automation scripts for installer/checksum/signature artifact generation.

### Changed

- Installer and release guidance now include explicit artifact/key download and signature verification instructions before execution.
- Release prep workflow now enforces docs/code accuracy checks and manual publish handoff due GPG passphrase entry.
- Setup wizard skill messaging updated for tool-agnostic assistant usage (Cursor, Copilot Chat, Claude, etc.).
- Project structure split between generic templates and domain-specific examples for safer adoption.

### Fixed

- Setup wizard interaction flow and prompt handling reliability improvements.
- Script linting/formatting/syntax guardrails integrated and validated via local verification.
- Multiple documentation accuracy updates for current script flags and supported workflows.
