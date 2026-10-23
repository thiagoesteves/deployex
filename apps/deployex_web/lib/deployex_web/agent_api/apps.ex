defmodule DeployexWeb.AgentApi.Apps do
  @moduledoc """
  Builds the agent API view of this host's monitored apps.

  Each value is plain data, so it encodes as JSON. The app env and the
  pre_commands are never included.
  """

  alias Deployer.Status

  @type snapshot :: map()

  @doc """
  Lists a snapshot of every monitored app.
  """
  @spec list() :: {:ok, [snapshot()]} | {:error, :unavailable}
  def list do
    with {:ok, apps} <- monitored_apps() do
      {:ok, Enum.map(apps, &snapshot(&1, Status.ghosted_version_list(&1.name)))}
    end
  end

  @spec fetch(name :: String.t()) :: {:ok, snapshot()} | {:error, :not_found | :unavailable}
  def fetch(name) do
    with {:ok, app} <- find(name) do
      {:ok, snapshot(app, Status.ghosted_version_list(name))}
    end
  end

  @spec versions(name :: String.t()) :: {:ok, [map()]} | {:error, :not_found | :unavailable}
  def versions(name) do
    with {:ok, _app} <- find(name) do
      {:ok, name |> Status.history_version_list([]) |> Enum.map(&version/1)}
    end
  end

  @spec ghosted(name :: String.t()) :: {:ok, [map()]} | {:error, :not_found | :unavailable}
  def ghosted(name) do
    with {:ok, _app} <- find(name) do
      {:ok, name |> Status.ghosted_version_list() |> newest_first() |> Enum.map(&version/1)}
    end
  end

  @doc """
  The status server lists DeployEx from its first update on. Before it, the list is empty.
  """
  @spec ready?(monitoring :: [Status.t()]) :: boolean()
  def ready?(monitoring), do: Enum.any?(monitoring, &(&1.name == "deployex"))

  @doc """
  Returns the monitored apps in a `Deployer.Status` monitoring list, without DeployEx.
  """
  @spec monitored(monitoring :: [Status.t()]) :: [Status.t()]
  def monitored(monitoring), do: Enum.reject(monitoring, &(&1.name == "deployex"))

  @spec snapshot(app :: Status.t(), ghosted :: list()) :: snapshot()
  def snapshot(%Status{} = app, ghosted) do
    config = app.config || %{}

    %{
      name: app.name,
      language: app.language,
      replicas: app.replicas,
      mode: Map.get(config, :mode),
      manual_version: manual_version(Map.get(config, :manual_version)),
      ghosted_versions: ghosted |> newest_first() |> Enum.map(& &1.version),
      instances: Enum.map(app.children, &instance/1)
    }
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  # The name is checked against the monitored apps before any catalog read
  defp find(name) do
    with {:ok, apps} <- monitored_apps() do
      case Enum.find(apps, &(&1.name == name)) do
        nil -> {:error, :not_found}
        app -> {:ok, app}
      end
    end
  end

  defp monitored_apps do
    with {:ok, monitoring} <- Status.monitoring(),
         true <- ready?(monitoring) do
      {:ok, monitored(monitoring)}
    else
      _ -> {:error, :unavailable}
    end
  end

  defp instance(%Status{} = instance) do
    %{
      sname: instance.sname,
      node: instance.node,
      version: instance.version,
      status: instance.status,
      otp: instance.otp,
      last_deployment: instance.last_deployment,
      crash_restart_count: instance.crash_restart_count,
      force_restart_count: instance.force_restart_count,
      started_at: instance.started_at,
      ports: Enum.map(instance.ports, &%{key: &1.key, port: &1.base})
    }
  end

  defp version(version) do
    %{
      version: version.version,
      hash: version.hash,
      sname: version.sname,
      deployment: version.deployment,
      inserted_at: utc(version.inserted_at)
    }
  end

  # The catalog lists the ghosted versions in file order, a change broadcast lists the newest first
  defp newest_first(versions), do: Enum.sort_by(versions, &inserted_at/1, :desc)

  defp inserted_at(%{inserted_at: %NaiveDateTime{} = at}),
    do: NaiveDateTime.to_gregorian_seconds(at)

  defp inserted_at(_version), do: {0, 0}

  # The catalog writes inserted_at with NaiveDateTime.utc_now/0
  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp utc(_at), do: nil

  defp manual_version(%{version: version}), do: version
  defp manual_version(_manual_version), do: nil
end
