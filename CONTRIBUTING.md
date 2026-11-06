# Contributing

Floating Brain is an experimental personal project. The project license has not yet been selected. Please resolve licensing with the maintainer before submitting code intended for redistribution. Third-party licenses are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Development workflow

Use a focused branch and keep changes small enough to review. For substantial product or architecture changes, describe the problem and proposed behavior in an issue first. The design/specification documents include future ideas; check the implementation and existing tests before treating those ideas as requirements.

From the repository root:

```bash
npm ci --prefix floating
python3 scripts/check.py
```

The checks require Python 3.12+ and Node.js 22.13+. `python3 scripts/check.py --python-only` runs the Python and configuration checks without Node. iOS tests require macOS/Xcode; SAM validation requires the SAM CLI or the validator used by CI. See [README.md](README.md) and [scripts/README.md](scripts/README.md).

For behavior changes, add a regression test that exercises the observable behavior, especially user partition isolation, authorization, sync reconciliation, and local cache handling. Documentation-only changes should be checked for accurate paths, commands, and links.

## Configuration and test data

- Use synthetic reminder text, fake phone numbers, and disposable development accounts in examples and tests.
- Keep `.env`, local Xcode configuration, AWS profiles, tokens, signing material, SQLite databases, and deployment state out of commits. Edit examples with placeholders instead.
- Follow [floating/AGENTS.md](floating/AGENTS.md) when working in the messaging companion; automated agents must not read, write, or echo its `.env` file.
- Local tests should not send messages, change live reminders, or deploy infrastructure. Run any integration smoke test deliberately against your own development resources.
- Check both the diff and the files staged for commit. Removing a secret from a later commit does not remove it from history.

## Pull requests

Explain the problem, the resulting behavior, and how you verified it. Note platform checks you could not run and any configuration or migration required. Include screenshots for visible UI changes, using synthetic content. Keep generated build output and personal deployment details out of the pull request.

Report suspected vulnerabilities privately as described in [SECURITY.md](SECURITY.md), rather than in a public issue.
