# Getting Started with CLEAR

> CLEAR is a framework for AI-assisted development that keeps architecture rules enforced, not suggested.
> This guide gets you from "just cloned" to "first constraint running" in about 30 minutes.

---

## Prerequisites

- Git
- bash (Linux, macOS, or WSL on Windows)
- Your AI tool: VS Code + GitHub Copilot, Claude Code, or Cursor

---

## Step 1: Clone and Explore

```bash
git clone https://github.com/jketreno/clear
cd clear
```

Look at the top-level structure:

```
scripts/          — verify-ci.sh (enforcement), setup-clear.sh (wizard),
                    bootstrap-project.sh (bootstrap + update)
clear/            — autonomy.yml (boundaries), principles.md (reference)
templates/        — copy-paste starting points for architecture tests and skills
docs/             — this documentation
.github/          — Copilot configs + GitHub Actions template
.cursor/rules/    — Cursor AI rules
.claude/          — Claude Code commands
CLAUDE.md         — Claude Code root config
```

---

## Step 2: Initialize CLEAR for a New Project

If you are adopting CLEAR into an **existing** project (most common), run the bootstrap script from the CLEAR seed repo:

```bash
# From the clear/ seed repository root:
./scripts/bootstrap-project.sh /path/to/your-project
```

This copies all CLEAR files into your project and then launches the setup wizard automatically. Existing files in your project are never overwritten — directories are merged and individual files are skipped if they already exist.

If the target already has CLEAR installed, run bootstrap in update mode:

```bash
./scripts/bootstrap-project.sh --update /path/to/your-project
```

**Options:**

| Flag | Description |
|------|-------------|
| `--dry-run` | Show what would be copied without writing anything |
| `--update` | Update an already-bootstrapped project |
| `--no-templates` | Skip copying the `templates/` directory |
| `--no-setup` | Copy files only; skip running `setup-clear.sh` |
| `--setup-extensions` | Interactive extension setup (use with `--update`) |
| `--self-sync` | Allow self-sync when targeting the CLEAR seed repo (use with `--update`) |

```bash
# Preview what will happen first:
./scripts/bootstrap-project.sh --dry-run /path/to/your-project

# Copy files without running the setup wizard:
./scripts/bootstrap-project.sh --no-setup /path/to/your-project
```

The setup wizard will:
1. Offer to use the `autonomy-bootstrap` skill to generate project-specific boundaries and sources of truth
2. Create or keep a starter `clear/autonomy.yml`
3. Fall back to manual prompts for boundaries/concepts if you choose not to use the skill flow

**Keeping your project up to date:** As the CLEAR seed evolves, run bootstrap in update mode to sync improvements back into your project:

```bash
# From the clear/ seed repository root:
./scripts/bootstrap-project.sh --update /path/to/your-project
```

---

## Step 3: Add your project's checks

`verify-ci.sh` auto-detects your stack (Node, Python, Go, Rust) and is CLEAR-owned — updated when you pull new CLEAR versions. Your project-specific checks go in `scripts/verify-local.sh`, which is never overwritten.

Open `scripts/verify-local.sh` and add your project's checks:

**For Node.js/TypeScript:**
```bash
run_check "TypeScript build" "cd '$PROJECT_ROOT' && npm run build 2>&1"
run_check "ESLint" "cd '$PROJECT_ROOT' && npx eslint . 2>&1"
run_check "Jest" "cd '$PROJECT_ROOT' && npm test 2>&1"

if ! $FAST_MODE; then
  run_check "Architecture" "cd '$PROJECT_ROOT' && npm run test:architecture 2>&1"
fi
```

**For Python:**
```bash
run_check "Ruff lint" "cd '$PROJECT_ROOT' && ruff check . 2>&1"
run_check "Mypy types" "cd '$PROJECT_ROOT' && mypy . 2>&1"
run_check "pytest" "cd '$PROJECT_ROOT' && pytest --tb=short -q 2>&1"

if ! $FAST_MODE; then
  run_check "Architecture tests" "cd '$PROJECT_ROOT' && pytest tests/architecture/ 2>&1"
fi
```

All helpers (`run_check`, `pass`, `fail`, `info`, `warn`, `section`) and variables (`PROJECT_ROOT`, `FAST_MODE`, `FIX_MODE`) are available from `verify-ci.sh`.

**Run it now** to see what passes and what doesn't in your current project:

```bash
./scripts/verify-ci.sh
```

Don't worry if things fail — that's the point. You're establishing a baseline.

---

## Step 4: Configure Your AI Tool

### VS Code / GitHub Copilot

