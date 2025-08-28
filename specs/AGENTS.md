# Specs Maintenance

- Before committing any change to the `specs/` folder, run `just lint-specs` from the project root. This performs Markdown linting, link checking, spell checking, prose/style linting, and Mermaid diagram validation.
- The Nix dev shell is fully reproducible; if a required tool is missing inside the shell, fix `flake.nix` rather than using ad‑hoc fallbacks.

If the pre-commit hook blocks your commit, run `just lint-specs`, address the reported issues, and commit again.
