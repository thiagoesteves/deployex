defmodule Host.MixProject do
  use Mix.Project

  @version File.read!("../../version.txt")

  def project do
    [
      app: :host,
      version: @version,
      name: "Host Commander",
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
      mod: {Host.Application, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def test_coverage do
    [
      summary: [threshold: 94],
      ignore_modules: [
        Host.Memory,
        Host.Commander.Local,
        Host.Terminal.Server.Message,
        Host.Application
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:erlexec, "~> 2.0.7"},
      {:phoenix_pubsub, "~> 2.0"},
      {:jason, "~> 1.2"},
      # Static Analysis
      {:mox, "~> 1.0", only: :test}
    ]
  end
end
