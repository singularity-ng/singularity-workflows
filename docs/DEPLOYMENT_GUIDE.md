# Singularity + Observer Deployment Guide

This guide covers deploying the complete Singularity system including the new Observer service and database.

## 🏗️ Architecture Overview

The complete system consists of:

- **Singularity** - Main Elixir application (port 4000)
- **Observer** - Phoenix web UI for monitoring (port 4000, separate database)
- **PostgreSQL** - Two databases:
  - `singularity` - Main application data
  - `observer_dev` - Observer UI data
- **pgmq** - Message queues for inter-service communication
- **pg_cron** - Scheduled tasks for CentralCloud sync

## 📋 Prerequisites

- **Nix** (recommended) or manual installation
- **PostgreSQL 17** with extensions:
  - `pgmq` - Message queues
  - `pg_cron` - Scheduled tasks
  - `pgvector` - Vector embeddings
  - `timescaledb` - Time-series data
- **Node.js/Bun** (for Observer frontend assets)

## 🚀 Quick Start (Nix)

### 1. Environment Setup

```bash
# Clone repository
git clone <repository-url>
cd singularity-incubation

# Enter Nix shell (starts PostgreSQL automatically)
nix develop

# Or with direnv (recommended)
direnv allow
```

### 2. Database Setup

```bash
# Setup both databases
./scripts/setup-database.sh

# This creates:
# - singularity database (main app)
# - observer_dev database (Observer UI)
# - All required extensions and tables
```

### 3. Start All Services

```bash
# Start everything (PostgreSQL, Singularity, Observer)
./start-all.sh

# Or individually:
# Terminal 1: Singularity
cd singularity
mix phx.server

# Terminal 2: Observer  
cd observer
mix phx.server

# Terminal 3: CentralCloud (optional)
cd centralcloud
mix phx.server
```

### 4. Access Services

- **Observer UI**: http://localhost:4000
- **Singularity API**: http://localhost:4000/api
- **CentralCloud**: http://localhost:4001 (if running)

## 🗄️ Database Configuration

### Singularity Database (`singularity`)

```elixir
# config/dev.exs
config :singularity, Singularity.Repo,
  username: "postgres",
  password: "postgres", 
  hostname: "localhost",
  database: "singularity",
  pool_size: 10
```

**Required Extensions:**
- `pgmq` - Message queues
- `pg_cron` - Scheduled tasks  
- `pgvector` - Vector embeddings
- `timescaledb` - Time-series data

### Observer Database (`observer_dev`)

```elixir
# observer/config/dev.exs
config :observer, Observer.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost", 
  database: "observer_dev",
  pool_size: 10
```

**Required Extensions:**
- `pgmq` - For HITL approvals

## 🔄 Message Queue Configuration

### Required Queues

```sql
-- Core application queues
SELECT pgmq.create('ai_requests');
SELECT pgmq.create('ai_results');
SELECT pgmq.create('embedding_requests');
SELECT pgmq.create('embedding_results');

-- Agent communication
SELECT pgmq.create('agent_messages');
SELECT pgmq.create('agent_responses');

-- Observer HITL
SELECT pgmq.create('observer_hitl_requests');

-- Genesis publishing
SELECT pgmq.create('genesis_rule_updates');

-- CentralCloud sync
SELECT pgmq.create('centralcloud_updates');
```

### Queue Management

```bash
# Check queue status
psql -d singularity -c "SELECT * FROM pgmq.metrics();"

# Monitor queue activity
psql -d singularity -c "SELECT * FROM pgmq.stats();"
```

## ⏰ Scheduled Tasks (pg_cron)

### CentralCloud Sync Schedule

```sql
-- Sync failure patterns every 2 hours
SELECT cron.schedule(
  'centralcloud-sync-failure-patterns',
  '0 */2 * * *',
  'SELECT Singularity.Storage.FailurePatternStore.sync_with_centralcloud();'
);

-- Sync validation metrics every hour
SELECT cron.schedule(
  'centralcloud-sync-validation-metrics', 
  '0 * * * *',
  'SELECT Singularity.Storage.ValidationMetricsStore.sync_with_centralcloud();'
);

-- Genesis v2: Publish learned rules every 6 hours
SELECT cron.schedule(
  'genesis-v2-publish-rules',
  '0 */6 * * *',
  'SELECT Singularity.Genesis.GenesisPublisher.publish_rules();'
);

-- Genesis v2: Import evolved rules every 4 hours
SELECT cron.schedule(
  'genesis-v2-import-rules',
  '0 */4 * * *',
  'SELECT Singularity.Genesis.GenesisPublisher.import_rules_from_genesis();'
);
```

### Database Maintenance

```sql
-- Daily vacuum and analyze (11 PM)
SELECT cron.schedule(
  'daily-vacuum-analyze',
  '0 23 * * *',
  'VACUUM ANALYZE; ANALYZE;'
);

-- Weekly cleanup (Sundays)
SELECT cron.schedule(
  'weekly-cleanup-oban-jobs',
  '0 0 * * 0', 
  'DELETE FROM oban_jobs WHERE state IN (''cancelled'', ''discarded'') AND updated_at < now() - interval ''30 days'';'
);
```

