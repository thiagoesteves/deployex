defmodule Deployex.MixProject do
  use Mix.Project

  @source_url "https://github.com/thiagoesteves/deployex"
  @version "0.5.0"

  def project do
    [
      name: "Deployex",
      apps_path: "apps",
      version: @version,
      source_url: @source_url,
      homepage_url: @source_url,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      description: description(),
      releases: [
        deployex: [
          include_executable_for: [:unix],
          steps: [:assemble, :tar],
          applications: [
            foundation: :permanent,
            host: :permanent,
            deployer: :permanent,
            sentinel: :permanent,
            deployex_web: :permanent
          ],
          config_providers: [
            {Foundation.ConfigProvider.Env.Config, nil},
            {Foundation.ConfigProvider.Secrets.Manager, nil}
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

  defp description do
    """
    Deployex is a tool designed for managing deployments for Elixir applications
    """
  end

  defp package do
    [
      files: [
        "apps",
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
      main: "Deployer",
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

  defp copy_ex_doc(_) do
    static_destination_path = "./doc/guides/static"
    File.mkdir_p!(static_destination_path)
    File.cp_r("./guides/static", static_destination_path)

    examples_destination_path = "./doc/guides/examples"
    File.mkdir_p!(examples_destination_path)
    File.cp_r("./guides/examples", examples_destination_path)
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mock, "~> 0.3.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      docs: ["docs", &copy_ex_doc/1]
    ]
  end
end
