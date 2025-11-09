# Node Roles and Deployment Patterns

**Package:** singularity_workflow v0.1.5+

---

## Node Role Definitions

### **Hybrid Node** (Recommended Default)

Most deployments use **hybrid nodes** that serve both roles:

```elixir
# config/prod.exs - Hybrid node configuration

config :singularity_workflow,
  # CLIENT ROLE: Submit and query workflows
  enable_client: true,

  # EXECUTOR ROLE: Execute workflow tasks
  enable_executor: true,

  # Worker configuration
  worker_pools: [
    default: [size: 10, queue: "default"],
    gpu: [size: 2, queue: "gpu_tasks"]
  ]
```

**Characteristics:**
- ✅ Can submit workflows (client)
- ✅ Can execute tasks (executor)
- ✅ Fully self-sufficient
- ✅ Simplest deployment

**Use When:**
- Standard deployments
- All nodes have similar resources
- Want maximum flexibility

---

### **Edge Node** (Client-Only)

Handles user requests but doesn't execute tasks:

```elixir
# config/prod.exs - Edge node

config :singularity_workflow,
  enable_client: true,    # ← Submit workflows
  enable_executor: false  # ← Don't execute tasks
```

**Characteristics:**
- ✅ Accepts user requests
- ✅ Submits workflows to PostgreSQL
- ✅ Queries workflow status
- ❌ Doesn't poll queues
- ❌ Doesn't execute tasks

**Use When:**
- Public-facing API servers
- Want to isolate user traffic from task execution
- Edge locations with limited resources

---

### **Worker Node** (Executor-Only)

Dedicated to task execution:

```elixir
# config/prod.exs - Worker node

config :singularity_workflow,
  enable_client: false,   # ← Don't accept submissions
  enable_executor: true,  # ← Execute tasks only

  worker_pools: [
    gpu: [size: 8, queue: "gpu_tasks"],
    cpu_intensive: [size: 16, queue: "cpu_tasks"]
  ]
```

**Characteristics:**
- ❌ Doesn't handle user requests
- ✅ Polls pgmq queues
- ✅ Executes workflow tasks
- ✅ Updates PostgreSQL state

**Use When:**
- Specialized hardware (GPUs, high-memory machines)
- Want to scale execution independently
- Internal execution cluster

---

## Deployment Patterns

### Pattern 1: All Hybrid (Recommended for Most)

```
Internet
    │
    ↓
┌────────────────────────────────────┐
│  Load Balancer                     │
└────┬───────────┬──────────┬────────┘
     │           │          │
     ↓           ↓          ↓
┌─────────┐ ┌─────────┐ ┌─────────┐
│ Hybrid  │ │ Hybrid  │ │ Hybrid  │
│ Node 1  │ │ Node 2  │ │ Node 3  │
│ C + E   │ │ C + E   │ │ C + E   │
└────┬────┘ └────┬────┘ └────┬─────┘
     │           │          │
     └───────────┴──────────┘
                 │
                 ↓
         ┌──────────────┐
         │  PostgreSQL  │
         │  + pgmq      │
         └──────────────┘

C = Client (submit workflows)
E = Executor (execute tasks)
```

**Configuration:**

```elixir
# Same on all nodes
config :singularity_workflow,
  enable_client: true,
  enable_executor: true,
  worker_pools: [
    default: [size: 10]
  ]
```

**Pros:**
- Simple configuration (same on all nodes)
- Any node can handle any request
- Auto load balancing
- High availability

**Cons:**
- Can't specialize nodes for specific hardware

---

### Pattern 2: Edge + Workers (Specialized Hardware)

