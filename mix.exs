defmodule Deployex.MixProject do
  use Mix.Project

  def project do
    [
      app: :deployex,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      description: description(),
      releases: [
        deployex: [
          include_executable_for: [:unix],
          steps: [:assemble, :tar]
        ]
      ],
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
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

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:briefly, "~> 0.4.1"},
      {:configparser_ex, "~> 4.0"},
      {:erlexec, "~> 2.0.6"},
      {:jason, "~> 1.2"},
      {:ex_aws, "~> 2.1"},
      {:ex_aws_s3, "~> 2.0"},
      {:hackney, "~> 1.9"},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end
end
