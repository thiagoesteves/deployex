defmodule DeployexWeb.AgentApi.AppsChannel do
  @moduledoc """
  Replies to the join with a snapshot of every monitored app, then pushes an `app`
  message with the new snapshot of one app each time it changes, and `app_removed`
  with the name of an app that the host no longer monitors.
  """
  use DeployexWeb, :channel

  alias Deployer.Status
  alias DeployexWeb.AgentApi.Apps
  alias DeployexWeb.AgentApi.Tokens

  @impl true
  def join("apps", _payload, socket) do
    if Tokens.allows?(socket.assigns.api_token, "read") do
      :ok = Status.subscribe()
      join_with(Status.monitoring(), socket)
    else
      {:error, %{reason: "forbidden"}}
    end
  end

  # Connected DeployEx nodes share the topic, only this node's apps are reported
  @impl true
  def handle_info({:monitoring_app_updated, source_node, monitoring}, socket)
      when source_node == node() do
    {:noreply, socket |> track(Apps.monitored(monitoring)) |> push_changes()}
  end

  def handle_info({:ghosted_versions_updated, source_node, name, ghosted}, socket)
      when source_node == node() do
    socket = assign(socket, :ghosted, Map.put(socket.assigns.ghosted, name, ghosted))
    {:noreply, push_changes(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  # Before the first status update the list is empty, so the client joins again later
  defp join_with({:ok, monitoring}, socket) do
    if Apps.ready?(monitoring) do
      socket = socket |> assign(apps: [], ghosted: %{}) |> track(Apps.monitored(monitoring))
      snapshots = snapshot_list(socket)

      {:ok, %{apps: snapshots}, assign(socket, :snapshots, Map.new(snapshots, &{&1.name, &1}))}
    else
      {:error, %{reason: "unavailable"}}
    end
  end

  defp join_with(_error, _socket), do: {:error, %{reason: "unavailable"}}

  # A new app gets its ghosted list once, then follows the list changes
  defp track(socket, apps) do
    ghosted =
      Enum.reduce(apps, socket.assigns.ghosted, fn %{name: name}, acc ->
        if Map.has_key?(acc, name) do
          acc
        else
          :ok = Status.subscribe_ghosted_versions(name)
          Map.put(acc, name, Status.ghosted_version_list(name))
        end
      end)

    assign(socket, apps: apps, ghosted: ghosted)
  end

  defp push_changes(socket) do
    current = socket.assigns.snapshots
    snapshots = snapshot_list(socket)

    Enum.each(snapshots, fn snapshot ->
      if current[snapshot.name] != snapshot, do: push(socket, "app", snapshot)
    end)

    snapshots = Map.new(snapshots, &{&1.name, &1})

    current
    |> Map.keys()
    |> Enum.reject(&Map.has_key?(snapshots, &1))
    |> Enum.each(&push(socket, "app_removed", %{name: &1}))

    assign(socket, :snapshots, snapshots)
  end

  defp snapshot_list(socket) do
    Enum.map(
      socket.assigns.apps,
      &Apps.snapshot(&1, Map.get(socket.assigns.ghosted, &1.name, []))
    )
  end
end
