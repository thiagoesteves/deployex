defmodule DeployexWeb.AgentApi.AppController do
  use DeployexWeb, :controller

  alias DeployexWeb.AgentApi.Apps

  action_fallback DeployexWeb.AgentApi.FallbackController

  def index(conn, _params) do
    with {:ok, apps} <- Apps.list(), do: json(conn, %{apps: apps})
  end

  def show(conn, %{"name" => name}) do
    with {:ok, app} <- Apps.fetch(name), do: json(conn, app)
  end

  def versions(conn, %{"name" => name}) do
    with {:ok, versions} <- Apps.versions(name), do: json(conn, %{versions: versions})
  end

  def ghosted(conn, %{"name" => name}) do
    with {:ok, ghosted} <- Apps.ghosted(name), do: json(conn, %{ghosted_versions: ghosted})
  end
end