## 🔧 Configuration

### Environment Variables

```bash
# Required
DATABASE_URL="postgresql://postgres:postgres@localhost/singularity"
OBSERVER_DATABASE_URL="postgresql://postgres:postgres@localhost/observer_dev"

# Optional (for LLM providers)
ANTHROPIC_API_KEY="your_key_here"
OPENAI_API_KEY="your_key_here"
GEMINI_API_KEY="your_key_here"

# CentralCloud integration
CENTRALCLOUD_URL="http://localhost:4001"
CENTRALCLOUD_API_KEY="your_key_here"
```

### Observer Configuration

```elixir
# observer/config/config.exs
config :observer,
  database_url: System.get_env("OBSERVER_DATABASE_URL"),
  hitl_poll_interval: 1000,
  dev_routes: true

config :observer, ObserverWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  secret_key_base: "your_secret_key_here"
```

## 🧪 Testing

### Run All Tests

```bash
# Singularity tests
cd singularity
mix test

# Observer tests  
cd observer
mix test

# Integration tests
mix test --only integration

# Regression tests
mix test --only regression
```

### Test Database Setup

```bash
# Setup test databases
MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate

# Observer test database
cd observer
MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate
```

## 📊 Monitoring

### Observer Dashboards

Access real-time monitoring at http://localhost:4000:

- **System Health** - Overall system status
- **Validation Metrics Store** - Validation effectiveness KPIs
- **Failure Patterns** - Failure analysis and guardrails
- **Nexus Analytics** - LLM router performance
- **HITL Approvals** - Human-in-the-loop workflow

### Database Monitoring

```sql
-- Check pg_cron job status
SELECT * FROM cron.job;

-- Monitor queue metrics
SELECT * FROM pgmq.metrics();

-- Check database size
SELECT pg_size_pretty(pg_database_size('singularity'));
SELECT pg_size_pretty(pg_database_size('observer_dev'));
```

## 🚨 Troubleshooting

### Common Issues

**1. Observer can't connect to Singularity**
```bash
# Check if Singularity is running
curl http://localhost:4000/api/health

# Check database connections
psql -d singularity -c "SELECT 1;"
psql -d observer_dev -c "SELECT 1;"
```

**2. Message queues not working**
```bash
# Check pgmq extension
psql -d singularity -c "SELECT * FROM pg_extension WHERE extname = 'pgmq';"

# Check queue creation
psql -d singularity -c "SELECT * FROM pgmq.list_queues();"
```

**3. Scheduled tasks not running**
```bash
# Check pg_cron extension
psql -d singularity -c "SELECT * FROM pg_extension WHERE extname = 'pg_cron';"

# Check job status
psql -d singularity -c "SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;"
```

**4. Observer database errors**
```bash
# Reset Observer database
cd observer
mix ecto.drop
mix ecto.create
mix ecto.migrate
```

### Logs

```bash
# Singularity logs
tail -f singularity/log/dev.log

# Observer logs  
tail -f observer/log/dev.log

# PostgreSQL logs
tail -f /var/log/postgresql/postgresql-17-main.log
```

## 🔄 Updates and Maintenance

### Database Migrations

```bash
# Singularity migrations
cd singularity
mix ecto.migrate

# Observer migrations
cd observer  
mix ecto.migrate
```

### Code Updates

```bash
# Pull latest changes
git pull origin main

# Update dependencies
cd singularity && mix deps.get
cd observer && mix deps.get

# Recompile
cd singularity && mix compile
cd observer && mix compile

# Restart services
./stop-all.sh
./start-all.sh
```

### Backup and Recovery

```bash
# Backup databases
pg_dump singularity > singularity_backup.sql
pg_dump observer_dev > observer_backup.sql

# Restore databases
psql singularity < singularity_backup.sql
psql observer_dev < observer_backup.sql
```

## 🎯 Production Deployment

### NixOS (Recommended)

```bash
# Build complete system
nix build .#singularity-integrated

# Deploy to NixOS
sudo nixos-rebuild switch --flake .#your-hostname
```

### Docker (Alternative)

```dockerfile
# See docker-compose.yml for complete setup
docker-compose up -d
```

### Manual Deployment

1. Install PostgreSQL 17 with required extensions
2. Create databases and run migrations
3. Install Elixir 1.19 and dependencies
4. Configure environment variables
5. Start services with process manager (systemd, supervisor, etc.)

## 📚 Additional Resources

- [FINAL_PLAN.md](FINAL_PLAN.md) - Complete project roadmap
- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture details
- [TESTING_GUIDE.md](TESTING_GUIDE.md) - Testing strategies
- [CONTRIBUTING.md](CONTRIBUTING.md) - Development guidelines

## 🆘 Support

For issues and questions:

1. Check the troubleshooting section above
2. Review logs for error messages
3. Check database connectivity and queue status
4. Verify all required extensions are installed
5. Ensure proper environment variable configuration

The system is designed to be resilient and self-healing, but proper monitoring and maintenance are essential for optimal performance.