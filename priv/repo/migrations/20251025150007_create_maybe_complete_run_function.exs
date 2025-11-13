defmodule Singularity.Workflow.Repo.Migrations.CreateMaybeCompleteRunFunction do
  @moduledoc """
  Creates singularity_workflow.maybe_complete_run() for checking and completing workflow runs.

  Matches Singularity.Workflow's implementation:
  1. Check if all steps are completed (remaining_steps = 0)
  2. If yes, mark run as completed
  3. Aggregate outputs from leaf steps (steps with no dependents) into a flat array
  4. Set run.output to aggregated leaf outputs

  Called by complete_task() when a step completes.
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION singularity_workflow.maybe_complete_run(p_run_id UUID)
    RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_completed_run workflow_runs%ROWTYPE;
    BEGIN
      -- Complete run if all steps are done
      UPDATE workflow_runs
      SET
        status = 'completed',
        completed_at = NOW(),
        -- Aggregate outputs from leaf steps (steps with no dependents)
        output = (
          SELECT jsonb_agg(output)
          FROM (
            SELECT DISTINCT
              leaf_state.step_slug,
              -- For now, just get the first task's output
              -- NOTE: Map step aggregation deferred
              -- Future enhancement: Aggregate outputs from map steps (multiple tasks per step)
              (SELECT t.output
               FROM workflow_step_tasks t
               WHERE t.run_id = leaf_state.run_id
                 AND t.step_slug = leaf_state.step_slug
                 AND t.status = 'completed'
               LIMIT 1) as output
            FROM workflow_step_states leaf_state
            WHERE leaf_state.run_id = maybe_complete_run.p_run_id
              AND leaf_state.status = 'completed'
              AND NOT EXISTS (
                SELECT 1
                FROM workflow_step_dependencies dep
                WHERE dep.run_id = leaf_state.run_id
                  AND dep.depends_on_step = leaf_state.step_slug
              )
          ) leaf_outputs
        )
      WHERE workflow_runs.id = maybe_complete_run.p_run_id
        AND workflow_runs.remaining_steps = 0
        AND workflow_runs.status != 'completed'
      RETURNING * INTO v_completed_run;

      -- Log completion (optional: would broadcast event in Singularity.Workflow)
      IF v_completed_run.id IS NOT NULL THEN
        RAISE NOTICE 'Run completed: run_id=%, output=%',
          v_completed_run.id, v_completed_run.output;
      END IF;
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION singularity_workflow.maybe_complete_run(UUID) IS
    'Checks if run is complete (all steps done), marks as completed, and aggregates leaf step outputs into a flat array. Matches Singularity.Workflow implementation.'
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS singularity_workflow.maybe_complete_run(UUID)")
  end
end
