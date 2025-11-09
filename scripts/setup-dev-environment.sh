#!/usr/bin/env bash

# ExPgflow Development Environment Setup Script
# 
# This script helps developers set up their local development environment
# for ex_pgflow. It supports multiple installation methods:
# 1. Nix (recommended)
# 2. Docker (PostgreSQL only)
# 3. Native installation (manual Elixir/Erlang setup)
#
# Usage: ./scripts/setup-dev-environment.sh [--method nix|docker|native]

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

# Parse command line arguments
INSTALL_METHOD=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --method)
            INSTALL_METHOD="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Detect or prompt for installation method
if [ -z "$INSTALL_METHOD" ]; then
    echo ""
    echo "ExPgflow Development Environment Setup"
    echo "======================================"
    echo ""
    echo "Choose your installation method:"
    echo "  1) Nix (recommended - includes Elixir, Erlang, PostgreSQL with pgmq)"
    echo "  2) Docker (PostgreSQL with pgmq only, requires Elixir/Erlang separately)"
    echo "  3) Native (manual installation of all dependencies)"
    echo ""
    read -p "Enter your choice (1-3): " choice
    
    case $choice in
        1) INSTALL_METHOD="nix" ;;
        2) INSTALL_METHOD="docker" ;;
        3) INSTALL_METHOD="native" ;;
        *)
            error "Invalid choice"
            exit 1
            ;;
    esac
fi

echo ""
info "Setting up ex_pgflow development environment using: $INSTALL_METHOD"
echo ""

# NIX INSTALLATION
if [ "$INSTALL_METHOD" = "nix" ]; then
    info "Setting up Nix development environment..."
    
    # Check if Nix is installed
    if ! command_exists nix; then
        warning "Nix is not installed. Installing Nix..."
        echo ""
        echo "This will install Nix with flakes support."
        read -p "Continue? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error "Installation cancelled"
            exit 1
        fi
        
        # Install Nix with flakes and nix-command enabled
        curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
        
        # Source Nix
        if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
            . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        fi
    else
        success "Nix is already installed"
    fi
    
    # Check if direnv is installed
    if ! command_exists direnv; then
        warning "direnv is not installed. Installing via nix..."
        nix-env -iA nixpkgs.direnv
        success "direnv installed"
        
        # Setup direnv hook
        echo ""
        info "Setting up direnv hook..."
        echo "Add this to your shell rc file (~/.bashrc, ~/.zshrc, etc.):"
        echo '  eval "$(direnv hook bash)"  # or zsh, fish, etc.'
        echo ""
    else
        success "direnv is already installed"
    fi
    
    # Allow direnv for this directory
    if [ -f .envrc ]; then
        info "Allowing direnv for this directory..."
        direnv allow .
        success "direnv allowed"
    fi
    
    # Enter Nix development shell
    info "Entering Nix development shell..."
    echo "Run: nix develop"
    echo ""
    success "Nix setup complete! Run 'nix develop' to enter the dev shell."

# DOCKER INSTALLATION
elif [ "$INSTALL_METHOD" = "docker" ]; then
    info "Setting up Docker environment for PostgreSQL..."
    
    # Check if Docker is installed
    if ! command_exists docker; then
        error "Docker is not installed. Please install Docker first:"
        echo "  https://docs.docker.com/get-docker/"
        exit 1
    fi
    success "Docker is installed"
    
    # Check if docker-compose is installed
    if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
        error "docker-compose is not installed. Please install docker-compose first:"
        echo "  https://docs.docker.com/compose/install/"
        exit 1
    fi
    success "docker-compose is installed"
    
    # Start PostgreSQL with pgmq
    info "Starting PostgreSQL with pgmq extension..."
    docker-compose up -d
    
    # Wait for PostgreSQL to be ready
    info "Waiting for PostgreSQL to be ready..."
    sleep 5
    until docker-compose exec -T postgres pg_isready -U postgres >/dev/null 2>&1; do
        echo -n "."
        sleep 1
    done
    echo ""
    success "PostgreSQL is ready (port 5433)"
    
    # Set environment variable
    export DATABASE_URL="postgresql://postgres:postgres@localhost:5433/postgres"
    echo ""
    info "Database URL: $DATABASE_URL"
    echo "Add this to your shell rc file:"
    echo '  export DATABASE_URL="postgresql://postgres:postgres@localhost:5433/postgres"'
    echo ""
    
    # Check for Elixir
    if ! command_exists elixir; then
        warning "Elixir is not installed. You need to install Elixir and Erlang."
        echo ""
        echo "Installation options:"
        echo "  - asdf: https://asdf-vm.com/"
        echo "  - Homebrew (macOS): brew install elixir"
        echo "  - apt (Ubuntu): sudo apt install elixir"
        echo ""
    else
        success "Elixir is installed: $(elixir --version | head -1)"
    fi

