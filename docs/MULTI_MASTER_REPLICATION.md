# Multi-Master Global Replication

**Architecture:** Every server has its own PostgreSQL database, all globally replicating.

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  SERVER 1 (US-EAST)                                      │
│  ┌────────────┐                                          │
│  │ Hybrid Node│ (Client + Executor)                      │
│  └─────┬──────┘                                          │
│        │                                                  │
│  ┌─────▼───────────┐                                     │
│  │  PostgreSQL     │────────────┐                        │
│  │  Local Master   │            │ Replication            │
│  └─────────────────┘            │                        │
└─────────────────────────────────┼────────────────────────┘
                                  │
┌─────────────────────────────────┼────────────────────────┐
│  SERVER 2 (EU-WEST)             │                        │
│  ┌────────────┐                 │                        │
│  │ Hybrid Node│                 │                        │
│  └─────┬──────┘                 │                        │
│        │                        │                        │
│  ┌─────▼───────────┐            │                        │
│  │  PostgreSQL     │◄───────────┘                        │
│  │  Local Master   │────────────┐                        │
│  └─────────────────┘            │                        │
└─────────────────────────────────┼────────────────────────┘
                                  │
┌─────────────────────────────────┼────────────────────────┐
│  SERVER 3 (AP-SOUTH)            │                        │
│  ┌────────────┐                 │                        │
│  │ Hybrid Node│                 │                        │
│  └─────┬──────┘                 │                        │
│        │                        │                        │
│  ┌─────▼───────────┐            │                        │
│  │  PostgreSQL     │◄───────────┘                        │
│  │  Local Master   │                                     │
│  └─────────────────┘                                     │
└──────────────────────────────────────────────────────────┘

- Every server is HYBRID (client + executor)
- Every server has FULL PostgreSQL database
- All databases replicate bidirectionally
- No single primary - all are equals
```

---

## Key Challenges & Solutions

### Challenge 1: Conflict Resolution

**Problem:** Same workflow submitted to 2 servers simultaneously

**Solution: Tenant Partitioning + Idempotency**

```elixir
# Each tenant is "owned" by a home region
# Workflows for that tenant ALWAYS execute on home region

defmodule MyApp.TenantRouter do
  @doc """
  Route tenant to home region.
  Ensures no conflicts - only one region executes for a tenant.
  """
  def get_home_region(tenant_id) do
    # Hash tenant_id to consistent region
    regions = ["us-east", "eu-west", "ap-south"]

    hash = :erlang.phash2(tenant_id, length(regions))
    Enum.at(regions, hash)
  end

  def submit_workflow(tenant_id, goal, opts) do
    home_region = get_home_region(tenant_id)
    current_region = Application.get_env(:my_app, :region)

    if home_region == current_region do
      # Execute locally (this is tenant's home region)
      Singularity.Workflow.Orchestrator.execute_goal(goal, ...)
    else
      # Forward to home region
      forward_to_region(home_region, tenant_id, goal, opts)
    end
  end

  defp forward_to_region(region, tenant_id, goal, opts) do
    # HTTP request to home region
    region_url = get_region_url(region)

    HTTPoison.post("#{region_url}/api/workflows", %{
      tenant_id: tenant_id,
      goal: goal,
      opts: opts
    })
  end
end
```

### Challenge 2: Database Synchronization

**Solution: PostgreSQL Logical Replication**

```sql
-- ON EACH SERVER: Set up logical replication

-- Server 1 (US-EAST)
CREATE PUBLICATION server1_pub FOR ALL TABLES;

-- Subscribe to other servers
CREATE SUBSCRIPTION server1_from_server2
  CONNECTION 'host=eu-west.db.example.com dbname=workflows user=replicator'
  PUBLICATION server2_pub;

CREATE SUBSCRIPTION server1_from_server3
  CONNECTION 'host=ap-south.db.example.com dbname=workflows user=replicator'
  PUBLICATION server3_pub;
```

**Replication Topology: Full Mesh**

```
Server1 ◄──────► Server2
   │                │
   │                │
   └──────┬─────────┘
          │
          ▼
       Server3
