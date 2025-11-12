# Scripts Directory

Helper scripts for Singularity.Workflow library management.

## Development Setup

**Just use Nix:**
```bash
nix develop  # Everything is automatically configured
```

Nix provides:
- Elixir 1.19.x
- Erlang/OTP 28
- PostgreSQL 18 with pgmq extension (auto-starts/stops)
- All development tools (gh, tree, etc.)

## Available Scripts

### `bootstrap_deps.exs`

Offline dependency bootstrapping for CI environments.

**Usage:**
```bash
BOOTSTRAP_HEX_DEPS=1 mix run scripts/bootstrap_deps.exs
```

### `release.sh`

Creates a new release with version bumping and changelog updates.

**Usage:**
```bash
./scripts/release.sh <major|minor|patch>
```

### `release-checklist.sh`

Pre-release validation checklist.

**Usage:**
```bash
./scripts/release-checklist.sh
```

### `setup-github.sh`

Configure GitHub repository settings.

**Usage:**
```bash
./scripts/setup-github.sh
```

### `setup-github-protection.sh`

Set up branch protection rules for the repository.

**Usage:**
```bash
./scripts/setup-github-protection.sh
```

## Common Development Commands

All development is done through mix commands in the Nix shell:

```bash
# Enter Nix shell
nix develop

# Install dependencies
mix deps.get

# Run tests
mix test
mix test --watch

# Code quality
mix format
mix credo --strict
mix dialyzer

# Database
mix ecto.create
mix ecto.migrate
mix ecto.reset

# Generate docs
mix docs
```

No Makefile needed - use mix commands directly!
