defmodule DeployexWeb.AgentApi.LogController do
  use DeployexWeb, :controller

  alias DeployexWeb.AgentApi.Logs

  action_fallback DeployexWeb.AgentApi.FallbackController

  def index(conn, %{"name" => name} = params) do
    with {:ok, history} <-
           Logs.history(name, params["sname"], params["type"], params["since"], params["limit"]) do
      json(conn, history)
    end
  end
end
