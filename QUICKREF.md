# Singularity.Workflow Quick Reference

Quick reference for Singularity.Workflow library development.

## Setup

```bash
# Enter Nix development shell (everything auto-configured)
nix develop

# That's it! PostgreSQL starts automatically with pgmq extension
```

## Development Commands

### Install Dependencies
```bash
mix deps.get
mix deps.compile
```

### Database
```bash
mix ecto.create
mix ecto.migrate
mix ecto.reset
psql $DATABASE_URL  # Open PostgreSQL shell
```

### Testing
```bash
# Run all tests
mix test

# Watch mode
mix test --watch

# Specific file
mix test test/singularity_workflow/executor_test.exs

# Specific test
mix test test/singularity_workflow/executor_test.exs:42

# With coverage
mix coveralls.html
```

### Code Quality
```bash
# Format code
mix format

# Lint
mix credo --strict

# Type check
mix dialyzer

# Security scan
mix sobelow --exit-on-warning

# All quality checks
mix quality
```

### Documentation
```bash
# Generate docs
mix docs

# Open in browser
open doc/index.html  # macOS
xdg-open doc/index.html  # Linux
```

## Environment Variables

```bash
# Database URL (auto-set by Nix)
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/singularity_workflow"

# Test database
export TEST_DATABASE_URL="postgresql://postgres:postgres@localhost:5432/singularity_workflow_test"

# Mix environment
export MIX_ENV=dev  # or test, prod
```

## Git Workflow

```bash
# Create feature branch
git checkout -b feature/my-feature

# Make changes and commit
git add .
git commit -m "feat: add new feature"

# Run quality checks before pushing
mix quality
mix test

# Push to GitHub
git push origin feature/my-feature
```

## Nix Commands

```bash
# Enter Nix shell (auto-starts PostgreSQL)
nix develop

# Update Nix flake
nix flake update

# Exit Nix shell (auto-stops PostgreSQL)
exit
```

## Helpful Aliases

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# Singularity.Workflow aliases
alias sw='nix develop'
alias sw-test='mix test'
alias sw-quality='mix quality'
alias sw-format='mix format'
```

## Resources

- **Setup Guide**: [SETUP.md](SETUP.md)
- **Contributing**: [CONTRIBUTING.md](CONTRIBUTING.md)
- **Architecture**: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- **Scripts**: [scripts/README.md](scripts/README.md)

## Common Issues

### "pgmq extension not found"
```bash
nix develop  # Includes PostgreSQL with pgmq
```

### "mix: command not found"
```bash
nix develop  # Includes Elixir
```

### "Connection refused" (PostgreSQL)
```bash
nix develop  # Auto-starts PostgreSQL
```

### "Database does not exist"
```bash
mix ecto.create
mix ecto.migrate
```

---

**Tip**: Just use `nix develop` and everything works! 🎯
