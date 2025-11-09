# Multi-Orchestrator Global Redundancy Guide

**Status:** Production-Ready Architecture
**Package:** singularity_workflow v0.1.5+

---

## Overview

Singularity.Workflow is designed for **globally redundant, multi-orchestrator deployments** across multiple regions/datacenters. The architecture is **already multi-orchestrator ready** - this guide shows how to deploy it for high availability.

---

## Architecture Patterns

### Pattern 1: Active-Active Multi-Region

```
┌─────────────────────────────────────────────────────────────┐
│                    Region: US-EAST                          │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐   │
│  │ Orchestrator │  │ Orchestrator │  │ Orchestrator    │   │
│  │  Instance 1  │  │  Instance 2  │  │  Instance 3     │   │
│  └──────┬───────┘  └──────┬───────┘  └────────┬────────┘   │
│         │                 │                    │            │
│         └─────────────────┴────────────────────┘            │
│                           │                                 │
│                    ┌──────▼────────┐                        │
│                    │  PostgreSQL   │◄────────┐              │
│                    │  Primary      │         │              │
│                    │  + pgmq       │         │ Replication  │
│                    └───────────────┘         │              │
└─────────────────────────────────────────────┼──────────────┘
                                              │
┌─────────────────────────────────────────────┼──────────────┐
│                    Region: EU-WEST          │              │
│  ┌──────────────┐  ┌──────────────┐  ┌─────▼─────────┐    │
│  │ Orchestrator │  │ Orchestrator │  │ PostgreSQL    │    │
│  │  Instance 4  │  │  Instance 5  │  │ Read Replica  │    │
│  └──────┬───────┘  └──────┬───────┘  └───────────────┘    │
│         │                 │                                │
│         └─────────────────┴────────────────┘               │
│                           │                                │
│                    (Reads from replica)                    │
└────────────────────────────────────────────────────────────┘

Benefits:
- All regions can execute workflows
- Read replicas reduce latency for status queries
- Automatic failover to replica if primary fails
- Horizontal scaling within each region
```

---

## Current Multi-Orchestrator Capabilities

### ✅ Already Built

1. **Stateless Orchestrators**
   - All state in PostgreSQL (`workflow_runs`, `step_states`, `step_tasks`)
   - No local state, no sticky sessions
   - Any orchestrator can process any workflow

2. **PostgreSQL Coordination**
   - Counter-based with ACID guarantees
   - Row-level locking on task claims
   - `start_tasks()` PostgreSQL function handles concurrency

3. **Worker Heartbeats**
   - `workflow_workers` table tracks all workers
   - `last_heartbeat_at` for liveness detection
   - Automatic cleanup of stale workers

4. **Idempotency**
   - `idempotency_key` on all tasks
   - Prevents duplicate execution
   - Safe for at-least-once delivery

5. **Tenant Isolation**
   - `tenant_id` on all tables
   - Ready for tenant-aware routing

---

## Deployment Configurations

### Configuration 1: Active-Active (Recommended)

**Scenario:** Multiple orchestrators in same region, all actively processing workflows.

**How It Works:**
- Multiple orchestrators poll same pgmq queues
- PostgreSQL handles task distribution via `start_tasks()` locking
- First orchestrator to claim task wins
- Others skip and poll for next task

**Configuration:**

```elixir
# config/prod.exs - Same on ALL orchestrators

config :singularity_workflow,
  mode: :active_active,

  # Unique worker ID per instance
  worker_id: System.get_env("WORKER_ID") || UUID.uuid4(),

  # Shared PostgreSQL
  repo: MyApp.Repo,

  # Polling configuration
  poll_interval_ms: 100,
  batch_size: 10,

  # Heartbeat
  heartbeat_interval_ms: 5_000,
  heartbeat_timeout_ms: 30_000  # Mark worker dead after 30s no heartbeat
```

**PostgreSQL Setup:**
```sql
-- Single primary database
-- All orchestrators connect to same DB
-- pgmq queues are shared
```

**Pros:**
- Simple setup
- Automatic load balancing
- No manual failover needed

**Cons:**
- Single database point of failure (mitigate with HA PostgreSQL)

---

### Configuration 2: Active-Passive (High Availability)

**Scenario:** Primary orchestrator processes workflows, standby ready for failover.

**How It Works:**
- Primary orchestrator actively polls queues
- Standby monitors primary's heartbeat
- If primary fails (no heartbeat), standby takes over
- Standby starts polling queues

**Configuration:**

