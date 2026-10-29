# NOTE: Load shared configuration
Code.require_file("mix/shared.exs")

defmodule Deployex.MixProject do
  use Mix.Project

  @source_url "https://github.com/deployex/deployex"

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
          steps: [:assemble, &Jellyfish.generate/1, :tar],
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
        "guides/docs/aws-elixir/README.md": [
          filename: "guide-aws-elixir",
          title: "AWS-Elixir"
        ],
        "guides/docs/aws-elixir-db-certificate/README.md": [
          filename: "guide-aws-elixir-db-certificate",
          title: "AWS-Elixir-DB-CertManager"
        ],
        "guides/docs/aws-erlang/README.md": [
          filename: "guide-aws-erlang",
          title: "AWS-Erlang"
        ],
        "guides/docs/aws-gleam/README.md": [
          filename: "guide-aws-gleam",
          title: "AWS-Gleam"
        ],
        "guides/docs/aws-air-gapped/README.md": [
          filename: "guide-aws-air-gapped",
          title: "AWS-Air-Gapped"
        ],
        "guides/docs/gcp-elixir/README.md": [
          filename: "guide-gcp-elixir",
          title: "GCP-Elixir"
        ],
        "guides/docs/local-elixir/README.md": [
          filename: "guide-local-elixir",
          title: "Local-Elixir"
        ],
        "guides/docs/local-elixir-ecto/README.md": [
          filename: "guide-local-elixir-ecto",
          title: "Local-Elixir-Ecto"
        ],
        "guides/docs/local-elixir-umbrella/README.md": [
          filename: "guide-local-elixir-umbrella",
          title: "Local-Elixir-Umbrella"
        ],
        "guides/docs/local-erlang/README.md": [
          filename: "guide-local-erlang",
          title: "Local-Erlang"
        ],
        "guides/docs/local-gleam/README.md": [
          filename: "guide-local-gleam",
          title: "Local-Gleam"
        ],
        "guides/docs/yaml/README.md": [
          filename: "guide-yaml",
          title: "YAML"
        ],
        "guides/docs/agent-api/README.md": [
          filename: "guide-agent-api",
          title: "Agent API"
        ],
        "guides/docs/hot-upgrades/README.md": [
          filename: "guide-hot-upgrades",
          title: "Hot Upgrades"
        ]
      ]
    ]
  end

  defp groups_for_extras do
    [
      "Installation and Deploy": Path.wildcard("guides/docs/*/*.md")
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
      {:meck, "~> 1.2", only: :test, override: true},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:jellyfish, "~> 0.2.0"}
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
