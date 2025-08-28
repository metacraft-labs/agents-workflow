# Run the test suite

test:
    ruby -Itest test/run_tests_shell.rb

# Lint the Ruby codebase
lint:
    rubocop

# Auto-fix lint issues where possible
lint-fix:
    rubocop --autocorrect-all

# Build and publish the gem
publish-gem:
    gem build agent-task.gemspec && gem push agent-task-*.gem

# Validate all JSON Schemas with ajv (meta-schema compile)
conf-schema-validate:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v ajv >/dev/null 2>&1; then
        AJV=ajv
    else
        echo "ajv not found; using npx ajv-cli (requires network)" >&2
        AJV='npx -y ajv-cli'
    fi
    for f in specs/schemas/*.json; do
        echo Validating $$f
        $$AJV compile -s "$$f"
    done
    echo All schemas valid.

# Check TOML files with Taplo (uses schema mapping if configured)
conf-schema-taplo-check:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v taplo >/dev/null 2>&1; then
        echo "taplo is not installed. Example to run once: nix shell ~/nixpkgs#taplo -c taplo check" >&2
        exit 127
    fi
    taplo check

# Serve schema docs locally with Docson (opens http://localhost:3000)
conf-schema-docs:
    docson -d specs/schemas

# Validate Mermaid diagrams in Markdown with mermaid-cli (mmdc)
md-mermaid-check:
    bash scripts/md-mermaid-validate.sh specs/**/*.md

# Lint Markdown structure/style in specs with markdownlint-cli2
md-lint:
    markdownlint-cli2 "specs/**/*.md"

# Check external links in Markdown with lychee
md-links:
    lychee --offline false --no-progress --require-https true --max-concurrency 8 "specs/**/*.md"

# Spell-check Markdown with cspell (uses default dictionaries unless configured)
md-spell:
    cspell "specs/**/*.md"
