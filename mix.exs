defmodule Singularity.Workflow.MixProject do
  use Mix.Project

  def project do
    [
      app: :singularity_workflow,
      version: "0.1.5",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      dialyzer: dialyzer(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # JSON handling
      dep(:jason, "~> 1.4"),

      # Observability
      dep(:telemetry, "~> 1.0"),

      # Development and testing
      dep(:mox, "~> 1.2", only: :test),

      # pgmq client
      dep(:pgmq, "~> 0.4"),

      # Job queue for background processing
      dep(:oban, "~> 2.17"),

      # Code quality and security (dev only)
      dep(:credo, "~> 1.7", only: [:dev, :test], runtime: false),
      dep(:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false),
      dep(:sobelow, "~> 0.13", only: [:dev, :test], runtime: false),
      dep(:excoveralls, "~> 0.18", only: :test),

      # Documentation
      # Disabled in CI due to proxy TLS issues fetching Hex packages
      # {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "Singularity.Workflow",
      source_url: "https://github.com/Singularity-ng/singularity-workflows",
      extras: ["README.md"]
    ]
  end

  defp package do
    [
      name: "singularity_workflow",
      description: "PostgreSQL-based workflow orchestration library for Elixir",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/Singularity-ng/singularity-workflows",
        "Documentation" => "https://hexdocs.pm/singularity_workflow"
      },
      maintainers: ["Mikko H"],
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE.md)
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix, :ex_unit]
    ]
  end

  defp aliases do
    [
      # Code quality tasks
      quality: [
        "format --check-formatted",
        "credo --strict",
        "dialyzer",
        "sobelow --exit-on-warning",
        "deps.audit"
      ],
      # Fix code quality issues
      "quality.fix": [
        "format",
        "credo --strict --fix"
      ],
      # Setup tasks
      setup: ["deps.get", "ecto.create", "ecto.migrate"],
      # Testing
      "test.watch": ["test --listen-on-stdin"],
      "test.coverage": ["coveralls.html"]
    ]
  end

  defp dep(app, requirement, opts \\ []) do
    if bootstrap_deps?() do
      opts
      |> Keyword.put(:path, Path.join("deps", Atom.to_string(app)))
      |> Keyword.put_new(:override, true)
      |> then(&{app, &1})
    else
      if opts == [] do
        {app, requirement}
      else
        {app, requirement, opts}
      end
    end
  end

  defp bootstrap_deps? do
    System.get_env("BOOTSTRAP_HEX_DEPS") in ["1", "true"]
  end
end
