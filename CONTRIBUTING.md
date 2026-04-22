# Contributing to CLEAR

Thank you for your interest in CLEAR! This framework keeps architecture rules enforced — not suggested — when working with AI coding tools.

## Ways to Contribute

### Report Issues
- Bug reports: something in bootstrap, verify-ci, or setup doesn't work as expected
- Documentation gaps: unclear instructions, missing examples, broken links
- Feature requests: new principles, tool integrations, template ideas

### Share Your Experience
- Open a Discussion with your team's adoption story
- Share which principles had the most impact
- Suggest improvements to the autonomy boundary model

### Submit Pull Requests
1. Fork the repo and create a feature branch
2. Read `clear/autonomy.yml` — respect the autonomy boundaries
3. Run `./clear/verify-ci.sh` before submitting (the framework enforces its own rules)
4. Keep PRs focused — one change per PR

### Improve Templates
Templates in `install/clear/templates/` are `full-autonomy` — feel free to:
- Add architecture test templates for new languages/frameworks
- Create new skill files for common regeneration patterns
- Improve linting configs
- Add CI/CD templates for other providers (GitLab, Bitbucket, etc.)

### Improve Documentation
Docs are `supervised` — PRs welcome, but expect review before merge:
- Fix errors or unclear explanations in `docs/`
- Add examples from your own experience
- Translate documentation

## Development Setup

```bash
git clone https://github.com/jketreno/clear
cd clear
# The seed repo is self-contained — no dependencies to install
./clear/verify-ci.sh  # Verify everything passes
```

## Code of Conduct

Be respectful, constructive, and focused on making AI-assisted development better for everyone.

## Questions?

Open a GitHub Discussion — that's the best place for questions, ideas, and conversation.
