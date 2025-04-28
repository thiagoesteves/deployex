defmodule Host.MixProject do
  use Mix.Project

  def project do
    [
      app: :host,
      version: MixShared.version(),
      name: "Host Commander",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: MixShared.elixir(),
      elixirc_paths: MixShared.elixirc_paths(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: MixShared.test_coverage()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Host.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:erlexec, "~> 2.0.7"},
      {:phoenix_pubsub, "~> 2.0"},
      {:jason, "~> 1.2"},
      # Static Analysis
      {:mox, "~> 1.0", only: :test},
      # Application dependencies
      {:foundation, in_umbrella: true}
    ]
  end
end
