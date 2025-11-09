# Development Environment Setup Guide

This guide provides comprehensive instructions for setting up your ex_pgflow development environment. Choose the method that best fits your workflow.

## Quick Setup (Recommended)

The easiest way to get started:

```bash
./scripts/setup-dev-environment.sh
```

This interactive script will guide you through the setup process.

## Setup Methods

### Method 1: Nix (Recommended) ⭐

**Benefits:**
- All dependencies managed automatically (Elixir 1.19, Erlang, PostgreSQL 18, pgmq)
- Reproducible environment across all platforms
- Zero version conflicts
- Auto-starts PostgreSQL in dev shell

**Prerequisites:**
- None! The setup script will install Nix for you

**Setup:**

1. Run the setup script:
   ```bash
   ./scripts/setup-dev-environment.sh --method nix
   ```

2. Or manually install Nix with flakes support:
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
   ```

3. Enter the development shell:
   ```bash
   nix develop
   ```

4. Alternatively, use direnv for automatic environment loading:
   ```bash
   # Install direnv
   nix-env -iA nixpkgs.direnv
   
   # Add to your shell rc file (~/.bashrc, ~/.zshrc, etc.)
   eval "$(direnv hook bash)"  # or zsh, fish, etc.
   
   # Allow direnv for this project
   direnv allow
   
   # Now the environment loads automatically when you cd into the directory!
   ```

**What you get:**
- Elixir 1.19.x
- Erlang/OTP 28
- PostgreSQL 18 with pgmq extension
- All build tools (mix, rebar3, etc.)
- PostgreSQL auto-starts and auto-stops with the shell

### Method 2: Docker (PostgreSQL Only)

**Benefits:**
- Isolated PostgreSQL environment
- No PostgreSQL installation needed on host
- Easy to reset/clean

**Prerequisites:**
- Docker and docker-compose installed
- Elixir and Erlang installed separately (see Method 3)

**Setup:**

1. Start PostgreSQL with pgmq:
   ```bash
   docker-compose up -d
   ```

2. Verify PostgreSQL is running:
   ```bash
   docker-compose ps
   ```

3. Set database URL:
   ```bash
   export DATABASE_URL="postgresql://postgres:postgres@localhost:5433/postgres"
   ```

4. Add to your shell rc file to persist:
   ```bash
   echo 'export DATABASE_URL="postgresql://postgres:postgres@localhost:5433/postgres"' >> ~/.bashrc
   ```

**Managing Docker:**
```bash
# Start PostgreSQL
docker-compose up -d

# Stop PostgreSQL
docker-compose down

# View logs
docker-compose logs -f

# Reset database (delete all data)
docker-compose down -v
```

**Note:** You still need to install Elixir and Erlang separately (see Method 3).

### Method 3: Native Installation

**Benefits:**
- No additional tools required
- Direct access to all components
- Full control over versions

**Prerequisites:**
- Package manager (apt, brew, dnf, etc.)

#### Install Elixir and Erlang

**macOS (using Homebrew):**
```bash
brew install elixir
```

**Ubuntu/Debian:**
```bash
# Add Erlang Solutions repository
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt update

# Install Elixir and Erlang
sudo apt install elixir erlang
```

**Using asdf (version manager - recommended for multiple projects):**
```bash
# Install asdf
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0

# Add to your shell rc file
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc

# Install plugins
asdf plugin add erlang
asdf plugin add elixir

# Install versions
asdf install erlang 27.0
asdf install elixir 1.17.0-otp-27

# Set versions for this project
asdf local erlang 27.0
asdf local elixir 1.17.0-otp-27
```

#### Install PostgreSQL

**macOS (using Homebrew):**
```bash
brew install postgresql@18
brew services start postgresql@18
```

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo systemctl start postgresql
```

#### Install pgmq Extension

**Option A: Using Docker image (easiest)**
```bash
docker run -d --name pgmq-postgres \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  ghcr.io/pgmq/pg18-pgmq:latest
```

**Option B: Build from source**
```bash
git clone https://github.com/tembo-io/pgmq.git
cd pgmq
make install
```

**Option C: Using PGXN**
```bash
pgxn install pgmq
```

#### Setup Database

```bash
# Create database
createdb ex_pgflow

# Install pgmq extension
psql ex_pgflow -c "CREATE EXTENSION IF NOT EXISTS pgmq;"

# Set environment variable
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/ex_pgflow"
```

## Common Setup Steps (All Methods)

After choosing your installation method, run these steps:

### 1. Install Dependencies

```bash
mix deps.get
```

### 2. Setup Database

