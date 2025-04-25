defmodule Foundation.MixProject do
  use Mix.Project

  @version File.read!("../../version.txt")

  def project do
    [
      app: :foundation,
      version: @version,
      name: "Foundation",
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
      mod: {Foundation.Application, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def test_coverage do
    [
      summary: [threshold: 94],
      ignore_modules: [
        Foundation.Rpc,
        Foundation.RpcMock,
        Foundation.Macros,
        Foundation.Application
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.2"},
      {:finch, "~> 0.13"},
      {:plug_crypto, "~> 2.1.0"},
      {:bcrypt_elixir, "~> 3.0"},
      # Used by Config Provider only
      {:ex_aws, "~> 2.1"},
      {:goth, "~> 1.4"},
      {:yaml_elixir, "~> 2.0"},
      # Static Analysis
      {:mox, "~> 1.0", only: :test}
    ]
  end
end
