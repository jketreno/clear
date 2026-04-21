---
name: autonomy-bootstrap
description: "Interviews the team and drafts clear/autonomy.yml boundaries plus sources_of_truth, then validates the configuration and setup follow-through steps."
mode: agent
---

# Bootstrap CLEAR Autonomy Configuration

> What this skill does: Guides the user through creating or refining clear/autonomy.yml so AI boundaries and sources of truth match the real project architecture.
> When to use: Use when adopting CLEAR in a new repository, reworking module boundaries, or tightening AI safety zones.
> Output: A proposed or updated clear/autonomy.yml plus a short checklist of follow-up setup actions.

---

## Context

CLEAR's Limited principle requires explicit autonomy boundaries per path.
CLEAR's Reality-Aligned principle requires sources_of_truth for important domain concepts.

The canonical source for both in a CLEAR project is clear/autonomy.yml.

---

## Instructions

When invoked, run this process.

### Step 1: Gather project structure and risk profile

1. Read the repository tree and identify major modules.
1. Ask the user which areas are high-risk or compliance-sensitive.
1. Ask which areas are safe for AI iteration and regeneration.

Classify candidate paths into:
- full-autonomy: low-risk utilities, generated code, repetitive glue code
- supervised: most application code requiring review
- humans-only: auth/payment/compliance/safety-critical logic

### Step 2: Draft module boundaries

Draft a modules section with specific path patterns and reasons.

Requirements:
- Use specific paths first, then end with a wildcard default.
- Include a human-readable reason for every entry.
- Keep ambiguous paths out of humans-only until confirmed.

Template:

```yaml
modules:
  - path: "src/generated"
    level: full-autonomy
    reason: "Generated artifacts are safe to regenerate"

  - path: "src/payments"
    level: humans-only
    reason: "Financial controls require manual authorship"

  - path: "src"
    level: supervised
    reason: "General product logic requires review"

  - path: "*"
    level: supervised
    reason: "Default: require human review"
```

### Step 3: Define sources of truth

Ask for 3-8 domain concepts that often cause drift.
For each concept, capture:
- concept
- source_of_truth
- defined_in
- optional note

Example:

```yaml
sources_of_truth:
  - concept: "User identity"
    source_of_truth: "Auth provider schema"
    defined_in: "infra/auth"
    note: "Provider claims win when app model differs"
```

### Step 4: Validate the configuration

Validate the draft before writing:
- Ensure wildcard path exists exactly once.
- Ensure levels are only full-autonomy, supervised, humans-only.
- Ensure no empty reasons.
- Ensure no duplicate concept names in sources_of_truth.

If constraints fail, fix and revalidate.

### Step 5: Write or propose updates

If user requests direct edits, write clear/autonomy.yml with:
- project name
- modules
- sources_of_truth

If user requests plan-only output, return a complete patch preview instead.

### Step 6: Provide setup follow-through checklist

After autonomy.yml is ready, recommend these CLEAR setup actions:
1. Confirm scripts/verify-local.sh contains project-specific checks.
1. Run ./scripts/verify-ci.sh and resolve failures.
1. Review humans-only boundaries with maintainers.
1. Optionally configure clear/extensions.yml for extra checks.
1. Install any needed prompt skills into .github/prompts/.

---

## Verification

Before marking complete:

1. Confirm clear/autonomy.yml parses as valid YAML.
1. Confirm every modules entry has path, level, and reason.
1. Confirm sources_of_truth entries are non-empty and actionable.
1. Run ./scripts/verify-ci.sh.

Do not report completion if verify-ci.sh fails.