```
Internet
    │
    ↓
┌────────────────────────────────────┐
│  Load Balancer                     │
└────┬───────────┬───────────────────┘
     │           │
     ↓           ↓
┌─────────┐ ┌─────────┐
│ Edge    │ │ Edge    │  ← Client only (accept requests)
│ Node 1  │ │ Node 2  │
│ (C)     │ │ (C)     │
└─────────┘ └─────────┘
     │           │
     └─────┬─────┘
           │
  ┌────────┴────────┬────────────┬─────────────┐
  │                 │            │             │
  ↓                 ↓            ↓             ↓
┌─────────┐   ┌─────────┐  ┌─────────┐  ┌─────────┐
│ Worker  │   │ Worker  │  │ GPU     │  │ GPU     │
│ Node 1  │   │ Node 2  │  │ Worker 1│  │ Worker 2│
│ (E)     │   │ (E)     │  │ (E)     │  │ (E)     │
│ CPU     │   │ CPU     │  │ GPU x4  │  │ GPU x4  │
└────┬────┘   └────┬────┘  └────┬────┘  └────┬────┘
     │             │            │            │
     └─────────────┴────────────┴────────────┘
                   │
                   ↓
           ┌──────────────┐
           │  PostgreSQL  │
           │  + pgmq      │
           └──────────────┘
```

**Configuration:**

```elixir
# Edge nodes (public-facing)
config :singularity_workflow,
  enable_client: true,
  enable_executor: false

# CPU worker nodes
config :singularity_workflow,
  enable_client: false,
  enable_executor: true,
  worker_pools: [
    cpu: [size: 20, queue: "cpu_tasks"]
  ]

# GPU worker nodes
config :singularity_workflow,
  enable_client: false,
  enable_executor: true,
  worker_pools: [
    gpu: [size: 8, queue: "gpu_tasks"]
  ]
```

**Pros:**
- Specialized hardware per node type
- Scale edge and workers independently
- Isolate user traffic from execution

**Cons:**
- More complex configuration
- Edge nodes don't help with execution

---

### Pattern 3: Multi-Region Hybrid

```
┌─────────────────────────────────────────────────┐
│  REGION: US-EAST                                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │ Hybrid 1 │  │ Hybrid 2 │  │ Hybrid 3 │      │
│  │  C + E   │  │  C + E   │  │  C + E   │      │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘      │
│       │             │             │             │
│       └─────────────┴─────────────┘             │
│                     │                           │
│              ┌──────▼────────┐                  │
│              │  PostgreSQL   │                  │
│              │  Primary      │──────────┐       │
│              └───────────────┘          │       │
└─────────────────────────────────────────┼───────┘
                                          │
┌─────────────────────────────────────────┼───────┐
│  REGION: EU-WEST                        │       │
│  ┌──────────┐  ┌──────────┐      ┌──────▼─────┐│
│  │ Hybrid 4 │  │ Hybrid 5 │      │ PostgreSQL ││
│  │  C + E   │  │  C + E   │      │ Replica    ││
│  └────┬─────┘  └────┬─────┘      └────────────┘│
│       │             │                           │
│       └─────────────┘ (read from replica)      │
└─────────────────────────────────────────────────┘
```

**Configuration:**

```elixir
# US-EAST (primary region) - Hybrid nodes
config :singularity_workflow,
  enable_client: true,
  enable_executor: true,
  repo: MyApp.Repo,  # Primary DB
  region: "us-east"

# EU-WEST (secondary region) - Hybrid nodes
config :singularity_workflow,
  enable_client: true,   # Accept queries
  enable_executor: true, # Execute tasks
  repo: MyApp.ReplicaRepo,  # Read replica
  region: "eu-west",

  # Route writes to primary
  write_region: "us-east"
```

**Pros:**
- Global presence
- Low-latency reads per region
- All nodes are hybrid (flexibility)

**Cons:**
- Writes still go to primary region

---

## Implementation

### Adding Client Role

