# Test Report

date: 2025-11-09T23:53:39Z

## Summary

- Bootstrapped all Mix dependencies offline via `scripts/bootstrap_deps.exs` and compiled the project in the test environment using the path overrides controlled by `BOOTSTRAP_HEX_DEPS`. 【0d28f4†L1-L88】【55e75c†L1-L2】
- Installed PostgreSQL 16, started the cluster, and set the default `postgres` user's password to match the configuration used in `config/test.exs`. 【a7164c†L1-L13】【4e2311†L1-L1】【015903†L1-L5】
- Database migrations fail because the required `pgmq` extension is not available in the system PostgreSQL installation; as a result, schema objects and stored procedures referenced by the test suite are missing. 【36dab8†L1-L11】
- With the database skipped (`SINGULARITY_WORKFLOW_SKIP_DB=1`), the ExUnit suite aborts on the first test because the `Singularity.Workflow.Repo` sandbox cannot be checked out, demonstrating that database-backed tests still require the repo to be running even when migrations are bypassed. 【09ef84†L1-L23】

## Logs

- Manual dependency bootstrap downloads Hex tarballs and unpacks them into `deps/`. 【4e9b5f†L1-L90】
- Compiling the application after bootstrapping succeeds. 【55e75c†L1-L2】
- Attempting to run migrations raises `ERROR 0A000 (feature_not_supported) extension "pgmq" is not available`. 【36dab8†L1-L11】
- `mix test --max-failures 1` exits early because the repo cannot be checked out, even when the database startup is skipped via environment variable. 【09ef84†L1-L23】【8de6bf†L1-L33】

## Next Steps for Release Readiness

1. Install the `pgmq` PostgreSQL extension (or adjust the migrations to skip it in CI) so that `mix ecto.migrate` can succeed. 【36dab8†L1-L11】
2. Provide a lightweight `Singularity.Workflow.Repo` stub or start the repo under `SINGULARITY_WORKFLOW_SKIP_DB=1` so ExUnit can check out the sandbox during tests. 【09ef84†L1-L23】
3. After the database issues are resolved, run the full `mix test` suite and the quality checks (`mix quality`) before cutting a release.
