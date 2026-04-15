# Cursor Setup Guide

> CLEAR configures Cursor through `.cursor/rules/*.mdc` files (MDC format) that apply automatically based on file patterns or globally. A `.cursorrules` fallback is included for older Cursor versions.

---

## Prerequisites

- Cursor IDE installed
- CLEAR files copied into your project (see [docs/getting-started.md](../getting-started.md))

---

## How CLEAR Configures Cursor

### Primary: `.cursor/rules/*.mdc` files

Cursor reads `.mdc` files from `.cursor/rules/` and applies them automatically. CLEAR includes six rule files:

| Rule file | Application | CLEAR principle |
|-----------|------------|-----------------|
| `clear-workflow.mdc` | All files (alwaysApply) | Workflow: verify-ci.sh, PLAN mode |
| `clear-limited.mdc` | All files (alwaysApply) | [L] Check autonomy.yml before every change |
| `clear-constrained.mdc` | All files (alwaysApply) | [C] Enforce rules via tests and linters |
| `clear-ephemeral.mdc` | All files (alwaysApply) | [E] Regenerate generated code, don't patch |
| `clear-reality-aligned.mdc` | All files (alwaysApply) | [R] Derive from declared source of truth |
| `clear-assertive.mdc` | Test files (globs) | [A] Write invariant tests, not confirmations |

### Fallback: `.cursorrules`

The root `.cursorrules` file provides a summary for older Cursor versions that don't support the `.cursor/rules/` directory. It points to the detailed MDC files.

---

## MDC File Format

Each rule file uses YAML frontmatter to control when it applies:

```markdown
---
description: Brief description of what this rule does
alwaysApply: true          # Apply to every file, every request
---

OR:

---
description: Brief description
globs: ["**/*.test.ts", "tests/**"]  # Apply only to matching files
---
```

**Rule content** is standard markdown. Cursor reads it as context for every AI request that matches the rule's scope.

---

## Verifying the Configuration

After setting up CLEAR, test each rule in Cursor:

**Test [L] Limited:**
Ask Cursor to modify a file in a `humans-only` path (e.g., `src/payment/processor.ts`).
Expected: Cursor refuses and explains the boundary.

**Test workflow:**
Ask Cursor "What must you do before marking work complete?"
Expected: Mentions `./scripts/verify-ci.sh`.

**Test PLAN mode:**
Ask Cursor to implement a new feature.
Expected: Asks to show the plan first, or shows it unprompted.

---

## Adding Project-Specific Rules

### Skill-based rule (for a specific file type)

```markdown
---
description: Type synchronization skill for Python → TypeScript
globs: ["backend/models/**", "frontend/src/types/**"]
---

# Type Sync Skill

When modifying Python Pydantic models in backend/models/:
[content of templates/skills/type-sync.md]
```

### Domain-specific rule (for a specific module)

```markdown
---
description: Payment module rules
globs: ["src/payment/**"]
---

# Payment Module

This module is marked `humans-only` in clear/autonomy.yml.
Do not generate code in this directory.
If asked to modify payment logic, explain: [explanation]
Ask the user to make the change manually.
```

### Architecture test helper rule

```markdown
---
description: Architecture test helper
globs: ["tests/architecture/**"]
---

# Architecture Test Rules

Tests in tests/architecture/ verify structural invariants.
These tests:
- Must use descriptive names: "all endpoints have rate limiting"
- Must NOT mock the module they're testing (they inspect real code)
- Are run by verify-ci.sh automatically
- Failing these is a blocker — do not mark work complete until they pass
```

---

## Cursor Composer Workflow

For complex multi-file changes, use Cursor Composer (Ctrl/Cmd + I):

1. Open Composer
2. CLEAR rules apply automatically
3. Composer respects autonomy boundaries:
   - Generates code for `supervised` paths with a review reminder
   - Refuses code for `humans-only` paths
4. After generation: "Run `./scripts/verify-ci.sh`" appears in the output

---

## Troubleshooting

**Rules are not being applied:**
- Check that `.cursor/rules/` files have `.mdc` extension
- Verify the YAML frontmatter is valid (no tabs, proper indentation)
- Restart Cursor after adding new rule files
- Check Settings → "Rules for AI" to see if rules are loading

**`alwaysApply: true` rules not appearing:**
- Some Cursor versions use different frontmatter keys. Try:
  ```yaml
  ---
  alwaysApply: true
  ---
  ```
  vs:
  ```yaml
  ---
  always: true
  ---
  ```
  Check Cursor's current documentation for the supported key.

**Cursor modifies humans-only files anyway:**
- AI instructions are advisory, not enforced at the file system level
- Add the autonomy guard architecture test to verify-local.sh as a mechanical safety net:
  ```bash
  run_check "Autonomy guard" "cd '$PROJECT_ROOT' && npx jest tests/architecture/autonomy-guard.test.js 2>&1"
  ```
- Consider a pre-commit hook as a final line of defense

**verify-ci.sh not running:**
- Cursor can run terminal commands if you enable it in Settings
- Alternatively: bind a keyboard shortcut to terminal commands in VS Code-compatible keybindings
- Or run manually: `Ctrl + \`` → `./scripts/verify-ci.sh`

**`.cursorrules` vs `.cursor/rules/`:**
- Cursor supports both. If you're on an older version, `.cursorrules` is the fallback
- CLEAR includes both; the `.cursorrules` file is a summary that points to `.cursor/rules/`
- Upgrading to a current Cursor version enables the more granular MDC rule system
