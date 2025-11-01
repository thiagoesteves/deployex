defmodule DeployexWeb.Fixture.Status do
  @moduledoc """
  This module will handle the status functions for testing purpose
  """

  alias Deployer.Status
  alias Foundation.Catalog.Version

  def version(attrs \\ %{}) do
    name = "testapp"
    sname = "#{name}-abc123"

    %Version{
      version: "1.0.0",
      hash: "local",
      pre_commands: [],
      name: name,
      sname: sname,
      deployment: :full_deployment,
      inserted_at: NaiveDateTime.utc_now()
    }
    |> Map.merge(attrs)
  end

  def versions(elements \\ 3, attrs \\ %{}) do
    Enum.map(1..elements, fn index -> version(%{version: "1.0.#{index}"}) end)
    |> Enum.map(&Map.merge(&1, attrs))
  end

  def config_by_app(current \\ %{config: %{}}, app_name \\ "test_app", attrs \\ %{}) do
    curr = Map.get(current, :config, %{})

    default = %{
      last_ghosted_version: nil,
      mode: :automatic,
      manual_version: nil,
      versions: []
    }

    config = Map.put(curr, app_name, Map.merge(default, attrs))

    Map.put(current, :config, config)
  end

  def deployex do
    config_by_app() |> deployex()
  end

  def deployex(attrs) do
    deployex = %Status{
      name: "deployex",
      sname: "deployex",
      version: "1.2.3",
      otp: :connected,
      tls: :supported,
      status: :running,
      uptime: "short time"
    }

    Map.merge(deployex, attrs)
  end

  defp default_config do
    %{
      last_ghosted_version: nil,
      mode: :automatic,
      manual_version: nil,
      versions: []
    }
  end

  def application(attrs \\ %{}, config \\ default_config()) do
    default_suffix = "abc123"
    name = Map.get(attrs, :name, "test_app")
    language = Map.get(attrs, :language, "elixir")
    children = Map.get(attrs, :children, [])

    application = %Status{
      name: "#{name}",
      sname: "#{name}-#{default_suffix}",
      version: "4.5.6",
      otp: :connected,
      tls: :supported,
      last_deployment: :full_deployment,
      status: :running,
      crash_restart_count: 0,
      uptime: "long time"
    }

    %Status{
      name: name,
      language: language,
      status: :running,
      config: config,
      children: children ++ [Map.merge(application, attrs)]
    }
  end

  def list do
    [deployex(), application()]
  end
end
