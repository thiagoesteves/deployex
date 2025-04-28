defmodule Deployer.MixProject do
  use Mix.Project

  def project do
    [
      app: :deployer,
      version: Mix.Shared.version(),
      name: "Deployer",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: Mix.Shared.elixir(),
      elixirc_paths: Mix.Shared.elixirc_paths(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: Mix.Shared.test_coverage()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Deployer.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.2"},
      {:finch, "~> 0.13"},
      {:phoenix_pubsub, "~> 2.0"},
      {:ex_aws, "~> 2.1"},
      {:ex_aws_s3, "~> 2.0"},
      {:goth, "~> 1.4"},
      {:briefly, "~> 0.4.1"},
      # Static Analysis
      {:mox, "~> 1.0", only: :test},
      {:mock, "~> 0.3.0", only: :test},
      # Application dependencies
      {:foundation, in_umbrella: true},
      {:host, in_umbrella: true}
    ]
  end
end
