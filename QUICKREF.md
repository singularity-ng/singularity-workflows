# ExPgflow Quick Reference

A quick reference guide for common ex_pgflow development tasks.

## Initial Setup

```bash
# Run setup script (choose your method)
./scripts/setup-dev-environment.sh

# Validate environment
make check

# Install dependencies
make deps

# Setup database
make db-create
make db-migrate

# Run tests
make test
```

## Daily Development

```bash
# Check environment is ready
make check

# Pull latest changes
git pull

# Update dependencies
make deps

# Run migrations
make db-migrate

# Run tests
make test

# Run tests in watch mode
make test-watch
```

## Quality Checks

```bash
# Run all quality checks
make quality

# Individual checks
make format      # Format code
make lint        # Credo linter
make dialyzer    # Type checking
make security    # Security scan
```

## Database Management

```bash
# Create database
make db-create

# Run migrations
make db-migrate

# Reset database (drops, creates, migrates)
make db-reset

# Open PostgreSQL shell
make db-shell
```

## Docker Commands

```bash
# Start PostgreSQL
make docker-up

# Stop PostgreSQL
make docker-down

# View logs
make docker-logs

# Reset (delete all data)
make docker-reset
```

## Common Tasks

### Running Tests

```bash
# All tests
make test

# Specific file
mix test test/pgflow/executor_test.exs

# Specific test
mix test test/pgflow/executor_test.exs:42

# With coverage
make test-coverage

# Watch mode (auto-rerun on changes)
make test-watch
```

### Code Formatting

```bash
# Check formatting
mix format --check-formatted

# Format all files
make format
```

### Type Checking

```bash
# Run Dialyzer
make dialyzer

# Clean and rebuild PLTs (if needed)
rm -rf priv/plts
make dialyzer
```

### Documentation

```bash
# Generate docs
make docs

# Generate and open in browser
make docs-open
```

## Troubleshooting

### Environment Issues

```bash
# Validate environment
make check

# Re-run setup
./scripts/setup-dev-environment.sh
```

### Database Issues

```bash
# Check PostgreSQL is running
pg_isready -h localhost

# Start PostgreSQL (Docker)
make docker-up

# Reset database
make db-reset
```

### Dependency Issues

```bash
# Clean and reinstall
make clean-all
make deps
make compile
```

### Test Failures

```bash
# Reset test database
MIX_ENV=test mix ecto.reset

# Run with detailed output
mix test --trace

# Run specific failing test
mix test path/to/test.exs:line_number
```

## Environment Variables

```bash
# Database URL
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/ex_pgflow"

# Test database
export TEST_DATABASE_URL="postgresql://postgres:postgres@localhost:5432/ex_pgflow_test"

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
make quality
make test

# Push to GitHub
git push origin feature/my-feature
```

## Nix Commands

```bash
# Enter Nix shell
nix develop

# Update Nix flake
nix flake update

# Exit Nix shell
exit
```

## Helpful Aliases

Add these to your `~/.bashrc` or `~/.zshrc`:

```bash
# ExPgflow aliases
alias pgf-test='make test'
alias pgf-check='make check'
alias pgf-quality='make quality'
alias pgf-format='make format'
alias pgf-db-reset='make db-reset'
```

## Resources

- **Setup Guide**: [SETUP.md](SETUP.md)
- **Getting Started**: [GETTING_STARTED.md](GETTING_STARTED.md)
- **Contributing**: [CONTRIBUTING.md](CONTRIBUTING.md)
- **Architecture**: [ARCHITECTURE.md](ARCHITECTURE.md)
- **Scripts Documentation**: [scripts/README.md](scripts/README.md)

## Getting Help

```bash
# View all available make commands
make help

# Check environment
make check

# View script help
./scripts/setup-dev-environment.sh --help
./scripts/check-environment.sh --help
```

## Common Error Solutions

### "pgmq extension not found"

```bash
# Use Docker with pgmq
make docker-up

# Or use Nix
nix develop
```

### "mix: command not found"

```bash
# Install Elixir
./scripts/setup-dev-environment.sh

# Or enter Nix shell
nix develop
```

### "Connection refused" (PostgreSQL)

```bash
# Start PostgreSQL
make docker-up

# Or check system PostgreSQL
sudo systemctl start postgresql  # Linux
brew services start postgresql   # macOS
```

### "Database does not exist"

```bash
make db-create
make db-migrate
```

---

**Tip**: Keep this file open in a terminal or editor for quick reference during development!
