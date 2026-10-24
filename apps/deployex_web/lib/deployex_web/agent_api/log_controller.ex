defmodule DeployexWeb.AgentApi.LogController do
  use DeployexWeb, :controller

  alias DeployexWeb.AgentApi.Logs

  action_fallback DeployexWeb.AgentApi.FallbackController

  def index(conn, %{"name" => name} = params) do
    with {:ok, logs} <- Logs.history(name, params["sname"], params["type"], params["since"]) do
      json(conn, %{logs: logs})
    end
  end
end