```

### Challenge 3: Idempotency Keys Prevent Duplicates

```elixir
# Idempotency key format: tenant_id + workflow_slug + timestamp + hash

def generate_idempotency_key(tenant_id, workflow_slug, input) do
  input_hash = :crypto.hash(:md5, Jason.encode!(input))
    |> Base.encode16(case: :lower)

  "#{tenant_id}:#{workflow_slug}:#{System.system_time(:millisecond)}:#{input_hash}"
end

# When workflow arrives via replication
def handle_replicated_workflow(workflow_run) do
  case MyApp.Repo.get_by(WorkflowRun, idempotency_key: workflow_run.idempotency_key) do
    nil ->
      # New workflow, insert
      MyApp.Repo.insert(workflow_run)

    existing ->
      # Duplicate (already replicated), skip
      Logger.debug("Skipping duplicate workflow: #{workflow_run.idempotency_key}")
      {:ok, existing}
  end
end
```

---

## Implementation

### Step 1: PostgreSQL BDR Setup

**Option A: PostgreSQL Logical Replication (Built-in)**

```bash
# On each server:

# 1. Enable logical replication
echo "wal_level = logical" >> /etc/postgresql/postgresql.conf
echo "max_replication_slots = 10" >> /etc/postgresql/postgresql.conf
echo "max_wal_senders = 10" >> /etc/postgresql/postgresql.conf

# 2. Restart PostgreSQL
systemctl restart postgresql

# 3. Create replication user
psql -c "CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'secure_password';"

# 4. Set up publications (on each server)
psql -c "CREATE PUBLICATION all_tables_pub FOR ALL TABLES;"

# 5. Set up subscriptions (to other servers)
# Server 1 subscribes to Server 2 and Server 3
psql -c "
CREATE SUBSCRIPTION from_server2
  CONNECTION 'host=server2.example.com dbname=workflows user=replicator password=xxx'
  PUBLICATION all_tables_pub;
"

psql -c "
CREATE SUBSCRIPTION from_server3
  CONNECTION 'host=server3.example.com dbname=workflows user=replicator password=xxx'
  PUBLICATION all_tables_pub;
"
```

**Option B: PostgreSQL BDR (Enterprise)**

BDR (Bi-Directional Replication) from EDB:

```sql
-- Create BDR group
SELECT bdr.create_node('server1', 'host=server1.example.com port=5432 dbname=workflows');
SELECT bdr.create_node('server2', 'host=server2.example.com port=5432 dbname=workflows');
SELECT bdr.create_node('server3', 'host=server3.example.com port=5432 dbname=workflows');

-- Join nodes to group
SELECT bdr.join_node_group('workflows_group', 'server1');
SELECT bdr.join_node_group('workflows_group', 'server2');
SELECT bdr.join_node_group('workflows_group', 'server3');
```

---

### Step 2: Conflict Resolution Rules

```sql
-- Set conflict resolution strategy per table

-- For workflow_runs: Last-Write-Wins based on started_at
ALTER TABLE workflow_runs REPLICA IDENTITY FULL;

-- For step_tasks: Use idempotency_key to detect duplicates
CREATE UNIQUE INDEX step_tasks_idempotency_idx ON workflow_step_tasks(idempotency_key);

-- For tenant assignment: Prefer tenant's home region
-- (Handled at application level via routing)
```

---

### Step 3: Application Configuration

```elixir
# config/prod.exs

config :my_app,
  # This server's region
  region: System.get_env("REGION"),  # "us-east", "eu-west", "ap-south"

  # All servers are hybrid
  enable_client: true,
  enable_executor: true,

  # Multi-master replication
  replication_mode: :multi_master,

  # Other regions (for forwarding)
  regions: %{
    "us-east" => "https://us-east.example.com",
    "eu-west" => "https://eu-west.example.com",
    "ap-south" => "https://ap-south.example.com"
  },

  # Tenant routing (hash-based assignment)
  tenant_routing: :consistent_hash