# NATIVE INSTALLATION
elif [ "$INSTALL_METHOD" = "native" ]; then
    info "Setting up native development environment..."
    echo ""
    warning "This method requires manual installation of dependencies."
    echo ""
    
    # Detect OS
    OS="unknown"
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        if [ -f /etc/debian_version ]; then
            OS="debian"
        elif [ -f /etc/redhat-release ]; then
            OS="redhat"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    fi
    
    info "Detected OS: $OS"
    echo ""
    
    # Check Elixir
    if ! command_exists elixir; then
        warning "Elixir is not installed"
        case $OS in
            debian)
                echo "Install with: sudo apt update && sudo apt install elixir erlang"
                ;;
            macos)
                echo "Install with: brew install elixir"
                ;;
            *)
                echo "Visit: https://elixir-lang.org/install.html"
                ;;
        esac
    else
        success "Elixir is installed: $(elixir --version | head -1)"
    fi
    
    # Check PostgreSQL
    if ! command_exists psql; then
        warning "PostgreSQL is not installed"
        case $OS in
            debian)
                echo "Install with: sudo apt update && sudo apt install postgresql postgresql-contrib"
                ;;
            macos)
                echo "Install with: brew install postgresql@18"
                ;;
            *)
                echo "Visit: https://www.postgresql.org/download/"
                ;;
        esac
    else
        success "PostgreSQL is installed: $(psql --version)"
    fi
    
    # Check if PostgreSQL is running
    if command_exists psql; then
        if pg_isready -h localhost >/dev/null 2>&1; then
            success "PostgreSQL is running"
            
            # Create database if needed
            info "Setting up database..."
            if ! psql -lqt | cut -d \| -f 1 | grep -qw ex_pgflow; then
                createdb ex_pgflow || warning "Could not create database (may already exist)"
            fi
            
            # Install pgmq extension
            info "Installing pgmq extension..."
            echo ""
            warning "pgmq extension needs to be installed manually:"
            echo "  1. Install pgmq from PGXN: https://github.com/tembo-io/pgmq"
            echo "  2. Or use Docker image: ghcr.io/pgmq/pg18-pgmq:latest"
            echo "  3. Or build from source"
            echo ""
            echo "After installation, run in psql:"
            echo "  CREATE EXTENSION IF NOT EXISTS pgmq;"
            echo ""
        else
            warning "PostgreSQL is not running. Start it with:"
            case $OS in
                debian)
                    echo "  sudo systemctl start postgresql"
                    ;;
                macos)
                    echo "  brew services start postgresql@18"
                    ;;
                *)
                    echo "  Check your PostgreSQL documentation"
                    ;;
            esac
        fi
    fi
    
    echo ""
    info "Set your database URL:"
    echo '  export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/ex_pgflow"'
fi

# Common setup steps (all methods)
echo ""
echo "======================================"
info "Running common setup steps..."
echo ""

# Install Elixir dependencies (if Elixir is available)
if command_exists mix; then
    info "Installing Elixir dependencies..."
    mix deps.get
    success "Dependencies installed"
    
    # Compile project
    info "Compiling project..."
    mix compile
    success "Project compiled"
    
    # Run migrations if database is available
    if [ -n "$DATABASE_URL" ] || command_exists psql; then
        info "Running database migrations..."
        mix ecto.create || true
        mix ecto.migrate || warning "Migrations failed - ensure PostgreSQL is running with pgmq extension"
    fi
else
    warning "mix command not found - skipping Elixir setup"
fi

echo ""
echo "======================================"
success "Setup complete!"
echo ""
info "Next steps:"
echo "  1. Verify setup: mix test"
echo "  2. Run quality checks: mix quality"
echo "  3. Start development!"
echo ""

if [ "$INSTALL_METHOD" = "nix" ]; then
    echo "Remember to enter the Nix shell: nix develop"
elif [ "$INSTALL_METHOD" = "docker" ]; then
    echo "Remember to set DATABASE_URL in your shell rc file"
fi

echo ""
info "For more information, see:"
echo "  - README.md"
echo "  - GETTING_STARTED.md"
echo "  - CONTRIBUTING.md"
echo ""
