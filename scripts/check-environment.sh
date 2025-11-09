#!/usr/bin/env bash

# ExPgflow Environment Validation Script
#
# This script checks if your development environment is properly set up
# for ex_pgflow development.
#
# Usage: ./scripts/check-environment.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Track overall status
ISSUES_FOUND=0

echo ""
echo "ExPgflow Environment Validation"
echo "================================"
echo ""

# Check Elixir
info "Checking Elixir installation..."
if command_exists elixir; then
    VERSION=$(elixir --version 2>&1 | grep "Elixir" | awk '{print $2}')
    success "Elixir is installed: $VERSION"
    
    # Check version is 1.14+
    MAJOR=$(echo $VERSION | cut -d. -f1)
    MINOR=$(echo $VERSION | cut -d. -f2)
    if [ "$MAJOR" -ge 1 ] && [ "$MINOR" -ge 14 ]; then
        success "Elixir version is sufficient (>= 1.14)"
    else
        warning "Elixir version is below 1.14 - some features may not work"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    error "Elixir is not installed"
    echo "  Install with: ./scripts/setup-dev-environment.sh"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check Mix
echo ""
info "Checking Mix (Elixir build tool)..."
if command_exists mix; then
    success "Mix is installed"
else
    error "Mix is not installed (comes with Elixir)"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check Erlang
echo ""
info "Checking Erlang/OTP..."
if command_exists erl; then
    VERSION=$(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell 2>&1 | tr -d '"')
    success "Erlang/OTP is installed: $VERSION"
else
    error "Erlang/OTP is not installed"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check PostgreSQL
echo ""
info "Checking PostgreSQL..."
if command_exists psql; then
    VERSION=$(psql --version 2>&1 | awk '{print $3}')
    success "PostgreSQL client is installed: $VERSION"
else
    error "PostgreSQL client (psql) is not installed"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check if PostgreSQL is running
echo ""
info "Checking PostgreSQL server..."
if command_exists pg_isready; then
    if pg_isready -h localhost >/dev/null 2>&1; then
        success "PostgreSQL server is running on localhost"
    elif pg_isready -h localhost -p 5433 >/dev/null 2>&1; then
        success "PostgreSQL server is running on localhost:5433"
    else
        warning "PostgreSQL server is not running"
        echo "  Start with: docker-compose up -d  (or your system's PostgreSQL service)"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    warning "pg_isready not found, cannot check PostgreSQL status"
fi

# Check DATABASE_URL
echo ""
info "Checking DATABASE_URL environment variable..."
if [ -n "$DATABASE_URL" ]; then
    success "DATABASE_URL is set: $DATABASE_URL"
else
    warning "DATABASE_URL is not set"
    echo "  Set with: export DATABASE_URL=\"postgresql://postgres:postgres@localhost:5432/ex_pgflow\""
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check if database exists
echo ""
info "Checking if ex_pgflow database exists..."
if command_exists psql && [ -n "$DATABASE_URL" ]; then
    if psql "$DATABASE_URL" -c "SELECT 1" >/dev/null 2>&1; then
        success "Database is accessible"
        
        # Check for pgmq extension
        info "Checking for pgmq extension..."
        if psql "$DATABASE_URL" -c "SELECT extname FROM pg_extension WHERE extname = 'pgmq'" | grep -q pgmq; then
            success "pgmq extension is installed"
        else
            error "pgmq extension is not installed"
            echo "  Install with: psql $DATABASE_URL -c \"CREATE EXTENSION IF NOT EXISTS pgmq;\""
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    else
        warning "Cannot connect to database"
        echo "  Create with: mix ecto.create"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    warning "Cannot check database (psql not available or DATABASE_URL not set)"
fi

# Check dependencies
echo ""
info "Checking Elixir dependencies..."
if [ -d "deps" ]; then
    success "Dependencies directory exists"
else
    warning "Dependencies not installed"
    echo "  Install with: mix deps.get"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check if project compiles
echo ""
info "Checking if project compiles..."
if command_exists mix; then
    if mix compile --warnings-as-errors >/dev/null 2>&1; then
        success "Project compiles successfully"
    else
        warning "Project has compilation issues"
        echo "  Run: mix compile"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    warning "Cannot check compilation (mix not available)"
fi

# Check Docker (optional)
echo ""
info "Checking Docker (optional)..."
if command_exists docker; then
    VERSION=$(docker --version 2>&1 | awk '{print $3}' | tr -d ',')
    success "Docker is installed: $VERSION"
    
    # Check if docker-compose is available
    if command_exists docker-compose || docker compose version >/dev/null 2>&1; then
        success "docker-compose is available"
    else
        warning "docker-compose is not available"
        echo "  This is optional but useful for running PostgreSQL"
    fi
else
    warning "Docker is not installed (optional)"
    echo "  This is optional but useful for running PostgreSQL"
fi

# Check Nix (optional)
echo ""
info "Checking Nix (optional)..."
if command_exists nix; then
    VERSION=$(nix --version 2>&1 | awk '{print $3}')
    success "Nix is installed: $VERSION"
else
    warning "Nix is not installed (optional but recommended)"
    echo "  Install with: ./scripts/setup-dev-environment.sh --method nix"
fi

# Check direnv (optional)
echo ""
info "Checking direnv (optional)..."
if command_exists direnv; then
    success "direnv is installed"
else
    warning "direnv is not installed (optional but convenient with Nix)"
    echo "  Install with: nix-env -iA nixpkgs.direnv"
fi

# Summary
echo ""
echo "================================"
if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo "Your environment is ready for development."
    echo ""
    echo "Next steps:"
    echo "  - Run tests: mix test"
    echo "  - Run quality checks: mix quality"
    echo "  - Start developing!"
else
    echo -e "${YELLOW}⚠ Found $ISSUES_FOUND issue(s)${NC}"
    echo ""
    echo "Please address the issues above."
    echo ""
    echo "Quick fixes:"
    echo "  - Setup environment: ./scripts/setup-dev-environment.sh"
    echo "  - Install dependencies: mix deps.get"
    echo "  - Create database: mix ecto.create"
    echo "  - Run migrations: mix ecto.migrate"
    echo ""
    echo "For detailed help, see:"
    echo "  - SETUP.md"
    echo "  - GETTING_STARTED.md"
    exit 1
fi

echo ""
