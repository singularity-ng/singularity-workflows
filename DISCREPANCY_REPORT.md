# Singularity.Workflow Documentation Discrepancy Report

## Executive Summary
This report documents discrepancies between the README.md documentation and the actual code implementation of the Singularity.Workflow library. A total of **11 critical discrepancies** have been identified across API functions, parameters, options, and missing resources.

---

## 1. MISSING RESOURCES

### 1.1 Missing Examples Directory
**Severity:** MEDIUM | **Type:** Missing Documentation

**Location:** README.md, lines 567-579

**README Claims:**
```
Check the `examples/` directory for comprehensive examples:
- simple_workflow.ex
- parallel_processing.ex
- dynamic_workflow.ex
- notifications_demo.ex
- error_handling.ex
- phoenix_integration.ex
- ai_workflow_generation.ex
- microservices_coordination.ex
```

**Reality:**
- No `examples/` directory exists in the repository
- Searching /home/user/singularity-workflows/ confirms absence

**Impact:**
Users looking for example code files will not find them, reducing the learning curve and usability of the library.

**Fix Required:**
Either create the examples directory with the referenced files, or remove the Examples section from the README and link to documentation files instead.

---

## 2. INCORRECT FUNCTION NAMES IN API REFERENCE

### 2.1 FlowBuilder.add_map_step Does Not Exist
**Severity:** HIGH | **Type:** Non-existent API Function

**Location:** README.md, line 487

**README Claims:**
```elixir
Singularity.Workflow.FlowBuilder.add_map_step(workflow_id, step_name, depends_on, initial_tasks, repo)
```

**Reality:**
- Function signature: `Singularity.Workflow.FlowBuilder.add_step/5`
- File: /home/user/singularity-workflows/lib/singularity_workflow/flow_builder.ex, line 146
- Actual implementation uses options parameter for map step configuration:
```elixir
def add_step(workflow_slug, step_slug, depends_on, _repo, opts \\ [])
```
- Map steps are created by passing `step_type: "map"` and `initial_tasks: N` in opts
- Example from code docs (line 135-139):
```elixir
{:ok, _} = FlowBuilder.add_step("my_workflow", "process_batch", ["fetch"],
  step_type: "map",
  initial_tasks: 50,
  max_attempts: 5
)
```

**Code Reference:**
File: /home/user/singularity-workflows/lib/singularity_workflow/flow_builder.ex
- Lines 106-172: Shows `add_step` function with `:step_type` and `:initial_tasks` options

**Impact:** 
Users trying to call `add_map_step` will get a function not found error. They need to use `add_step` with options instead.

**Fix Required:**
Replace line 487 in README with:
```elixir
# Add map step (process 50 items in parallel)
Singularity.Workflow.FlowBuilder.add_step(workflow_id, step_name, depends_on, repo,
  step_type: "map",
  initial_tasks: 50
)
```

---

### 2.2 FlowBuilder.get_workflow Should Be get_flow
**Severity:** HIGH | **Type:** Incorrect Function Name

**Location:** README.md, line 490

**README Claims:**
```elixir
Singularity.Workflow.FlowBuilder.get_workflow(workflow_id, repo)
```

**Reality:**
- Actual function: `Singularity.Workflow.FlowBuilder.get_flow/2`
- File: /home/user/singularity-workflows/lib/singularity_workflow/flow_builder.ex, line 230
- Function signature:
```elixir
@spec get_flow(String.t(), module()) :: {:ok, map()} | {:error, :not_found | term()}
def get_flow(workflow_slug, repo) do
```

**Code Reference:**
File: /home/user/singularity-workflows/lib/singularity_workflow/flow_builder.ex
- Lines 210-261: Shows `get_flow` function

**Impact:**
Users will get "function not found" error when calling `get_workflow`. The correct function name is `get_flow`.

**Fix Required:**
Replace line 490 in README:
```elixir
# Get workflow
Singularity.Workflow.FlowBuilder.get_flow(workflow_slug, repo)
```

