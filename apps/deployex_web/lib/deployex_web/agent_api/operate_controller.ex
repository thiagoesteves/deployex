defmodule DeployexWeb.AgentApi.OperateController do
  use DeployexWeb, :controller

  alias DeployexWeb.AgentApi.Operate

  action_fallback DeployexWeb.AgentApi.FallbackController

  def restart(conn, %{"name" => name}) do
    with {:ok, body} <- audited(conn, "restart", name, [], Operate.restart(name)) do
      conn |> put_status(202) |> json(body)
    end
  end

  def remove_ghosted(conn, %{"name" => name, "version" => version}) do
    result = Operate.remove_ghosted(name, version)

    with {:ok, ghosted} <- audited(conn, "remove_ghosted", name, [version: version], result) do
      json(conn, %{ghosted_versions: ghosted})
    end
  end

  def clear_ghosted(conn, %{"name" => name}) do
    with {:ok, ghosted} <- audited(conn, "clear_ghosted", name, [], Operate.clear_ghosted(name)) do
      json(conn, %{ghosted_versions: ghosted})
    end
  end

  def set_mode(conn, %{"name" => name} = params) do
    fields = for key <- [:mode, :version], value = params[to_string(key)], do: {key, value}

    with {:ok, body} <- audited(conn, "set_mode", name, fields, Operate.set_mode(name, params)) do
      json(conn, body)
    end
  end

  defp audited(conn, action, name, fields, result) do
    caller = %{token: conn.assigns.api_token_name, from: Operate.remote_ip(conn)}
    Operate.audit(caller, action, name, fields, result)
    result
  end
end
