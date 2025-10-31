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

  def metadata_by_app(current \\ %{metadata: %{}}, app_name \\ "test_app", attrs \\ %{}) do
    curr = Map.get(current, :metadata, %{})

    default = %{
      last_ghosted_version: nil,
      mode: :automatic,
      manual_version: nil,
      versions: []
    }

    metadata = Map.put(curr, app_name, Map.merge(default, attrs))

    Map.put(current, :metadata, metadata)
  end

  def deployex do
    metadata_by_app() |> deployex()
  end

  def deployex(attrs) do
    deployex = %Status{
      name: "deployex",
      sname: "deployex",
      version: "1.2.3",
      otp: :connected,
      tls: :supported,
      supervisor: true,
      status: :running,
      uptime: "short time"
    }

    Map.merge(deployex, attrs)
  end

  def application(attrs \\ %{}) do
    default_name = "test_app"
    default_suffix = "abc123"

    application = %Status{
      name: "#{default_name}",
      sname: "#{default_name}-#{default_suffix}",
      version: "4.5.6",
      otp: :connected,
      tls: :supported,
      last_deployment: :full_deployment,
      supervisor: false,
      status: :running,
      crash_restart_count: 0,
      uptime: "long time"
    }

    Map.merge(application, attrs)
  end

  def list do
    [deployex(), application()]
  end
end