---

### 2.3 FlowBuilder.list_workflows Should Be list_flows
**Severity:** HIGH | **Type:** Incorrect Function Name

**Location:** README.md, line 493

**README Claims:**
```elixir
Singularity.Workflow.FlowBuilder.list_workflows(repo)
```

**Reality:**
- Actual function: `Singularity.Workflow.FlowBuilder.list_flows/1`
- File: /home/user/singularity-workflows/lib/singularity_workflow/flow_builder.ex, line 199
- Function signature:
```elixir
@spec list_flows(module()) :: {:ok, [map()]} | {:error, term()}
def list_flows(repo) do
```

**Code Reference:**
File: /home/user/singularity-workflows/lib/singularity_workflow/flow_builder.ex
- Lines 174-208: Shows `list_flows` function

**Impact:**
Users will get "function not found" error when calling `list_workflows`. The correct function name is `list_flows`.

**Fix Required:**
Replace line 493 in README:
```elixir
# List workflows
Singularity.Workflow.FlowBuilder.list_flows(repo)
```

---

## 3. INCORRECT FUNCTION PARAMETERS

### 3.1 Parameter Names Don't Match Actual Implementation
**Severity:** MEDIUM | **Type:** Parameter Naming Mismatch

**Location:** README.md, lines 481-484, 490, 493

**README Uses:**
- `workflow_id` - should be `workflow_slug`
- `step_name` - should be `step_slug`
- `name` - parameter doesn't exist as a positional argument

**Reality:**

FlowBuilder functions use:
- `workflow_slug` as the identifier (String, must match `^[a-zA-Z_][a-zA-Z0-9_]*$`)
- `step_slug` as the step identifier

Example from code (line 481 in README vs actual):
```elixir
# README says:
Singularity.Workflow.FlowBuilder.create_flow(name, repo)

# Actual signature:
def create_flow(workflow_slug, _repo, opts \\ [])
```

**Code Reference:**
File: /home/user/singularity-workflows/lib/singularity_workflow/flow_builder.ex
- Lines 70-104: `create_flow` parameter documentation
- Lines 109-142: `add_step` parameter documentation

**Impact:**
While the code will still work (parameter positions are correct), using wrong variable names in documentation is confusing and violates the contract of the API.

**Fix Required:**
Update all README examples to use correct parameter names:
```elixir
# Create workflow
Singularity.Workflow.FlowBuilder.create_flow(workflow_slug, repo)

# Add step
Singularity.Workflow.FlowBuilder.add_step(workflow_slug, step_slug, depends_on, repo)

# Get workflow
Singularity.Workflow.FlowBuilder.get_flow(workflow_slug, repo)
```

---

## 4. INCORRECT EXECUTION OPTIONS

### 4.1 Executor Options Mismatch
**Severity:** HIGH | **Type:** Incorrect Options Documentation

**Location:** README.md, lines 441-451

**README Claims:**
```elixir
opts = [
  timeout: 30_000,           # Execution timeout (ms)
  max_retries: 3,            # Retry failed tasks
  parallel: true,            # Enable parallel execution
  notify_events: true,       # Send NOTIFY events
  execution: :local          # :local (this node) or :distributed (multi-node)
]
```

**Reality:**
Actual documented options in Singularity.Workflow.Executor (lines 115-119):
```elixir
- `:timeout` - Maximum execution time in milliseconds (default: 300_000 = 5 minutes)
- `:poll_interval` - Time between task polls in milliseconds (default: 100)
- `:worker_id` - Worker identifier for task claiming (default: inspect(self()))
```

**Code Reference:**
File: /home/user/singularity-workflows/lib/singularity_workflow/executor.ex
- Lines 105-120: Documented options for execute/4

**Impact:**
Users will attempt to use non-existent options, causing them to be silently ignored. Parallel execution is automatic for independent tasks (DAG-based), not controlled by an option.

