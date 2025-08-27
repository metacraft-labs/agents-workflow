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
    set -euo pipefail
    for f in specs/schemas/*.json; do
        echo Validating $$f
        ajv compile -s "$$f"
    done
    echo All schemas valid.

# Check TOML files with Taplo (uses schema mapping if configured)
conf-schema-taplo-check:
    taplo check

# Serve schema docs locally with Docson (opens http://localhost:3000)
conf-schema-docs:
    docson -d specs/schemas
