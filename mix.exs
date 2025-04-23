defmodule Deployex.MixProject do
  use Mix.Project

  @source_url "https://github.com/thiagoesteves/deployex"
  @version "0.4.1"

  def project do
    [
      app: :deployex,
      version: @version,
      elixir: "~> 1.15",
      name: "DeployEx",
      description:
        "Application designed for managing deployments for Beam applications (Elixir, Gleam and Erlang)",
      source_url: "https://github.com/thiagoesteves/deployex",
      homepage_url: "https://github.com/thiagoesteves/deployex",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ],
      docs: docs(),
      package: package(),
      description: description(),
      releases: [
        deployex: [
          include_executable_for: [:unix],
          steps: [:assemble, :tar],
          config_providers: [
            {Deployex.ConfigProvider.Env.Config, nil},
            {Deployex.ConfigProvider.Secrets.Manager, nil}
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
    env_specific_applications =
      if Mix.env() == :dev do
        [:wx, :observer]
      else
        []
      end

    [
      mod: {Deployex.Application, []},
      extra_applications: [:logger, :runtime_tools, :sasl | env_specific_applications]
    ]
  end

  defp description do
    """
    Deployex is a tool designed for managing deployments for Elixir applications
    """
  end

  defp package do
    [
      files: [
        "lib",
        "priv",
        "mix.exs",
        "README.md",
        "LICENSE.md",
        "CHANGELOG.md",
        ".formatter.exs"
      ],
      maintainers: ["Thiago Esteves"],
      licenses: ["MIT"],
      links: %{
        Documentation: "https://hexdocs.pm/deployex",
        Changelog: "#{@source_url}/blob/main/CHANGELOG.md",
        GitHub: @source_url
      }
    ]
  end

  defp docs do
    [
      main: "Deployex",
      source_ref: @version,
      formatters: ["html"],
      api_reference: false,
      extras: [
        "README.md",
        "LICENSE.md",
        "CHANGELOG.md"
      ]
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
      {:bcrypt_elixir, "~> 3.0"},
      {:phoenix, "~> 1.7.12"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0.3"},
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
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.0", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:mock, "~> 0.3.0", only: :test},
      {:goth, "~> 1.4"},
      {:observer_web, "~> 0.1.0"},
      {:yaml_elixir, "~> 2.0"}
    ]
  end

  defp copy_ex_doc(_) do
    static_destination_path = "./doc/guides/static"
    File.mkdir_p!(static_destination_path)
    File.cp_r("./guides/static", static_destination_path)

    examples_destination_path = "./doc/guides/examples"
    File.mkdir_p!(examples_destination_path)
    File.cp_r("./guides/examples", examples_destination_path)
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      docs: ["docs", &copy_ex_doc/1],
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