```elixir
# config/prod.exs

config :singularity_workflow,
  mode: :active_passive,
  role: System.get_env("ORCHESTRATOR_ROLE"),  # "primary" or "standby"

  # Failover detection
  primary_heartbeat_check_interval: 5_000,
  primary_timeout_ms: 15_000,  # Promote standby after 15s no heartbeat

  # Leadership election
  leadership_key: "orchestrator:leader",
  leadership_ttl_ms: 10_000
```

**Leadership Election (PostgreSQL Advisory Locks):**

```elixir
# lib/my_app/orchestrator_supervisor.ex

defmodule MyApp.OrchestratorSupervisor do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    # Try to acquire leadership
    if opts[:role] == "primary" do
      acquire_leadership()
    else
      monitor_primary()
    end

    {:ok, %{role: opts[:role], is_leader: false}}
  end

  defp acquire_leadership do
    # Use PostgreSQL advisory lock for leadership
    query = "SELECT pg_try_advisory_lock(12345)"

    case Ecto.Adapters.SQL.query(MyApp.Repo, query) do
      {:ok, %{rows: [[true]]}} ->
        # We are the leader
        start_polling_workers()

      {:ok, %{rows: [[false]]}} ->
        # Another orchestrator is leader
        become_standby()
    end
  end
end
```

**Pros:**
- Clear primary/standby roles
- Fast failover (seconds)
- No split-brain

**Cons:**
- Standby is idle (wasted capacity)
- Requires leadership election

---

### Configuration 3: Multi-Region with Read Replicas

**Scenario:** Primary region processes workflows, other regions use read replicas for queries.

**How It Works:**
- Primary region: orchestrators write to primary DB
- Other regions: orchestrators read from local replicas
- Workflow execution always goes to primary
- Status queries use local replicas (low latency)

**Configuration:**

```elixir
# Region US-EAST (primary)
config :singularity_workflow,
  repo: MyApp.Repo,  # Primary DB
  mode: :primary_region,
  can_execute_workflows: true

# Region EU-WEST (secondary)
config :singularity_workflow,
  repo: MyApp.ReplicaRepo,  # Read replica
  mode: :secondary_region,
  can_execute_workflows: false,  # Read-only

  # Route execution to primary
  primary_region_url: "https://us-east.example.com"
```

**Routing Logic:**

```elixir
defmodule MyApp.WorkflowRouter do
  def execute_workflow(goal, opts) do
    if Application.get_env(:singularity_workflow, :can_execute_workflows) do
      # Execute locally
      Singularity.Workflow.Orchestrator.execute_goal(goal, ...)
    else
      # Forward to primary region
      forward_to_primary(goal, opts)
    end
  end

  defp forward_to_primary(goal, opts) do
    primary_url = Application.get_env(:singularity_workflow, :primary_region_url)

    HTTPoison.post("#{primary_url}/api/workflows/execute", %{
      goal: goal,
      opts: opts
    })
  end
end
```

**PostgreSQL Replication:**
```sql
-- Primary (US-EAST)
CREATE PUBLICATION workflow_pub FOR ALL TABLES;

-- Replica (EU-WEST)
CREATE SUBSCRIPTION workflow_sub
  CONNECTION 'host=us-east.db.example.com dbname=workflows user=replicator'
  PUBLICATION workflow_pub;
```

**Pros:**
- Low-latency reads in all regions
- Centralized workflow execution
- Simple consistency model

**Cons:**
- Writes always go to primary (latency)
- Replica lag for status queries

---

## Tenant-Aware Routing

With `tenant_id` field now available, you can **pin tenants to specific regions**.

### Tenant Routing Table

```sql
CREATE TABLE tenant_regions (
  tenant_id UUID PRIMARY KEY,
  primary_region TEXT NOT NULL,
  fallback_regions TEXT[],
  created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO tenant_regions VALUES
  ('tenant-a', 'us-east', ARRAY['us-west', 'eu-west']),
  ('tenant-b', 'eu-west', ARRAY['eu-central', 'us-east']);
```

### Routing Logic

```elixir
defmodule MyApp.TenantRouter do
  def execute_for_tenant(tenant_id, goal, opts) do
    # Get tenant's primary region
    region = get_tenant_region(tenant_id)

    if region == current_region() do
      # Execute locally
      Singularity.Workflow.Orchestrator.execute_goal(goal, opts)
    else
      # Forward to tenant's region
      forward_to_region(region, tenant_id, goal, opts)
    end
  end

  defp get_tenant_region(tenant_id) do
    query = """
    SELECT primary_region FROM tenant_regions WHERE tenant_id = $1
    """

    case Ecto.Adapters.SQL.query(MyApp.Repo, query, [tenant_id]) do
      {:ok, %{rows: [[region]]}} -> region
      _ -> "us-east"  # Default region
    end
  end
end
```