**Fix Required:**
Replace the options in README with actual ones:
```elixir
opts = [
  timeout: 300_000,          # Execution timeout in ms (default: 5 minutes)
  poll_interval: 100,        # Time between task polls in ms (default: 100)
  worker_id: "worker_1"      # Worker identifier for task claiming
]
```

---

### 4.2 WorkflowComposer Options Mismatch
**Severity:** MEDIUM | **Type:** Incorrect Options Documentation

**Location:** README.md, lines 365-366

**README Claims:**
```elixir
{:ok, result} = Singularity.Workflow.WorkflowComposer.compose_from_goal(
  "Build authentication system",
  &MyApp.GoalDecomposer.decompose/1,
  step_functions,
  MyApp.Repo,
  optimization_level: :advanced,
  monitoring: true
)
```

**Reality:**
Actual documented options in WorkflowComposer.compose_from_goal (lines 141-147):
```elixir
- `:workflow_name` - Name for the generated workflow
- `:max_depth` - Maximum decomposition depth
- `:max_parallel` - Maximum parallel tasks
- `:retry_attempts` - Retry attempts for failed tasks
- `:timeout` - Execution timeout in milliseconds
- `:optimize` - Enable workflow optimization (default: true)
- `:monitor` - Enable real-time monitoring (default: true)
```

**Code Reference:**
File: /home/user/singularity-workflows/lib/singularity_workflow/workflow_composer.ex
- Lines 129-165: Shows documented options

**Issue:**
- `optimization_level` doesn't exist as a parameter
- The actual option is `:optimize` (boolean), not `optimization_level` (enum)
- `:monitoring` is correct as `:monitor` in the code

**Impact:**
The `optimization_level: :advanced` parameter will be silently ignored. Users who want optimization must use `:optimize: true`.

**Fix Required:**
Replace lines 365-366 in README:
```elixir
{:ok, result} = Singularity.Workflow.WorkflowComposer.compose_from_goal(
  "Build authentication system",
  &MyApp.GoalDecomposer.decompose/1,
  step_functions,
  MyApp.Repo,
  optimize: true,
  monitor: true
)
```

---

## 5. VERSION MISMATCH

### 5.1 Version Number Inconsistency
**Severity:** LOW | **Type:** Version Number Mismatch

**Location:** 
- mix.exs, line 7: `version: "0.1.0"`
- lib/singularity_workflow.ex, line 308: `def version, do: "0.1.5"`
- README.md, line 56: `{:singularity_workflow, "~> 0.1.0"}`

**Issue:**
The version returned by `Singularity.Workflow.version()` function is "0.1.5", but the actual package version in mix.exs is "0.1.0".

**Code References:**
1. /home/user/singularity-workflows/mix.exs, line 7
2. /home/user/singularity-workflows/lib/singularity_workflow.ex, lines 300-308
3. /home/user/singularity-workflows/README.md, line 56

**Impact:**
Users checking the version via `Singularity.Workflow.version()` will get 0.1.5, but the package.json/mix.exs says 0.1.0, causing confusion.

**Fix Required:**
Ensure all three locations have consistent version:
```elixir
# Option 1: Update mix.exs to 0.1.5
version: "0.1.5"

# Option 2: Update singularity_workflow.ex to 0.1.0
def version, do: "0.1.0"

# Option 3: Update README to match chosen version
{:singularity_workflow, "~> 0.1.5"}  # if 0.1.5
```

---

## 6. DOCUMENTATION STRUCTURE ISSUES

### 6.1 Function Names in API Reference Don't Match
**Severity:** MEDIUM | **Type:** Documentation Inconsistency

**Location:** README.md, lines 479-494

**Issue:**
The API Reference section documents function names that don't exist in FlowBuilder:
- `create_flow(name, repo)` - Parameter should be `workflow_slug`
- `add_step(workflow_id, step_name, depends_on, repo)` - Parameters should be `workflow_slug, step_slug`
- `add_map_step(...)` - Function doesn't exist
- `get_workflow(workflow_id, repo)` - Should be `get_flow(workflow_slug, repo)`
- `list_workflows(repo)` - Should be `list_flows(repo)`

