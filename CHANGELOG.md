# Changelog

All notable user-facing changes to this project are documented in this file.

## v1.0.0 - 2026-04-21

Initial public release prepared from repository history (no prior release tags found).

### Added

- CLEAR framework foundation with the five principles: Constrained, Limited, Ephemeral, Assertive, and Reality-Aligned.
- Bootstrap and setup workflow for existing projects with autonomy boundaries and source-of-truth onboarding.
- Unified update path via `scripts/bootstrap-project.sh --update`.
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
