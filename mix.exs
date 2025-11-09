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
      {:jason, "~> 1.4"},

      # Observability
      {:telemetry, "~> 1.0"},

      # Development and testing
      {:mox, "~> 1.2", only: :test},

      # pgmq client
      {:pgmq, "~> 0.4"},

      # Job queue for background processing
      {:oban, "~> 2.17"},

      # Code quality and security (dev only)
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},

      # Documentation
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
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
end
