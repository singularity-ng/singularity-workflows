# credo:disable-for-this-file Credo.Check.Refactor.CondStatements
defmodule Singularity.Workflow.Orchestrator.ExampleDecomposer do
  @moduledoc """
  Example decomposer implementations for HTDAG.

  Provides sample decomposer functions that demonstrate how to create
  custom goal decomposition logic for different types of workflows.

  ## Usage

      # Use a simple decomposer
      {:ok, result} = Singularity.Workflow.WorkflowComposer.compose_from_goal(
        "Build user authentication system",
        &Singularity.Workflow.Orchestrator.ExampleDecomposer.simple_decompose/1,
        step_functions,
        MyApp.Repo
      )
      
      # Use a microservices decomposer
      {:ok, result} = Singularity.Workflow.WorkflowComposer.compose_from_goal(
        "Deploy microservices architecture",
        &Singularity.Workflow.Orchestrator.ExampleDecomposer.microservices_decompose/1,
        step_functions,
        MyApp.Repo
      )
  """

  @doc """
  Simple decomposer for basic workflows.

  Decomposes goals into a linear sequence of tasks.
  """
  @spec simple_decompose(String.t() | map()) :: {:ok, map()} | {:error, term()}
  def simple_decompose(goal) do
    goal_string = normalize_goal(goal)

    tasks =
      cond do
        String.match?(goal_string, ~r/auth|authentication|login/i) ->
          [
            %{id: "validate_input", description: "Validate user input", depends_on: []},
            %{
              id: "hash_password",
              description: "Hash user password",
              depends_on: ["validate_input"]
            },
            %{id: "create_user", description: "Create user account", depends_on: ["hash_password"]},
            %{id: "send_welcome", description: "Send welcome email", depends_on: ["create_user"]}
          ]

        String.match?(goal_string, ~r/deploy|deployment/i) ->
          [
            %{id: "check_prerequisites", description: "Check system prerequisites", depends_on: []},
            %{
              id: "build_artifacts",
              description: "Build deployment artifacts",
              depends_on: ["check_prerequisites"]
            },
            %{
              id: "deploy_services",
              description: "Deploy services to environment",
              depends_on: ["build_artifacts"]
            },
            %{
              id: "run_tests",
              description: "Run integration tests",
              depends_on: ["deploy_services"]
            },
            %{
              id: "verify_deployment",
              description: "Verify deployment success",
              depends_on: ["run_tests"]
            }
          ]

        String.match?(goal_string, ~r/process|analyze|data/i) ->
          [
            %{id: "fetch_data", description: "Fetch data from sources", depends_on: []},
            %{
              id: "validate_data",
              description: "Validate data quality",
              depends_on: ["fetch_data"]
            },
            %{
              id: "process_data",
              description: "Process and transform data",
              depends_on: ["validate_data"]
            },
            %{
              id: "save_results",
              description: "Save processed results",
              depends_on: ["process_data"]
            }
          ]

        true ->
          [
            %{id: "analyze_goal", description: "Analyze goal requirements", depends_on: []},
            %{
              id: "plan_execution",
              description: "Plan execution strategy",
              depends_on: ["analyze_goal"]
            },
            %{id: "execute_plan", description: "Execute the plan", depends_on: ["plan_execution"]},
            %{
              id: "verify_completion",
              description: "Verify goal completion",
              depends_on: ["execute_plan"]
            }
          ]
      end

    {:ok, tasks}
  end

  @doc """
  Microservices decomposer for complex distributed systems.

  Decomposes goals into parallel microservice deployment tasks.
  """
  @spec microservices_decompose(String.t() | map()) :: {:ok, map()} | {:error, term()}
  def microservices_decompose(goal) do
    goal_string = normalize_goal(goal)

    tasks =
      cond do
        String.match?(goal_string, ~r/microservices|microservice/i) ->
          [
            # Infrastructure tasks (can run in parallel)
            %{id: "setup_database", description: "Setup database cluster", depends_on: []},
            %{id: "setup_redis", description: "Setup Redis cache", depends_on: []},
            %{id: "setup_message_queue", description: "Setup message queue", depends_on: []},
            %{id: "setup_monitoring", description: "Setup monitoring stack", depends_on: []},

            # Service deployment tasks (depend on infrastructure)
            %{
              id: "deploy_auth_service",
              description: "Deploy authentication service",
              depends_on: ["setup_database", "setup_redis"]
            },
            %{
              id: "deploy_api_gateway",
              description: "Deploy API gateway",
              depends_on: ["deploy_auth_service"]
            },
            %{
              id: "deploy_user_service",
              description: "Deploy user management service",
              depends_on: ["setup_database", "deploy_auth_service"]
            },
            %{
              id: "deploy_notification_service",
              description: "Deploy notification service",
              depends_on: ["setup_message_queue", "deploy_auth_service"]
            },

            # Integration tasks
            %{
              id: "configure_services",
              description: "Configure service communication",
              depends_on: [
                "deploy_api_gateway",
                "deploy_user_service",
                "deploy_notification_service"
              ]
            },
            %{
              id: "setup_load_balancer",
              description: "Setup load balancer",
              depends_on: ["configure_services"]
            },
            %{
              id: "run_integration_tests",
              description: "Run integration tests",
              depends_on: ["setup_load_balancer"]
            },
            %{
              id: "verify_deployment",
              description: "Verify complete deployment",
              depends_on: ["run_integration_tests"]
            }
          ]

        true ->
          # Fallback to simple decomposition
          [
            %{id: "analyze_goal", description: "Analyze goal requirements", depends_on: []},
            %{
              id: "plan_execution",
              description: "Plan execution strategy",
              depends_on: ["analyze_goal"]
            },
            %{id: "execute_plan", description: "Execute the plan", depends_on: ["plan_execution"]},
            %{
              id: "verify_completion",
              description: "Verify goal completion",
              depends_on: ["execute_plan"]
            }
          ]
      end

    {:ok, tasks}
  end

  @doc """
  Data pipeline decomposer for ETL workflows.

  Decomposes goals into data extraction, transformation, and loading tasks.
  """
  @spec data_pipeline_decompose(String.t() | map()) :: {:ok, map()} | {:error, term()}
  def data_pipeline_decompose(goal) do
    goal_string = normalize_goal(goal)

    tasks =
      cond do
        String.match?(goal_string, ~r/data|pipeline|etl|extract|transform|load/i) ->
          [
            # Extraction tasks (can run in parallel)
            %{id: "extract_users", description: "Extract user data", depends_on: []},
            %{id: "extract_orders", description: "Extract order data", depends_on: []},
            %{id: "extract_products", description: "Extract product data", depends_on: []},

            # Transformation tasks
            %{
              id: "validate_data",
              description: "Validate extracted data",
              depends_on: ["extract_users", "extract_orders", "extract_products"]
            },
            %{
              id: "clean_data",
              description: "Clean and normalize data",
              depends_on: ["validate_data"]
            },
            %{
              id: "transform_data",
              description: "Transform data for target format",
              depends_on: ["clean_data"]
            },

            # Loading tasks
            %{
              id: "load_to_warehouse",
              description: "Load data to data warehouse",
              depends_on: ["transform_data"]
            },
            %{
              id: "create_aggregates",
              description: "Create data aggregates",
              depends_on: ["load_to_warehouse"]
            },
            %{
              id: "update_analytics",
              description: "Update analytics dashboards",
              depends_on: ["create_aggregates"]
            }
          ]

        true ->
          simple_decompose(goal)
      end

    {:ok, tasks}
  end

  @doc """
  Machine learning decomposer for ML workflows.

  Decomposes goals into data preparation, model training, and deployment tasks.
  """
  @spec ml_pipeline_decompose(String.t() | map()) :: {:ok, map()} | {:error, term()}
  def ml_pipeline_decompose(goal) do
    goal_string = normalize_goal(goal)

    tasks =
      cond do
        String.match?(goal_string, ~r/ml|machine learning|model|training|prediction/i) ->
          [
            # Data preparation
            %{id: "collect_data", description: "Collect training data", depends_on: []},
            %{
              id: "clean_data",
              description: "Clean and preprocess data",
              depends_on: ["collect_data"]
            },
            %{
              id: "split_data",
              description: "Split data into train/validation/test",
              depends_on: ["clean_data"]
            },

            # Model development
            %{
              id: "feature_engineering",
              description: "Engineer features",
              depends_on: ["split_data"]
            },
            %{
              id: "train_model",
              description: "Train machine learning model",
              depends_on: ["feature_engineering"]
            },
            %{
              id: "validate_model",
              description: "Validate model performance",
              depends_on: ["train_model"]
            },

            # Model deployment
            %{
              id: "package_model",
              description: "Package model for deployment",
              depends_on: ["validate_model"]
            },
            %{
              id: "deploy_model",
              description: "Deploy model to production",
              depends_on: ["package_model"]
            },
            %{
              id: "monitor_model",
              description: "Setup model monitoring",
              depends_on: ["deploy_model"]
            }
          ]

        true ->
          simple_decompose(goal)
      end

    {:ok, tasks}
  end

  # Private functions

  @spec normalize_goal(String.t()) :: String.t()
  defp normalize_goal(goal) when is_binary(goal), do: goal

  @spec normalize_goal(map()) :: String.t()
  defp normalize_goal(goal) when is_map(goal) do
    Map.get(goal, :description, Map.get(goal, :goal, "unknown"))
  end

  @spec normalize_goal(term()) :: String.t()
  defp normalize_goal(goal), do: to_string(goal)
end
