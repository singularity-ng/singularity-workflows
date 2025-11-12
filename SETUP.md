# Singularity.Workflow Setup Guide

Simple setup guide for Singularity.Workflow library development.

## Prerequisites

- [Nix package manager](https://nixos.org/download.html) installed
- Git

## Setup (One Command!)

```bash
# Clone repository
git clone https://github.com/Singularity-ng/singularity-workflows.git
cd singularity-workflows

# Enter Nix shell
nix develop
```

That's it! Nix automatically provides:
- Elixir 1.19.x
- Erlang/OTP 28
- PostgreSQL 18 with pgmq extension
- All development tools (gh, tree, etc.)
- PostgreSQL auto-starts and auto-stops with the shell

## First Steps

### 1. Install Dependencies

```bash
mix deps.get
```

### 2. Setup Database

```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate
```

### 3. Verify Installation

```bash
# Run tests
mix test

# Should see all tests passing
```

### 4. Run Quality Checks

```bash
# Format code
mix format

# Lint code
mix credo --strict

# Type checking
mix dialyzer

# Or run all checks at once
mix quality
```

## Development Workflow

```bash
# 1. Enter Nix shell (if not already)
nix develop

# 2. Pull latest changes
git pull

# 3. Update dependencies
mix deps.get

# 4. Run migrations
mix ecto.migrate

# 5. Run tests
mix test

# 6. Make your changes...

# 7. Run quality checks before committing
mix quality
mix test
```

## Installing Nix

If you don't have Nix installed:

### Linux / macOS

```bash
# Install Nix (official installer)
sh <(curl -L https://nixos.org/nix/install) --daemon

# Or use determinate systems installer (recommended)
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

### Enable Flakes

Add to `~/.config/nix/nix.conf` or `/etc/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

## Troubleshooting

### Nix not found

**Error:** `nix: command not found`

**Solution:**
```bash
# Install Nix
sh <(curl -L https://nixos.org/nix/install) --daemon

# Reload shell
source ~/.bashrc  # or ~/.zshrc
```

### Flakes not enabled

**Error:** `error: experimental Nix feature 'flakes' is disabled`

**Solution:**
```bash
# Enable flakes
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

### PostgreSQL connection issues

**Error:** `Connection refused` or `could not connect to server`

**Solution:**
```bash
# Exit and re-enter Nix shell
exit
nix develop

# PostgreSQL should start automatically
# Wait a few seconds for it to be ready
```

### pgmq extension not found

**Error:** `ERROR: extension "pgmq" is not available`

**Solution:**
```bash
# Use Nix (includes pgmq automatically)
nix develop

# Verify pgmq is available
psql $DATABASE_URL -c "CREATE EXTENSION IF NOT EXISTS pgmq;"
```

### Mix dependencies won't compile

**Error:** Compilation errors or dependency conflicts

**Solution:**
```bash
# Clean and reinstall
mix deps.clean --all
rm -rf _build deps
mix deps.get
mix compile
```

## Common Commands Reference

```bash
# Database operations
mix ecto.create              # Create database
mix ecto.migrate             # Run migrations
mix ecto.rollback            # Rollback last migration
mix ecto.reset               # Drop, create, and migrate
psql $DATABASE_URL           # PostgreSQL shell

# Testing
mix test                     # Run all tests
mix test --watch             # Watch mode
mix test path/to/test.exs    # Run specific test file
mix coveralls.html           # Generate coverage report

# Code quality
mix format                   # Format code
mix credo --strict           # Lint code
mix dialyzer                 # Type checking
mix sobelow                  # Security scan
mix quality                  # Run all checks

# Documentation
mix docs                     # Generate documentation

# Nix
nix develop                  # Enter dev shell
nix flake update             # Update dependencies
exit                         # Exit shell (stops PostgreSQL)
```

## direnv Integration (Optional)

For automatic environment loading:

```bash
# Install direnv
nix-env -i direnv

# Add to ~/.bashrc or ~/.zshrc
eval "$(direnv hook bash)"  # or zsh

# Allow in project directory
cd singularity-workflows
direnv allow

# Now automatically enters Nix shell when cd'ing into directory
```

## Additional Resources

- [Nix Documentation](https://nixos.org/manual/nix/stable/)
- [Elixir Documentation](https://elixir-lang.org/docs.html)
- [Phoenix Framework](https://phoenixframework.org/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

## Getting Help

- Check [QUICKREF.md](QUICKREF.md) for quick command reference
- Read [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines
- See [docs/](docs/) for comprehensive documentation
- Open an issue on GitHub for bugs or questions

---

**Remember:** Just `nix develop` and you're ready to code! 🚀