config :my_app, MyApp.Repo,
  # Local PostgreSQL (each server has its own)
  hostname: "localhost",
  database: "workflows",
  username: "postgres",
  password: System.get_env("DB_PASSWORD"),

  # Connection pool
  pool_size: 20
```

---

### Step 4: Tenant-Aware Workflow Submission

```elixir
# lib/my_app_web/controllers/workflow_controller.ex

defmodule MyAppWeb.WorkflowController do
  def create(conn, %{"tenant_id" => tenant_id, "goal" => goal}) do
    # Route to tenant's home region
    home_region = MyApp.TenantRouter.get_home_region(tenant_id)
    current_region = Application.get_env(:my_app, :region)

    result =
      if home_region == current_region do
        # Execute locally
        execute_workflow_locally(tenant_id, goal, conn.body_params)
      else
        # Forward to home region
        forward_to_home_region(home_region, tenant_id, goal, conn.body_params)
      end

    case result do
      {:ok, run_id} ->
        json(conn, %{run_id: run_id, executed_on: home_region})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: reason})
    end
  end

  defp execute_workflow_locally(tenant_id, goal, opts) do
    # Generate idempotency key
    idempotency_key = generate_idempotency_key(tenant_id, goal, opts)

    # Submit workflow with tenant_id
    Singularity.Workflow.Orchestrator.execute_goal(
      goal,
      &MyApp.Decomposer.decompose/1,
      %{},
      MyApp.Repo,
      tenant_id: tenant_id,
      idempotency_key: idempotency_key
    )
  end

  defp forward_to_home_region(region, tenant_id, goal, opts) do
    region_url = Application.get_env(:my_app, :regions)[region]

    case HTTPoison.post(
      "#{region_url}/api/workflows",
      Jason.encode!(%{tenant_id: tenant_id, goal: goal, opts: opts}),
      [{"Content-Type", "application/json"}]
    ) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)["run_id"]}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

---

### Step 5: Monitoring Replication Lag

```sql
-- Check replication lag on each server

-- Subscription status
SELECT
  subname,
  received_lsn,
  latest_end_lsn,
  pg_wal_lsn_diff(latest_end_lsn, received_lsn) AS lag_bytes
FROM pg_stat_subscription;

-- Publication activity
SELECT * FROM pg_stat_replication;
```

```elixir
# Prometheus metric for replication lag
defmodule MyApp.ReplicationMetrics do
  use PromEx.Plugin

  @impl true
  def polling_metrics(_opts) do
    [
      replication_lag_metric()
    ]
  end

  defp replication_lag_metric do
    Polling.build(
      :replication_lag,
      {__MODULE__, :measure_replication_lag, []},
      [
        last_value([:postgres, :replication, :lag_bytes],
          description: "Replication lag in bytes",
          tags: [:subscription_name]
        )
      ]
    )
  end

  def measure_replication_lag do
    query = """
    SELECT
      subname,
      pg_wal_lsn_diff(latest_end_lsn, received_lsn) AS lag_bytes
    FROM pg_stat_subscription
    """

    case Ecto.Adapters.SQL.query(MyApp.Repo, query) do
      {:ok, %{rows: rows}} ->
        Enum.into(rows, %{}, fn [subname, lag] ->
          {{:subscription_name, subname}, lag || 0}
        end)

      _ ->
        %{}
    end
  end
end
```

---

## Tenant Partitioning Strategy

### Consistent Hash Ring

```elixir
defmodule MyApp.TenantRouter do
  @doc """
  Consistent hashing to assign tenant to home region.

  Ensures:
  - Same tenant always routes to same region
  - Balanced distribution across regions
  - Minimal re-assignment if region added/removed
  """
  def get_home_region(tenant_id) do
    regions = active_regions()

    # Hash tenant_id
    hash = :crypto.hash(:md5, tenant_id)
      |> :binary.decode_unsigned()

    # Modulo number of regions
    index = rem(hash, length(regions))

    Enum.at(regions, index)
  end

  defp active_regions do
    # Could be dynamic (fetch from config or health checks)
    Application.get_env(:my_app, :active_regions, [
      "us-east",
      "eu-west",
      "ap-south"
    ])
  end

  @doc """
  Check if tenant is local (home region is current region).
  """
  def local_tenant?(tenant_id) do
    get_home_region(tenant_id) == current_region()
  end

  defp current_region do
    Application.get_env(:my_app, :region)
  end
end
```

