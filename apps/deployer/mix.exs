defmodule Deployer.MixProject do
  use Mix.Project

  @version File.read!("../../version.txt")

  def project do
    [
      app: :deployer,
      version: @version,
      name: "Deployer",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: test_coverage()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Deployer.Application, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def test_coverage do
    [
      summary: [threshold: 98],
      ignore_modules: [
        Deployer.Application,
        Deployer.Monitor.Supervisor,
        Deployer.Release.Version,
        Deployer.Fixture.Binary,
        Foundation.Fixture.Catalog
      ]
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
