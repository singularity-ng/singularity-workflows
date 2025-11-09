# Scripts Directory

This directory contains helper scripts for ex_pgflow development.

## Development Scripts

### `setup-dev-environment.sh`

Interactive script to set up your development environment. Supports three methods:

1. **Nix** (recommended) - Installs Elixir, Erlang, PostgreSQL with pgmq automatically
2. **Docker** - Runs PostgreSQL with pgmq in Docker (requires separate Elixir/Erlang installation)
3. **Native** - Guides you through manual installation of all dependencies

**Usage:**
```bash
# Interactive mode
./scripts/setup-dev-environment.sh

# Specify method
./scripts/setup-dev-environment.sh --method nix
./scripts/setup-dev-environment.sh --method docker
./scripts/setup-dev-environment.sh --method native
```

**Or via Makefile:**
```bash
make setup          # Interactive
make setup-nix      # Nix method
make setup-docker   # Docker method
```

### `check-environment.sh`

Validates your development environment setup. Checks:
- Elixir and Erlang installation
- PostgreSQL server status
- Database connectivity
- pgmq extension installation
- Project dependencies
- Compilation status

**Usage:**
```bash
./scripts/check-environment.sh

# Or via Makefile
make check
```

## GitHub Scripts

### `setup-github.sh`

Sets up GitHub repository settings (for maintainers).

### `setup-github-protection.sh`

Configures branch protection rules (for maintainers).

### `release-checklist.sh`

Release preparation checklist (for maintainers).

## Usage Examples

### First-Time Setup

```bash
# 1. Run setup script
./scripts/setup-dev-environment.sh

# 2. Verify setup
./scripts/check-environment.sh

# 3. Install dependencies
make deps

# 4. Create and migrate database
make db-create
make db-migrate

# 5. Run tests
make test
```

### Quick Environment Check

Before starting work each day:

```bash
# Check environment is ready
make check

# Start PostgreSQL if needed
make docker-up

# Run tests
make test
```

### Troubleshooting

If environment check fails:

```bash
# Re-run setup
./scripts/setup-dev-environment.sh

# Or manually fix specific issues
# See SETUP.md for detailed troubleshooting
```

## For More Information

- [SETUP.md](../SETUP.md) - Complete setup guide with troubleshooting
- [GETTING_STARTED.md](../GETTING_STARTED.md) - First workflow tutorial
- [CONTRIBUTING.md](../CONTRIBUTING.md) - Development guidelines
