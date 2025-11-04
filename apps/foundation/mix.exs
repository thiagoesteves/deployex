defmodule Foundation.MixProject do
  use Mix.Project

  def project do
    [
      app: :foundation,
      version: Mix.Shared.version(),
      name: "Foundation",
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
      mod: {Foundation.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.2"},
      {:finch, "~> 0.13"},
      {:plug_crypto, "~> 2.1.0"},
      {:bcrypt_elixir, "~> 3.0"},
      {:phoenix_pubsub, "~> 2.0"},
      # Used by Config Provider only
      {:configparser_ex, "~> 4.0"},
      {:ex_aws, "~> 2.1"},
      {:goth, "~> 1.4"},
      {:yaml_elixir, "~> 2.0"},
      # Static Analysis
      {:mox, "~> 1.0", only: :test}
    ]
  end
end
