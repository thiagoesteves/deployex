defmodule Deployex.MixProject do
  use Mix.Project

  def project do
    [
      app: :deployex,
      version: "0.3.0-rc5",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      description: description(),
      releases: [
        deployex: [
          include_executable_for: [:unix],
          steps: [:assemble, :tar],
          config_providers: [
            {Deployex.AwsSecretsManagerProvider, nil}
          ]
        ]
      ],
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],
      aliases: aliases()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Deployex.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp description do
    """
    Deployex is a tool designed for managing deployments for Elixir applications
    """
  end

  defp package do
    [
      files: ["lib", "priv", "mix.exs", "README.md", "LICENSE.md", ".formatter.exs"],
      maintainers: ["Thiago Esteves"],
      licenses: ["MIT"],
      links: %{
        Documentation: "https://hexdocs.pm/deployex",
        Changelog: "https://hexdocs.pm/deployex/changelog.html",
        GitHub: "https://github.com/deployex/deployex"
      }
    ]
  end

  defp docs do
    [
      source_url: "https://github.com/thiagoesteves/deployex",
      homepage_url: "https://github.com/thiagoesteves/deployex",
      main: "home"
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.7.12"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.20.2"},
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
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.2"},
      {:briefly, "~> 0.4.1"},
      {:configparser_ex, "~> 4.0"},
      {:erlexec, "~> 2.0.6"},
      {:ex_aws, "~> 2.1"},
      {:ex_aws_s3, "~> 2.0"},
      {:hackney, "~> 1.9"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
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
      "assets.build": ["tailwind deployex", "esbuild deployex"],
      "assets.deploy": [
        "tailwind deployex --minify",
        "esbuild deployex --minify",
        "phx.digest"
      ]
    ]
  end
end