The `.github/copilot-instructions.md` file is auto-read by Copilot. No additional setup needed.

Enable instruction files in VS Code settings:
```json
"github.copilot.chat.codeGeneration.useInstructionFiles": true
```

Run the CLEAR task from the command palette:
- `Ctrl/Cmd + Shift + P` → "Tasks: Run Task" → "CLEAR: Verify CI"

See [docs/ai-tools/vscode-copilot.md](ai-tools/vscode-copilot.md) for full setup.

### Claude Code

The `CLAUDE.md` file in your project root is auto-read at session start.

Available slash commands (defined in `.claude/commands/`):
- `/project:verify` — run verify-ci.sh and get a structured report
- `/project:check-autonomy [path]` — check autonomy level for a file
- `/project:update-autonomy` — guided autonomy boundary update

See [docs/ai-tools/claude.md](ai-tools/claude.md) for full setup.

### Cursor

The `.cursor/rules/` directory is auto-applied. The `.cursorrules` file provides a legacy fallback.

Rules applied automatically:
- `clear-workflow.mdc` — always
- `clear-limited.mdc` — always (checks autonomy.yml before every change)
- `clear-constrained.mdc` — always
- `clear-ephemeral.mdc` — always
- `clear-assertive.mdc` — on test files
- `clear-reality-aligned.mdc` — always

See [docs/ai-tools/cursor.md](ai-tools/cursor.md) for full setup.

---

## Step 5: Your First Experiment

Pick ONE of these — the one that matches your biggest current pain point:

### Option A: Turn a code review comment into a test [C]

1. Think of your most common code review comment ("always add input validation", "never commit console.log", etc.)
2. Ask your AI:
   ```
   Turn this code review rule into an architecture test:
   "[YOUR RULE]"
   Wire it into scripts/verify-ci.sh.
   ```
3. Review the generated test. Run `./scripts/verify-ci.sh`.
4. That rule now fails before it reaches code review.

### Option B: Mark a module boundary [L]

1. Open `clear/autonomy.yml`
2. Find your most sensitive/critical module (authentication, payments, etc.)
3. Set it to `humans-only`
4. Ask your AI to modify a file in that module
5. It should refuse and explain why

### Option C: Delete and regenerate [E+A]

1. Pick a non-trivial component with tests
2. Delete the implementation (keep the tests)
3. Ask AI to regenerate it: "Regenerate the implementation to make these tests pass"
4. Compare quality — did the tests define enough invariants?

### Option D: Write a reality test [R]

1. Pick one external dependency (database, OAuth/IAM provider, external API)
2. Ask your AI:
   ```
   Write a reality test using templates/examples/skills/reality-test.md
   that verifies our [concept] model matches [external system].
   ```
3. Run it against your staging environment

---

## Step 6: Add Architecture Tests

Copy a template from `templates/architecture-tests/` (generic) or `templates/examples/architecture-tests/` (domain-specific) into `tests/architecture/`:

```bash
cp templates/architecture-tests/autonomy-guard.test.js tests/architecture/
cp templates/examples/architecture-tests/api-rules.test.js tests/architecture/
```

Edit the copied files to match your project structure (the `// UPDATE:` comments show you where).

Add to `scripts/verify-local.sh`:
```bash
run_check "Architecture tests" "cd '$PROJECT_ROOT' && npx jest tests/architecture/ 2>&1"
```

---

## What's Next

| Goal | Document |
|------|---------|
| Deep dive into enforcement | [docs/principles/constrained.md](principles/constrained.md) |
| Configure autonomy boundaries | [docs/principles/limited.md](principles/limited.md) |
| Set up regeneration workflows | [docs/principles/ephemeral.md](principles/ephemeral.md) |
| Improve your tests | [docs/principles/assertive.md](principles/assertive.md) |
| Declare sources of truth | [docs/principles/reality-aligned.md](principles/reality-aligned.md) |
| VS Code / Copilot setup details | [docs/ai-tools/vscode-copilot.md](ai-tools/vscode-copilot.md) |
| Claude Code setup details | [docs/ai-tools/claude.md](ai-tools/claude.md) |
| Cursor setup details | [docs/ai-tools/cursor.md](ai-tools/cursor.md) |
| Multi-agent pipelines & MCP | [docs/agentic.md](agentic.md) |

---

## The 30-Second Check

After any AI-generated change, run:

```bash
./scripts/verify-ci.sh
```

If it passes: commit.  
If it fails: fix it, run again.  
**Never commit AI-generated code that hasn't passed verify-ci.sh.**