```elixir
# lib/my_app_web/controllers/workflow_controller.ex

defmodule MyAppWeb.WorkflowController do
  use MyAppWeb, :controller

  def create(conn, %{"goal" => goal}) do
    # This node's CLIENT role submits workflow
    case Singularity.Workflow.Orchestrator.execute_goal(
      goal,
      &MyApp.Decomposer.decompose/1,
      %{},
      MyApp.Repo
    ) do
      {:ok, result} ->
        json(conn, %{run_id: result.run_id, status: "started"})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: reason})
    end
  end

  def show(conn, %{"run_id" => run_id}) do
    # This node's CLIENT role queries status
    {:ok, lineage} = Singularity.Workflow.Lineage.get_lineage(run_id, MyApp.Repo)

    json(conn, %{
      run_id: run_id,
      status: lineage.status,
      metrics: lineage.metrics
    })
  end
end
```

### Adding Executor Role

```elixir
# lib/my_app/application.ex

defmodule MyApp.Application do
  def start(_type, _args) do
    children = base_children() ++ executor_children()

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp base_children do
    [
      MyApp.Repo,
      MyAppWeb.Endpoint
    ]
  end

  defp executor_children do
    if Application.get_env(:singularity_workflow, :enable_executor, true) do
      [
        # Worker supervisor for task execution
        {MyApp.WorkerSupervisor, []},

        # Heartbeat updater
        {MyApp.HeartbeatWorker, []}
      ]
    else
      []
    end
  end
end

defmodule MyApp.WorkerSupervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Start worker pools based on configuration
    pools = Application.get_env(:singularity_workflow, :worker_pools, [])

    children =
      Enum.map(pools, fn {name, config} ->
        pool_size = Keyword.get(config, :size, 10)
        queue = Keyword.get(config, :queue, "default")

        Supervisor.child_spec(
          {MyApp.TaskWorker, [queue: queue, name: name]},
          id: {MyApp.TaskWorker, name}
        )
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

### Role Detection

```elixir
# lib/my_app/node_info.ex

defmodule MyApp.NodeInfo do
  @doc "Get this node's roles"
  def roles do
    [
      client: Application.get_env(:singularity_workflow, :enable_client, true),
      executor: Application.get_env(:singularity_workflow, :enable_executor, true)
    ]
    |> Enum.filter(fn {_role, enabled} -> enabled end)
    |> Enum.map(fn {role, _} -> role end)
  end

  @doc "Check if this node is hybrid (both roles)"
  def hybrid? do
    length(roles()) == 2
  end

  @doc "Get node type name"
  def node_type do
    case roles() do
      [:client, :executor] -> "hybrid"
      [:client] -> "edge"
      [:executor] -> "worker"
      [] -> "disabled"
    end
  end
end

# Usage in health check
defmodule MyAppWeb.HealthController do
  def info(conn, _params) do
    json(conn, %{
      node_type: MyApp.NodeInfo.node_type(),
      roles: MyApp.NodeInfo.roles(),
      region: Application.get_env(:singularity_workflow, :region),
      worker_pools: get_worker_pool_status()
    })
  end
end
```

---

## Naming Summary

**OLD (confusing):**
- "Orchestrator" (ambiguous - what does it orchestrate?)
- "Worker" (too generic)

**NEW (clear):**

| Term | Means | Has Client Role? | Has Executor Role? |
|------|-------|-----------------|-------------------|
| **Hybrid Node** | Full-featured node | ✅ Yes | ✅ Yes |
| **Edge Node** | Public-facing, client-only | ✅ Yes | ❌ No |
| **Worker Node** | Execution-only, no API | ❌ No | ✅ Yes |

**Recommended Default:** Hybrid nodes (both roles enabled)

---

## Migration from Current Setup

If you're currently running "orchestrators":

```elixir
# Before (old naming)
config :singularity_workflow,
  mode: :orchestrator  # What does this mean?

# After (new naming)
config :singularity_workflow,
  enable_client: true,    # Accept workflow submissions
  enable_executor: true   # Execute workflow tasks

# This makes you a HYBRID node (recommended)
```

---

## Summary

- **Most nodes should be HYBRID** (client + executor)
- **Edge nodes** = client-only (public API, no execution)
- **Worker nodes** = executor-only (specialized hardware)

The architecture supports all three patterns - choose based on your needs.
