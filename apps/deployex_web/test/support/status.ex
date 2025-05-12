defmodule DeployexWeb.Fixture.Status do
  @moduledoc """
  This module will handle the status functions for testing purpose
  """

  alias Deployer.Status
  alias DeployexWeb.Fixture.Nodes, as: FixtureNodes

  def version(attrs \\ %{}) do
    %Status.Version{
      version: "1.0.0",
      hash: "local",
      pre_commands: [],
      node: FixtureNodes.test_node("testapp", "abc123"),
      deployment: :full_deployment,
      inserted_at: NaiveDateTime.utc_now()
    }
    |> Map.merge(attrs)
  end

  def versions(elements \\ 3, attrs \\ %{}) do
    Enum.map(1..elements, fn index -> version(%{version: "1.0.#{index}"}) end)
    |> Enum.map(&Map.merge(&1, attrs))
  end

  def deployex(attrs \\ %{}) do
    deployex = %Status{
      name: "deployex",
      sname: "deployex",
      node: "deployex@nohost",
      version: "1.2.3",
      otp: :connected,
      tls: :supported,
      supervisor: true,
      status: :running,
      uptime: "short time",
      last_ghosted_version: "-/-"
    }

    Map.merge(deployex, attrs)
  end

  def application(attrs \\ %{}) do
    default_name = "test_app"
    default_suffix = "abc123"

    application = %Status{
      name: "default_name",
      sname: "#{default_name}-#{default_suffix}",
      node: FixtureNodes.test_node(default_name, default_suffix),
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