**Benefits:**
- Data locality (GDPR compliance)
- Predictable latency per tenant
- Region-specific failure isolation

---

## Health Checks & Monitoring

### Orchestrator Health Check

```elixir
# lib/my_app_web/controllers/health_controller.ex

defmodule MyAppWeb.HealthController do
  use MyAppWeb, :controller

  def orchestrator_health(conn, _params) do
    checks = %{
      database: check_database(),
      pgmq: check_pgmq(),
      workers: check_workers(),
      memory: check_memory(),
      uptime: System.uptime()
    }

    status = if all_healthy?(checks), do: :ok, else: :degraded

    conn
    |> put_status(if status == :ok, do: 200, else: 503)
    |> json(%{status: status, checks: checks})
  end

  defp check_database do
    try do
      Ecto.Adapters.SQL.query!(MyApp.Repo, "SELECT 1")
      :healthy
    rescue
      _ -> :unhealthy
    end
  end

  defp check_pgmq do
    try do
      query = "SELECT * FROM pgmq.list_queues() LIMIT 1"
      Ecto.Adapters.SQL.query!(MyApp.Repo, query)
      :healthy
    rescue
      _ -> :unhealthy
    end
  end

  defp check_workers do
    # Check for active workers
    query = """
    SELECT COUNT(*) FROM workflow_workers
    WHERE last_heartbeat_at > NOW() - INTERVAL '30 seconds'
    """

    case Ecto.Adapters.SQL.query(MyApp.Repo, query) do
      {:ok, %{rows: [[count]]}} when count > 0 -> :healthy
      _ -> :no_workers
    end
  end
end
```

### Prometheus Metrics

```elixir
# lib/my_app/telemetry.ex

defmodule MyApp.Telemetry do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      # Prometheus exporter
      {PromEx, MyApp.PromEx}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

# Custom metrics
defmodule MyApp.PromEx do
  use PromEx, otp_app: :my_app

  @impl true
  def plugins do
    [
      PromEx.Plugins.Beam,
      PromEx.Plugins.Ecto,
      MyApp.WorkflowMetrics
    ]
  end

  @impl true
  def dashboards do
    []
  end
end

defmodule MyApp.WorkflowMetrics do
  use PromEx.Plugin

  @impl true
  def polling_metrics(opts) do
    poll_rate = 5_000

    [
      workflows_metric(opts),
      workers_metric(opts)
    ]
  end

  defp workflows_metric(_opts) do
    Polling.build(
      :workflow_metrics,
      {__MODULE__, :execute_workflow_metrics, []},
      [
        last_value([:workflow, :runs, :active],
          description: "Number of active workflow runs"),
        last_value([:workflow, :runs, :completed],
          description: "Total completed workflows"),
        last_value([:workflow, :runs, :failed],
          description: "Total failed workflows")
      ]
    )
  end

  def execute_workflow_metrics do
    # Query PostgreSQL for metrics
    %{active: count_active(), completed: count_completed(), failed: count_failed()}
  end
end
```

---

## Failover Procedures

### Automatic Failover (Active-Passive)

```elixir
# Standby monitors primary via heartbeat
defmodule MyApp.FailoverManager do
  use GenServer

  def init(state) do
    # Schedule heartbeat checks
    :timer.send_interval(5_000, :check_primary_heartbeat)
    {:ok, state}
  end

  def handle_info(:check_primary_heartbeat, state) do
    case check_primary_alive?() do
      true ->
        {:noreply, state}

      false ->
        Logger.warning("Primary orchestrator down, promoting to leader")
        promote_to_primary()
        {:noreply, %{state | role: :primary}}
    end
  end

  defp check_primary_alive? do
    query = """
    SELECT last_heartbeat_at FROM workflow_workers
    WHERE worker_id = $1
    """

    primary_id = Application.get_env(:singularity_workflow, :primary_worker_id)

    case Ecto.Adapters.SQL.query(MyApp.Repo, query, [primary_id]) do
      {:ok, %{rows: [[timestamp]]}} ->
        DateTime.diff(DateTime.utc_now(), timestamp) < 15

      _ ->
        false
    end
  end

  defp promote_to_primary do
    # Acquire leadership lock
    Ecto.Adapters.SQL.query!(MyApp.Repo, "SELECT pg_advisory_lock(12345)")

    # Start polling workers
    MyApp.WorkerSupervisor.start_workers()

    Logger.info("Failover complete, now primary orchestrator")
  end
end
```

### Manual Failover

