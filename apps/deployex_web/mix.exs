defmodule DeployexWeb.MixProject do
  use Mix.Project

  @version File.read!("../../version.txt")

  def project do
    [
      app: :deployex_web,
      name: "Deployex Web",
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: test_coverage()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {DeployexWeb.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def test_coverage do
    [
      summary: [threshold: 98],
      ignore_modules: [
        DeployexWeb.Application,
        DeployexWeb.Layouts,
        DeployexWeb.PageHTML,
        DeployexWeb.Telemetry,
        DeployexWeb.ErrorHTML,
        DeployexWeb.CoreComponents,
        DeployexWeb.Fixture.Status,
        DeployexWeb.Fixture.Binary,
        DeployexWeb.Fixture.Monitoring,
        DeployexWeb.Fixture.Nodes,
        DeployexWeb.Fixture.Terminal
      ]
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.7.20"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0.0"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.5"},
      {:finch, "~> 0.13"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.5"},
      {:observer_web, "~> 0.1.0"},
      # Static Analysis
      {:mox, "~> 1.0", only: :test},
      {:mock, "~> 0.3.0", only: :test},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      # Application dependencies
      {:foundation, in_umbrella: true},
      {:host, in_umbrella: true},
      {:sentinel, in_umbrella: true},
      {:deployer, in_umbrella: true}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind deployex_web", "esbuild deployex_web"],
      "assets.deploy": [
        "tailwind deployex_web --minify",
        "esbuild deployex_web --minify",
        "phx.digest"
      ]
    ]
  end
end