### Tenant Registry Table

```sql
-- Optional: Explicit tenant → region mapping

CREATE TABLE tenant_registry (
  tenant_id UUID PRIMARY KEY,
  home_region TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Pre-assign tenants to regions
INSERT INTO tenant_registry VALUES
  ('tenant-a', 'us-east'),
  ('tenant-b', 'eu-west'),
  ('tenant-c', 'ap-south');

-- This table replicates globally
-- Each server knows which tenants belong to which region
```

---

## Failure Scenarios

### Scenario 1: One Region Goes Down

**Example:** EU-WEST region fails

**Impact:**
- Tenants with home_region="eu-west" can't execute workflows
- Other tenants (us-east, ap-south) unaffected

**Recovery:**
1. **Automatic:** Workflows for EU tenants queue locally on clients
2. **Manual failover:** Re-assign EU tenants to US-EAST temporarily

```elixir
# Emergency tenant re-assignment
def failover_region(from_region, to_region) do
  query = """
  UPDATE tenant_registry
  SET home_region = $2, updated_at = NOW()
  WHERE home_region = $1
  """

  Ecto.Adapters.SQL.query(MyApp.Repo, query, [from_region, to_region])

  Logger.warning("Failover: #{from_region} tenants moved to #{to_region}")
end

# When EU-WEST recovers
def restore_region(original_region, tenants) do
  Enum.each(tenants, fn tenant_id ->
    query = """
    UPDATE tenant_registry
    SET home_region = $1, updated_at = NOW()
    WHERE tenant_id = $2
    """

    Ecto.Adapters.SQL.query(MyApp.Repo, query, [original_region, tenant_id])
  end)
end
```

### Scenario 2: Network Partition (Split Brain)

**Problem:** US-EAST can't reach EU-WEST

**Impact:**
- Replication paused between regions
- Each region continues executing for its tenants
- WAL log accumulates on both sides

**Resolution:**
- Replication resumes automatically when network heals
- PostgreSQL logical replication catches up from WAL
- Conflicts resolved by timestamp (last-write-wins)

**Prevention:**
- Tenant partitioning prevents write conflicts
- Each tenant writes to exactly one region

---

## Benefits of Multi-Master

1. **Zero Single Point of Failure**
   - Any region can fail, others continue
   - No "primary" to worry about

2. **Local Writes**
   - Tenants write to their home region (low latency)
   - No cross-region writes

3. **Local Reads**
   - Every server has full database
   - Status queries are always local (fast)

4. **Automatic Load Balancing**
   - Tenant hash distributes load evenly
   - Each region handles ~1/3 of tenants

5. **Geographic Compliance**
   - EU tenants always process in EU region
   - Satisfies GDPR data residency

---

## Tradeoffs

### Compared to Single Primary

| Aspect | Multi-Master | Single Primary |
|--------|-------------|----------------|
| Writes | Local (fast) | Remote for some regions (slow) |
| Reads | Always local (fast) | Replicas may lag |
| Consistency | Eventually consistent | Strongly consistent |
| Complexity | Higher (conflict resolution) | Lower (single source of truth) |
| Failure Modes | Tenant-specific | Global outage if primary fails |

### When to Use Multi-Master

✅ Use when:
- Need low-latency writes globally
- Can tolerate eventual consistency
- Have clear tenant partitioning
- Want zero single point of failure

❌ Don't use when:
- Need strict consistency (ACID across regions)
- Can't partition by tenant
- Cross-tenant transactions required

---

## Summary

**Multi-master with tenant partitioning:**

- Every server = Hybrid node (client + executor)
- Every server = Full PostgreSQL database
- Tenants hash to home region (consistent hashing)
- Workflows execute only in home region (no conflicts)
- Databases replicate bidirectionally (eventual consistency)
- Idempotency keys prevent duplicates

**Result:** Globally redundant, zero single point of failure, low latency everywhere.
