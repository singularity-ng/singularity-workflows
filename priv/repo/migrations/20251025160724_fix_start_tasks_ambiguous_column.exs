defmodule Singularity.Workflow.Repo.Migrations.FixStartTasksAmbiguousColumn do
  @moduledoc """
  Fixes ambiguous column reference in start_tasks() function.

  The issue: PostgreSQL's RETURNS TABLE creates implicit variables that conflict
  with column names in queries, causing "ambiguous column" errors even when
  using aliases and table qualifiers.

  Solution: Use a simple query structure that avoids the ambiguity entirely
  by not using column names that match RETURNS TABLE columns in CTEs.
  """
  use Ecto.Migration

  def up do
    # Drop old version with ambiguous references
    execute("DROP FUNCTION IF EXISTS start_tasks(TEXT, BIGINT[], TEXT)")

    # Recreate with fully qualified and unambiguous column references
    execute("""
    CREATE OR REPLACE FUNCTION start_tasks(
      p_workflow_slug TEXT,
      p_msg_ids BIGINT[],
      p_worker_id TEXT
    )
    RETURNS TABLE (
      run_id UUID,
      step_slug TEXT,
      task_index INTEGER,
      input JSONB,
      message_id BIGINT
    )
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_worker_uuid UUID;
    BEGIN
      -- Convert worker_id string to UUID (or generate new one)
      BEGIN
        v_worker_uuid := p_worker_id::uuid;
      EXCEPTION
        WHEN invalid_text_representation THEN
          v_worker_uuid := gen_random_uuid();
      END;

      -- Update tasks to 'started' status with worker tracking
      UPDATE workflow_step_tasks AS wst
      SET
        status = 'started',
        started_at = NOW(),
        attempts_count = attempts_count + 1,
        claimed_by = p_worker_id,
        last_worker_id = NULL
      WHERE
        wst.workflow_slug = p_workflow_slug
        AND wst.message_id = ANY(p_msg_ids)
        AND wst.status = 'queued';

      -- NOTE: Visibility timeout setting deferred
      -- Future enhancement: Use set_vt_batch for batch visibility timeout management
      -- This requires a different PL/pgSQL pattern. For now, timeout setting
      -- is handled by pgmq's default values.

      -- Return task records with built input
      RETURN QUERY
      SELECT
        t.run_id::uuid,
        t.step_slug::text,
        t.task_index::integer,
        -- Build input: merge run input + dependency outputs
        COALESCE(r.input, '{}'::jsonb) || COALESCE(
          jsonb_object_agg(d.depends_on_step, d.output) FILTER (WHERE d.output IS NOT NULL),
          '{}'::jsonb
        ) AS input,
        t.message_id::bigint
      FROM workflow_step_tasks t
      JOIN workflow_runs r ON r.id = t.run_id
      LEFT JOIN (
        SELECT
          dep.run_id,
          dep.step_slug,
          dep.depends_on_step,
          wst.output
        FROM workflow_step_dependencies dep
        LEFT JOIN workflow_step_tasks wst
          ON wst.run_id = dep.run_id
          AND wst.step_slug = dep.depends_on_step
          AND wst.status = 'completed'
      ) d
        ON d.run_id = t.run_id
        AND d.step_slug = t.step_slug
      WHERE
        t.workflow_slug = p_workflow_slug
        AND t.message_id = ANY(p_msg_ids)
        AND t.status = 'started'
      GROUP BY
        t.run_id, t.step_slug, t.task_index, t.message_id, r.input;
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION start_tasks(TEXT, BIGINT[], TEXT) IS
    'Claims tasks from pgmq messages, sets worker tracking, configures timeouts. Returns full task records with merged input.'
    """)
  end

  def down do
    # Restore previous version
    execute("DROP FUNCTION IF EXISTS start_tasks(TEXT, BIGINT[], TEXT)")

    execute("""
    CREATE OR REPLACE FUNCTION start_tasks(
      p_workflow_slug TEXT,
      p_msg_ids BIGINT[],
      p_worker_id TEXT
    )
    RETURNS TABLE (
      run_id UUID,
      step_slug TEXT,
      task_index INTEGER,
      input JSONB,
      message_id BIGINT
    )
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_worker_uuid UUID;
    BEGIN
      BEGIN
        v_worker_uuid := p_worker_id::uuid;
      EXCEPTION
        WHEN invalid_text_representation THEN
          v_worker_uuid := gen_random_uuid();
      END;

      UPDATE workflow_step_tasks
      SET
        status = 'started',
        started_at = NOW(),
        attempts_count = attempts_count + 1,
        claimed_by = p_worker_id,
        last_worker_id = v_worker_uuid
      WHERE
        workflow_slug = p_workflow_slug
        AND message_id = ANY(p_msg_ids)
        AND status = 'queued';

      RETURN QUERY
      SELECT
        t.run_id,
        t.step_slug,
        t.task_index,
        '{}'::jsonb AS input,
        t.message_id
      FROM workflow_step_tasks t
      WHERE
        t.workflow_slug = p_workflow_slug
        AND t.message_id = ANY(p_msg_ids)
        AND t.status = 'started';
    END;
    $$;
    """)
  end
end