**Code Reference:**
File: /home/user/singularity-workflows/lib/singularity_workflow/flow_builder.ex
- Lines 65-104: Correct create_flow signature
- Lines 106-172: Correct add_step signature
- Lines 210-261: Correct get_flow signature
- Lines 174-208: Correct list_flows signature

**Fix Required:**
Replace entire section with correct function names and parameters.

---

## 7. CODE EXAMPLES WITH INCORRECT PARAMETER NAMES

### 7.1 Dynamic Workflow Example Uses Wrong Parameter Names
**Severity:** LOW | **Type:** Parameter Naming

**Location:** README.md, lines 284-304

**Example:**
```elixir
{:ok, workflow_id} = Singularity.Workflow.FlowBuilder.create_flow("ai_generated_workflow", MyApp.Repo)

{:ok, _} = Singularity.Workflow.FlowBuilder.add_step(workflow_id, "analyze", [], MyApp.Repo)
```

**Issue:**
- `workflow_id` variable is actually a map (workflow), not just an ID
- Parameter name should be `workflow_slug` (it's a string identifier)
- This doesn't cause functional problems, but violates naming conventions

**Impact:**
Minor - code will work, but naming is misleading.

**Fix Required:**
Rename variable for clarity:
```elixir
{:ok, workflow} = Singularity.Workflow.FlowBuilder.create_flow("ai_generated_workflow", MyApp.Repo)

{:ok, _} = Singularity.Workflow.FlowBuilder.add_step("ai_generated_workflow", "analyze", [], MyApp.Repo)
```

---

## SUMMARY TABLE

| # | Issue | Type | Severity | README Location | Actual Location |
|---|-------|------|----------|-----------------|-----------------|
| 1 | Missing examples/ directory | Missing Resource | MEDIUM | Lines 567-579 | N/A |
| 2 | add_map_step doesn't exist | API Function | HIGH | Line 487 | flow_builder.ex:146 |
| 3 | get_workflow should be get_flow | Function Name | HIGH | Line 490 | flow_builder.ex:230 |
| 4 | list_workflows should be list_flows | Function Name | HIGH | Line 493 | flow_builder.ex:199 |
| 5 | Parameter: workflow_id → workflow_slug | Parameter Name | MEDIUM | Lines 481-493 | flow_builder.ex docs |
| 6 | Parameter: step_name → step_slug | Parameter Name | MEDIUM | Lines 484-487 | flow_builder.ex docs |
| 7 | Executor options completely wrong | Options | HIGH | Lines 441-451 | executor.ex:115-119 |
| 8 | optimization_level option doesn't exist | Options | MEDIUM | Lines 365-366 | workflow_composer.ex:146 |
| 9 | Version 0.1.5 vs 0.1.0 mismatch | Version | LOW | Line 56 | executor.ex:308, mix.exs:7 |
| 10 | API Reference function names | Documentation | MEDIUM | Lines 479-494 | flow_builder.ex |
| 11 | Example uses wrong parameter names | Examples | LOW | Lines 284-304 | flow_builder.ex docs |

---

## TEST COVERAGE ANALYSIS

**Correct Claims:**
- ✅ 26 test files found (matches repo structure)
- ✅ 678 test cases found via grep (correct count)
- ✅ Testing section examples reference correct module names

**Verified Working Tests:**
- /home/user/singularity-workflows/test/singularity_workflow/executor_test.exs
- /home/user/singularity-workflows/test/singularity_workflow/flow_builder_test.exs
- /home/user/singularity-workflows/test/singularity_workflow/notifications_test.exs
- /home/user/singularity-workflows/test/singularity_workflow/executor_test.exs

---

## CODE QUALITY VERIFICATION

**Verified Correct:**
- ✅ Credo linting available (mix credo)
- ✅ Dialyzer type checking available
- ✅ Sobelow security scanning available
- ✅ Test coverage reporting via ExCoveralls

---

## SECTIONS WITH CORRECT DOCUMENTATION

The following sections are documented correctly and match the implementation:

1. **Quick Start Installation** (lines 49-119)
   - ✅ Correct mix.exs dependency syntax
   - ✅ Correct configuration examples
   - ✅ Correct basic usage example

2. **Architecture Overview** (lines 121-160)
   - ✅ Core components correctly described
   - ✅ Real-time messaging correctly explained

3. **Real-time Messaging** (lines 162-232)
   - ✅ `send_with_notify` function correct
   - ✅ `listen` and `unlisten` functions correct
   - ✅ `notify_only` function correct
   - ✅ Notification types documented correctly

4. **Workflow Types - Static Workflows** (lines 234-276)
   - ✅ `__workflow_steps__` syntax correct
   - ✅ Example code matches actual API

5. **Workflow Types - Dynamic Workflows** (lines 278-305)
   - ⚠️  Mostly correct but parameter names misleading (see issue #7)

6. **Map Steps / Bulk Processing** (lines 307-332)
   - ✅ `initial_tasks` parameter usage correct

7. **HTDAG Orchestration** (lines 334-387)
   - ✅ WorkflowComposer.compose_from_goal correct
   - ⚠️  Option names incorrect (see issue #8)

8. **Phoenix Integration** (lines 389-427)
   - ✅ listen/unlisten functions correct
   - ✅ LiveView example correct

9. **Workflow Lifecycle Management** (lines 454-475)
   - ✅ All functions exist and signatures correct:
     - `get_run_status` ✓
     - `list_workflow_runs` ✓
     - `pause_workflow_run` ✓
     - `resume_workflow_run` ✓
     - `cancel_workflow_run` ✓
     - `retry_failed_workflow` ✓

10. **Testing Section** (lines 512-561)
    - ✅ Test commands correct
    - ✅ Test file structure examples correct

11. **Deployment Section** (lines 581-636)
    - ✅ Configuration examples correct
    - ✅ Docker and Kubernetes examples correct

12. **Contributing Section** (lines 638-681)
    - ✅ Setup instructions correct
    - ✅ Quality tools configuration correct

---

## RECOMMENDED FIXES PRIORITY

### Critical (Fix Immediately)
1. Remove or fix `add_map_step` reference - **HIGH IMPACT**
2. Correct `get_workflow` → `get_flow` - **HIGH IMPACT**
3. Correct `list_workflows` → `list_flows` - **HIGH IMPACT**
4. Fix Executor options documentation - **HIGH IMPACT**

### High Priority
5. Fix WorkflowComposer options (`optimization_level` → `optimize`) - **MEDIUM IMPACT**
6. Update all parameter names (workflow_id → workflow_slug, step_name → step_slug) - **MEDIUM IMPACT**

### Medium Priority
7. Create examples directory or remove Examples section - **MEDIUM IMPACT**
8. Fix version consistency across files - **LOW IMPACT**
9. Update dynamic workflow example variable names - **LOW IMPACT**

### Low Priority
10. Review and update comprehensive API Reference table (lines 479-494)

---

## CONCLUSION

The Singularity.Workflow library is well-documented overall, but there are **11 significant discrepancies** between the README and actual code implementation. The most critical issues are:

1. **Non-existent functions** being documented (add_map_step)
2. **Incorrect function names** in API Reference (get_workflow, list_workflows)
3. **Wrong options documentation** for critical functions (Executor, WorkflowComposer)
4. **Missing resources** (examples directory)

All identified issues are correctable through README updates or minor code/documentation alignment. The actual library implementation is solid; the discrepancies are primarily in the documentation layer.

**Recommended Action:** Create an issue to systematically address all discrepancies with pull requests to update README.md accordingly.