```bash
# Create database (if not exists)
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

# Run linter
mix credo

# Type checking
mix dialyzer

# Security analysis
mix sobelow
```

## Verification Checklist

Ensure your environment is properly set up:

- [ ] Elixir installed (`elixir --version` shows 1.14+)
- [ ] Mix available (`mix --version`)
- [ ] PostgreSQL running (`pg_isready -h localhost`)
- [ ] pgmq extension installed (check in psql: `\dx pgmq`)
- [ ] Database created (`psql ex_pgflow -c "SELECT 1"`)
- [ ] Dependencies installed (`mix deps.get` completes)
- [ ] Tests pass (`mix test` all green)
- [ ] Code compiles (`mix compile` no errors)

## Troubleshooting

### Elixir not found

**Solution:**
```bash
# Check if Elixir is in PATH
which elixir

# If using Nix, ensure you're in the dev shell
nix develop

# If using asdf, ensure versions are set
asdf current
```

### PostgreSQL connection failed

**Solution:**
```bash
# Check if PostgreSQL is running
pg_isready -h localhost

# Start PostgreSQL
# macOS: brew services start postgresql@18
# Linux: sudo systemctl start postgresql

# Check DATABASE_URL is set
echo $DATABASE_URL

# Test connection
psql $DATABASE_URL -c "SELECT 1"
```

### pgmq extension not found

**Error:** `ERROR: extension "pgmq" is not available`

**Solution:**
```bash
# Option 1: Use Docker with pre-installed pgmq
docker run -d --name pgmq-postgres \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  ghcr.io/pgmq/pg18-pgmq:latest

# Option 2: Install pgmq manually
# Follow instructions at: https://github.com/tembo-io/pgmq

# Option 3: Use Nix (includes everything)
nix develop
```

### Mix dependencies won't compile

**Solution:**
```bash
# Clean build artifacts
mix deps.clean --all
mix clean

# Rebuild
mix deps.get
mix compile
```

### Dialyzer taking too long

**Solution:**
```bash
# Dialyzer builds PLTs on first run (can take 10+ minutes)
# Subsequent runs are much faster

# Clean and rebuild PLTs if needed
rm -rf priv/plts
mix dialyzer
```

### Tests failing

**Solution:**
```bash
# Ensure PostgreSQL is running
pg_isready -h localhost

# Reset test database
MIX_ENV=test mix ecto.reset

# Run tests again
mix test

# Run tests with detailed output
mix test --trace
```

## Environment Variables

Key environment variables for development:

```bash
# Database connection
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/ex_pgflow"

# Test database (optional, defaults to ex_pgflow_test)
export TEST_DATABASE_URL="postgresql://postgres:postgres@localhost:5432/ex_pgflow_test"

# Mix environment
export MIX_ENV=dev  # or test, prod

# Elixir/Erlang paths (usually set automatically)
export ERL_AFLAGS="-kernel shell_history enabled"
```

## IDE Setup

### VS Code

Recommended extensions:
```json
{
  "recommendations": [
    "jakebecker.elixir-ls",
    "pantajoe.vscode-elixir-credo",
    "direnv.direnv"
  ]
}
```

### Emacs

Use `alchemist` or `lsp-mode` with `elixir-ls`.

### Vim/Neovim

Use `vim-elixir` with `coc-elixir` or `nvim-lspconfig` with `elixir-ls`.

## Next Steps

Once your environment is set up:

1. Read [GETTING_STARTED.md](GETTING_STARTED.md) for your first workflow
2. Review [ARCHITECTURE.md](ARCHITECTURE.md) for technical details
3. Check [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines
4. Start coding! 🚀

## Getting Help

- **Issues with setup?** Open a GitHub issue with the "question" label
- **Documentation unclear?** Submit a PR with improvements
- **Need help?** Check existing issues or discussions

## Quick Reference

```bash
# Development workflow
mix test                    # Run tests
mix test.watch              # Auto-run tests on file changes
mix quality                 # Run all quality checks
mix format                  # Format code
mix credo --strict          # Lint code
mix dialyzer                # Type check
mix docs                    # Generate documentation

# Database management
mix ecto.create             # Create database
mix ecto.migrate            # Run migrations
mix ecto.rollback           # Rollback last migration
mix ecto.reset              # Drop, create, and migrate

# Docker (if using docker-compose)
docker-compose up -d        # Start PostgreSQL
docker-compose down         # Stop PostgreSQL
docker-compose logs -f      # View logs

# Nix (if using Nix)
nix develop                 # Enter dev shell
direnv allow                # Allow auto-loading
```
