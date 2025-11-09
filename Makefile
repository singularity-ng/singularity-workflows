.PHONY: help setup test quality clean docker-up docker-down

# Default target
help:
	@echo "ExPgflow Development Commands"
	@echo "=============================="
	@echo ""
	@echo "Setup:"
	@echo "  make setup          - Set up development environment (interactive)"
	@echo "  make setup-nix      - Set up using Nix"
	@echo "  make setup-docker   - Set up using Docker (PostgreSQL only)"
	@echo ""
	@echo "Development:"
	@echo "  make deps           - Install dependencies"
	@echo "  make compile        - Compile the project"
	@echo "  make test           - Run tests"
	@echo "  make test-watch     - Run tests in watch mode"
	@echo "  make quality        - Run all quality checks"
	@echo ""
	@echo "Database:"
	@echo "  make db-create      - Create database"
	@echo "  make db-migrate     - Run migrations"
	@echo "  make db-reset       - Reset database"
	@echo "  make db-shell       - Open PostgreSQL shell"
	@echo ""
	@echo "Docker:"
	@echo "  make docker-up      - Start PostgreSQL with Docker"
	@echo "  make docker-down    - Stop PostgreSQL"
	@echo "  make docker-logs    - View PostgreSQL logs"
	@echo "  make docker-reset   - Reset Docker environment"
	@echo ""
	@echo "Formatting & Linting:"
	@echo "  make format         - Format code"
	@echo "  make lint           - Run Credo linter"
	@echo "  make dialyzer       - Run Dialyzer type checker"
	@echo "  make security       - Run security checks"
	@echo ""
	@echo "Documentation:"
	@echo "  make docs           - Generate documentation"
	@echo "  make docs-open      - Generate and open documentation"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make clean-all      - Clean everything (including deps)"
	@echo ""

# Setup
setup:
	@./scripts/setup-dev-environment.sh

setup-nix:
	@./scripts/setup-dev-environment.sh --method nix

setup-docker:
	@./scripts/setup-dev-environment.sh --method docker

# Dependencies
deps:
	@echo "Installing dependencies..."
	@mix deps.get
	@echo "✓ Dependencies installed"

compile: deps
	@echo "Compiling project..."
	@mix compile
	@echo "✓ Compilation complete"

# Testing
test: compile
	@echo "Running tests..."
	@mix test

test-watch:
	@echo "Running tests in watch mode..."
	@mix test.watch

test-coverage:
	@echo "Generating test coverage report..."
	@mix coveralls.html
	@echo "✓ Coverage report generated at cover/excoveralls.html"

# Quality
quality:
	@echo "Running quality checks..."
	@mix quality

format:
	@echo "Formatting code..."
	@mix format
	@echo "✓ Code formatted"

lint:
	@echo "Running Credo linter..."
	@mix credo --strict

dialyzer:
	@echo "Running Dialyzer type checker..."
	@mix dialyzer

security:
	@echo "Running security checks..."
	@mix sobelow --exit-on-warning
	@mix deps.audit

# Database
db-create:
	@echo "Creating database..."
	@mix ecto.create
	@echo "✓ Database created"

db-migrate:
	@echo "Running migrations..."
	@mix ecto.migrate
	@echo "✓ Migrations complete"

db-reset:
	@echo "Resetting database..."
	@mix ecto.reset
	@echo "✓ Database reset"

db-shell:
	@echo "Opening PostgreSQL shell..."
	@psql $(DATABASE_URL)

# Docker
docker-up:
	@echo "Starting PostgreSQL with Docker..."
	@docker-compose up -d
	@echo "Waiting for PostgreSQL to be ready..."
	@sleep 3
	@docker-compose exec -T postgres pg_isready -U postgres || (echo "PostgreSQL not ready" && exit 1)
	@echo "✓ PostgreSQL is ready"
	@echo "Database URL: postgresql://postgres:postgres@localhost:5433/postgres"

docker-down:
	@echo "Stopping PostgreSQL..."
	@docker-compose down
	@echo "✓ PostgreSQL stopped"

docker-logs:
	@docker-compose logs -f

docker-reset:
	@echo "Resetting Docker environment..."
	@docker-compose down -v
	@echo "✓ Docker environment reset"

# Documentation
docs:
	@echo "Generating documentation..."
	@mix docs
	@echo "✓ Documentation generated at doc/index.html"

docs-open: docs
	@echo "Opening documentation..."
	@open doc/index.html || xdg-open doc/index.html || echo "Please open doc/index.html manually"

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@mix clean
	@echo "✓ Build artifacts cleaned"

clean-all: clean
	@echo "Cleaning dependencies..."
	@rm -rf deps _build
	@echo "✓ All artifacts cleaned"

# Development shell (Nix)
shell:
	@echo "Entering Nix development shell..."
	@nix develop

# Quick start (for first-time setup)
quickstart: setup deps db-create db-migrate test
	@echo ""
	@echo "=============================="
	@echo "✓ Setup complete!"
	@echo "=============================="
	@echo ""
	@echo "Next steps:"
	@echo "  - Run tests: make test"
	@echo "  - Check quality: make quality"
	@echo "  - Read docs: make docs-open"
	@echo ""