```bash
# Gracefully stop primary
curl -X POST https://primary.example.com/admin/orchestrator/stop

# Promote standby
curl -X POST https://standby.example.com/admin/orchestrator/promote
```

---

## Best Practices

### 1. PostgreSQL High Availability

Use PostgreSQL HA solutions:

**Option A: Patroni** (Recommended)
```yaml
# patroni.yml
scope: workflows
name: postgres-1

postgresql:
  data_dir: /var/lib/postgresql/data

watchdog:
  mode: required
  device: /dev/watchdog

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
```

**Option B: Managed Services**
- AWS RDS with Multi-AZ
- Google Cloud SQL with HA
- Azure Database for PostgreSQL with replicas

### 2. Connection Pooling

```elixir
# config/prod.exs
config :my_app, MyApp.Repo,
  pool_size: 20,
  queue_target: 50,
  queue_interval: 1000
```

### 3. Graceful Shutdown

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  def stop(_state) do
    # Stop accepting new workflows
    MyApp.WorkflowGate.close()

    # Wait for in-flight workflows to complete
    wait_for_workflows(timeout: 30_000)

    # Mark worker as deprecated
    deprecate_worker()

    :ok
  end

  defp wait_for_workflows(opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    start = System.monotonic_time(:millisecond)

    wait_loop(start, timeout)
  end

  defp wait_loop(start, timeout) do
    if System.monotonic_time(:millisecond) - start > timeout do
      Logger.warning("Shutdown timeout, forcefully stopping")
      :ok
    else
      case count_in_flight_tasks() do
        0 ->
          Logger.info("All workflows completed, safe shutdown")
          :ok

        count ->
          Logger.info("Waiting for #{count} tasks to complete")
          Process.sleep(1000)
          wait_loop(start, timeout)
      end
    end
  end

  defp deprecate_worker do
    worker_id = Application.get_env(:singularity_workflow, :worker_id)

    query = """
    UPDATE workflow_workers
    SET deprecated_at = NOW()
    WHERE worker_id = $1
    """

    Ecto.Adapters.SQL.query(MyApp.Repo, query, [worker_id])
  end
end
```

### 4. Monitoring Dashboards

Create Grafana dashboard for multi-orchestrator visibility:

```promql
# Active orchestrators
count(up{job="orchestrator"} == 1)

# Workflows per orchestrator
rate(workflow_executions_total[5m]) by (orchestrator_id)

# Queue depth by region
pgmq_queue_depth by (region, queue)

# Failover events
increase(orchestrator_failovers_total[1h])
```

---

## Troubleshooting

### Issue: Split-Brain

**Symptoms:** Two orchestrators both think they're primary

**Detection:**
```sql
SELECT COUNT(*) FROM workflow_workers
WHERE deprecated_at IS NULL;
-- Should be <= expected number of orchestrators
```

**Fix:**
```elixir
# Force release all advisory locks
Ecto.Adapters.SQL.query!(MyApp.Repo, "SELECT pg_advisory_unlock_all()")

# Restart orchestrators in order
# Only one will acquire lock
```

### Issue: Stale Workers

**Symptoms:** Old workers still showing in `workflow_workers` table

**Detection:**
```sql
SELECT * FROM workflow_workers
WHERE last_heartbeat_at < NOW() - INTERVAL '5 minutes';
```

**Fix:**
```sql
-- Automatic cleanup query (run via cron)
DELETE FROM workflow_workers
WHERE last_heartbeat_at < NOW() - INTERVAL '1 hour';
```

### Issue: Region Lag

**Symptoms:** Read replica has stale data

**Detection:**
```sql
-- On replica
SELECT pg_last_wal_replay_lsn();

-- On primary
SELECT pg_current_wal_lsn();

-- Compare lag
SELECT pg_wal_lsn_diff(
  pg_current_wal_lsn(),
  pg_last_wal_replay_lsn()
) AS lag_bytes;
```

**Fix:**
- Check network between primary and replica
- Increase `max_wal_senders` on primary
- Reduce `wal_retrieve_retry_interval` on replica

---

## Summary

**singularity_workflow is already multi-orchestrator ready:**

✅ Stateless orchestrators
✅ PostgreSQL coordination
✅ Worker heartbeats
✅ Idempotency keys
✅ Tenant isolation (`tenant_id`)

**To deploy globally redundant:**

1. Choose deployment pattern (active-active, active-passive, multi-region)
2. Set up PostgreSQL HA (Patroni, managed service, or replication)
3. Configure orchestrators with worker IDs and heartbeats
4. Add health checks and monitoring
5. Implement graceful shutdown
6. Set up alerting for failover events

**The architecture supports it all - just add the deployment layer.**
