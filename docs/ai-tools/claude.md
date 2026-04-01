# Claude Code Setup Guide

> CLEAR configures Claude Code through `CLAUDE.md` (auto-read at session start) and custom slash commands in `.claude/commands/`.

---

## Prerequisites

- Claude Code installed (`npm install -g @anthropic-ai/claude-code` or equivalent)
- CLEAR files copied into your project (see [docs/getting-started.md](../getting-started.md))

---

## How CLEAR Configures Claude Code

### Primary: `CLAUDE.md`

Claude Code automatically reads `CLAUDE.md` from the project root at the start of every session — no configuration required. This file contains:

- The verify-ci.sh requirement (non-negotiable)
- Autonomy boundary checking instructions
- Testing standards
- PLAN mode guidance
- Available bash commands

**Verify it's working:** Start a Claude Code session and ask "What are your instructions for this project?" — it should mention CLEAR, autonomy.yml, and verify-ci.sh.

### Hierarchical CLAUDE.md (optional)

Claude Code also reads `CLAUDE.md` from subdirectories when you're working in them. You can add subdirectory-specific instructions:

```markdown
<!-- src/api/CLAUDE.md -->
# API Module Instructions

All endpoints in this directory are in the `supervised` autonomy zone.
Always follow templates/skills/api-endpoint.md when creating new endpoints.
Every endpoint must pass the architecture test in tests/architecture/api-rules.test.js.
```

This is especially useful for communicating module-specific skills to Claude.

---

## Custom Slash Commands

CLEAR adds three custom commands to `.claude/commands/`:

### `/project:verify`

Runs `verify-ci.sh` and returns a structured report.

```bash
# In Claude Code:
/project:verify
```

Output format:
```
## Verify CI Results

Status: ✅ PASSED / ❌ FAILED

### Failing Checks
- **ESLint**: 'console' is not allowed (src/api/users.ts:42)
  Fix: Remove console.log or replace with logger.debug()

### Next Step
Shall I fix these issues and run verify again?
```

### `/project:check-autonomy [path]`

Looks up the autonomy level for a file path:

```bash
/project:check-autonomy src/payment/processor.ts
```

Output:
```
## Autonomy Check: src/payment/processor.ts

Matched rule: src/payment
Level: humans-only
Reason: Money movement; AI errors are financial risk

What this means:
I won't generate code in this path. Please make this change yourself.
If the boundary has changed, run /project:update-autonomy to update autonomy.yml.
```

### `/project:update-autonomy`

Guides you through updating `clear/autonomy.yml` with a new or modified boundary.

---

## Recommended Workflow with Claude Code

### PLAN mode for new features

```
You: Before implementing, show me the plan for adding user registration.

Claude:
## Plan

**Files to create/modify:**
- src/api/routes/auth.ts — new registration endpoint (supervised)
- src/services/user.service.ts — createUser method (supervised)
- tests/api/auth.test.ts — constraint tests (full-autonomy)

**Autonomy levels:**
- src/api/ → supervised (from clear/autonomy.yml)

**Tests to add:**
- 'never allows duplicate email registration' (property-based)
- 'always validates email format' (invariant)
- 'rate limiter blocks after 10 requests' (constraint)

**Source of truth:**
- User concept derives from database schema (clear/autonomy.yml)

Proceed with implementation?

You: Yes.

Claude: [generates code, runs verify-ci.sh, reports completion]
```

### Session startup best practice

Claude Code automatically reads CLAUDE.md, but you can reinforce the context at session start:

```
You: Read clear/autonomy.yml and summarize the current 
     module boundaries before we start.
```

This is especially useful for long sessions where you're touching multiple modules.

---

## Adding Skills to Claude

### Option 1: Reference from CLAUDE.md

For project-wide skills, add a reference in your `CLAUDE.md`:

```markdown
## Skills

When generating TypeScript types from Python models, follow:
`templates/skills/type-sync.md`

When the user says "update the protos", follow:
`templates/skills/proto-visualization.md`

When creating a new API endpoint, follow:
`templates/skills/api-endpoint.md`
```

Claude will read the skill file when it's relevant.

### Option 2: Custom command per skill

For skills that are invoked explicitly, create a `.claude/commands/` file:

```markdown
<!-- .claude/commands/sync-types.md -->
# /project:sync-types

When invoked, follow templates/skills/type-sync.md exactly to regenerate
TypeScript types from the Python Pydantic models in backend/models/api/.

After regenerating, run ./scripts/verify-ci.sh to verify the type
compatibility test passes.
```

Then use it as:
```
/project:sync-types
```

---

## Troubleshooting

**Claude ignores CLAUDE.md:**
- Ensure `CLAUDE.md` is in the project root (not a subdirectory, unless intentional)
- Ask: "What does CLAUDE.md say about verify-ci.sh?" to test if it was read
- Restart the Claude Code session

**Claude doesn't check autonomy.yml:**
- Reference autonomy.yml explicitly: "Check clear/autonomy.yml before modifying anything"
- The architecture test in `autonomy-guard.test.js` provides mechanical enforcement

**Custom commands not found:**
- Verify `.claude/commands/*.md` files exist
- Commands are discovered by their filename: `verify.md` → `/project:verify`
- Restart Claude Code session after adding new commands

**verify-ci.sh operation fails:**
- Claude needs permission to run terminal commands
- If working in restricted mode: manually run `./scripts/verify-ci.sh` and paste the output to Claude
