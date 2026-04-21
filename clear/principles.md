# CLEAR Principles — Quick Reference

> Keep this file in your repository root. AI tools are instructed to read it.
> Full documentation: docs/principles/

---

## [C] Constrained — Enforced, not suggested

Rules exist in code and tests, not in code review comments or docs.

**Mechanism:** `scripts/verify-ci.sh` runs before any work is marked complete.  
**Implementation:** Architecture tests, linters, type checkers, build validation.  
**AI rule:** Never report work as complete if `./scripts/verify-ci.sh` fails.

---

## [L] Limited — Boundaries are explicit

Each module has a declared autonomy level. AI checks before every change.

**Mechanism:** `clear/autonomy.yml` maps paths to autonomy levels.  
**Levels:**
- `full-autonomy` — AI proceeds freely
- `supervised` — AI generates; human reviews before commit
- `humans-only` — AI stops and alerts the user

**AI rule:** Read `clear/autonomy.yml` before touching any file. Refuse to generate code in `humans-only` paths.

---

## [E] Ephemeral — Generated code is regenerated, not hand-edited

Code derived from a source of truth is never manually patched.

**Mechanism:** Skill files define regeneration rules. AI follows them exactly.  
**Implementation:** When models change, run the skill — don't patch the output.  
**AI rule:** If a file is marked as generated (header comment, autonomy level), regenerate from source rather than editing in place.

---

## [A] Assertive — Tests define invariants, not confirmations

Tests capture what must always be true, not what the implementation currently does.

**Mechanism:** Architecture tests, property-based tests, schema-lock tests.  
**Test quality check:** Delete the implementation, regenerate it with AI, run tests. If tests fail, they're doing their job.  
**AI rule:** Write tests that would catch a correct-but-different implementation. Prefer invariants ("this can never happen") over confirmations ("this currently returns X").

---

## [R] Reality-Aligned — Single source of truth

Each domain concept has one authoritative source. Everything derives from it.

**Mechanism:** `clear/autonomy.yml` `sources_of_truth` section.  
**Implementation:** Reality tests run against external systems in staging/nightly.  
**AI rule:** When generating code for a domain concept, find its `source_of_truth` in `clear/autonomy.yml` and derive from that. Never invent a representation.

---

## Workflow Summary

```
You: "Implement X"
  ↓
AI checks clear/autonomy.yml for affected paths
  ↓
AI checks clear/principles.md for applicable rules
  ↓
AI generates code following constraints
  ↓
AI runs ./scripts/verify-ci.sh
  ↓
If fails → AI fixes and reruns
  ↓
All checks pass → AI reports: "Complete. All CI checks pass."
You: review the diff, then commit
```

---

## Multi-Agent and MCP

CLEAR principles apply equally to orchestrated multi-agent pipelines. Key rules:

- **Orchestrators:** check `clear/autonomy.yml` before delegating any subtask; never delegate a `humans-only` path
- **Sub-agents:** run `./scripts/verify-ci.sh` before reporting a subtask complete, regardless of AI provider
- **Headless agents:** read `clear/autonomy.yml` at startup; exit non-zero if verification fails — let CI catch it
- **MCP:** expose `verify-ci.sh` and `autonomy.yml` as MCP tools (`clear_verify`, `clear_check_autonomy`) for structured agent access

See [docs/agentic.md](../docs/agentic.md) for full patterns and the `templates/skills/mcp-server.md` skill to scaffold a CLEAR MCP server.

---

## Files in This Repository

| File | Purpose |
|------|---------|
| `clear/autonomy.yml` | Module autonomy boundaries + sources of truth |
| `clear/principles.md` | This file — AI quick reference |
| `scripts/verify-ci.sh` | Local CI/CD enforcement — CLEAR-owned, auto-updated |
| `scripts/verify-local.sh` | Project-specific checks — yours to edit |
| `scripts/setup-clear.sh` | Interactive setup wizard for new projects |
| `templates/architecture-tests/` | Generic architecture tests (autonomy guard) |
| `templates/examples/architecture-tests/` | Domain-specific test examples (API rules, type sync, module boundaries) |
| `templates/skills/` | Generic AI skills (MCP server, code review) |
| `templates/examples/skills/` | Domain-specific skill illustrations (copy and customize) |
| `templates/github-actions/` | CI/CD workflow templates |
| `templates/linting/` | ESLint config templates |
| `docs/` | Detailed documentation per principle and AI tool |
| `.github/copilot-instructions.md` | GitHub Copilot / VS Code workspace config |
| `CLAUDE.md` | Claude Code configuration (auto-read at startup) |
| `.cursor/rules/` | Cursor AI rules (MDC format) |
| `docs/agentic.md` | Multi-agent pipelines and MCP integration guide |
| `templates/skills/mcp-server.md` | Skill to scaffold a CLEAR MCP server |
