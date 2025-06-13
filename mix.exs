# NOTE: Load shared configuration
Code.require_file("mix/shared.exs")

defmodule Deployex.MixProject do
  use Mix.Project

  @source_url "https://github.com/thiagoesteves/deployex"

  def project do
    [
      name: "Deployex",
      apps_path: "apps",
      version: Mix.Shared.version(),
      source_url: @source_url,
      homepage_url: @source_url,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      test_coverage: Mix.Shared.test_coverage(),
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
      aliases: aliases(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  defp description do
    """
    Deployex is a tool designed for managing deployments for Beam applications (Elixir, Erlang and Gleam)
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
      main: "readme",
      source_ref: Mix.Shared.version(),
      formatters: ["html"],
      api_reference: false,
      extra_section: ["GUIDES"],
      groups_for_extras: groups_for_extras(),
      extras: [
        "README.md",
        "LICENSE.md": [filename: "license", title: "License"],
        "CHANGELOG.md": [filename: "changelog", title: "Changelog"],
        "guides/examples/aws-elixir/README.md": [filename: "README.md", title: "AWS-Elixir"],
        "guides/examples/aws-erlang/README.md": [filename: "README.md", title: "AWS-Erlang"],
        "guides/examples/aws-gleam/README.md": [filename: "README.md", title: "AWS-Gleam"],
        "guides/examples/gcp-elixir/README.md": [filename: "README.md", title: "GCP-Elixir"],
        "guides/examples/local-elixir/README.md": [filename: "README.md", title: "Local-Elixir"],
        "guides/examples/local-elixir/README.md": [
          filename: "README.md",
          title: "Local-Elixir-Ecto"
        ],
        "guides/examples/local-elixir-umbrella/README.md": [
          filename: "README.md",
          title: "Local-Elixir-Umbrella"
        ],
        "guides/examples/local-erlang/README.md": [filename: "README.md", title: "Local-Erlang"],
        "guides/examples/local-gleam/README.md": [filename: "README.md", title: "Local-Gleam"]
      ]
    ]
  end

  defp groups_for_extras do
    [
      "Installation and Deploy": Path.wildcard("guides/examples/*/*.md")
    ]
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

  defp cleanup_doc_config_js(_) do
    files = Path.wildcard("./doc/*html")

    Enum.each(files, fn file ->
      System.cmd("sed", ["-i", ".backup", "/docs_config.js/d", file])
      File.rm("#{file}.backup")
    end)
  end

  defp copy_ex_doc_images(_) do
    static_destination_path = "./doc/guides/static"
    File.mkdir_p!(static_destination_path)
    File.cp_r("./guides/static", static_destination_path)
  end

  defp publish_docs(_) do
    docs_folder = "apps/deployex_web/priv/static/docs"
    File.cp_r("./doc", docs_folder)
    System.cmd("tar", ["czf", "#{docs_folder}/docs.tar.gz", "-C", "./doc", "."])
  end

  defp digest_docs(_) do
    docs_folder = "apps/deployex_web/priv/static/docs"
    System.cmd("tar", ["xf", "#{docs_folder}/docs.tar.gz", "-C", docs_folder])
    File.rm("#{docs_folder}/docs.tar.gz")
  end

  defp aliases do
    [
      docs: ["docs", &cleanup_doc_config_js/1, &copy_ex_doc_images/1, &publish_docs/1],
      release: [&digest_docs/1, "release"]
    ]
  end
end
