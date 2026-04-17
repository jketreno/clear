# Changelog

All notable changes to the CLEAR framework are documented here.

Format: [semantic version] — date — summary of changes.

---

## [Unreleased]

### Added
- `scripts/render-mermaid-assets.sh` — render Mermaid markdown diagrams with `beautiful-mermaid` to SVG and LinkedIn-ready PNG assets
- `.github/workflows/publish-mermaid-assets.yml` — workflow to generate and upload Mermaid publish artifacts
- `assets/diagrams/clear-overview.mmd` — source diagram for social image exports

### Changed
- `README.md` — added Mermaid asset publishing section with local and CI usage
- `scripts/render-mermaid-assets.sh` — removed Mermaid CLI support and switched to Beautiful-only rendering
- `.github/workflows/publish-mermaid-assets.yml` — removed dual-render branching and now publishes Beautiful-generated assets only

---

## [1.1.0] — 2025-04-14

### Added
- `scripts/update-project.sh` — sync a bootstrapped project with the latest CLEAR seed
- `docs/agentic.md` — guide for multi-agent pipelines and MCP integration
- `templates/skills/mcp-server.md` — skill template for scaffolding a CLEAR MCP server
- `LICENSE` (MIT) — explicit open-source license
- `CHANGELOG.md` — this file

### Changed
- `POST-engagement.md` — removed self-deprecating parenthetical, added LinkedIn plain-text version, added publishing-purpose header
- `README.md` — added `update-project.sh` to What's Included; added multi-agent/MCP to Learn More table; updated tagline to mention agentic workflows and MCP
- `docs/ai-tools/claude.md` — fixed outdated install command; added MCP integration section
- `docs/getting-started.md` — added `update-project.sh` usage note; added multi-agent pointer in What's Next table
- `clear/autonomy.yml` — added `docs/agentic.md` to supervised paths; extended sources of truth
- `clear/principles.md` — added agentic/MCP note to workflow summary

---

## [1.0.0] — 2025-04-01

### Initial release

- Five CLEAR principles: Constrained, Limited, Ephemeral, Assertive, Reality-Aligned
- `scripts/verify-ci.sh` — local CI/CD enforcement script with project auto-detection
- `scripts/setup-clear.sh` — interactive setup wizard
- `scripts/bootstrap-project.sh` — one-command bootstrap into existing projects
- `clear/autonomy.yml` — YAML autonomy boundary format
- `clear/principles.md` — AI quick-reference card
- Template configs for Claude Code, Cursor, GitHub Copilot, VS Code
- Template architecture tests, skill files, linting configs, GitHub Actions workflow
- Full documentation: getting-started, five principle deep dives, three AI tool guides
- `ORIGIN.md` — origin story and philosophy
