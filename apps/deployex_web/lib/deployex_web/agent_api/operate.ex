defmodule DeployexWeb.AgentApi.Operate do
  @moduledoc """
  The `operate` actions of the agent API. Each one calls the same function as its dashboard
  button, after a check that the host monitors the app.

  Each result is plain data. The caller writes the audit line with `audit/5`.
  """

  require Logger

  alias Deployer.Engine
  alias Deployer.Status
  alias DeployexWeb.AgentApi.Apps

  @type error :: {:error, :not_found | :unavailable | {:invalid, String.t()}}

  @doc """
  Restarts every instance of the app, as the dashboard restart button does. The engine
  worker restarts them after the reply.
  """
  @spec restart(name :: String.t()) :: {:ok, map()} | error()
  def restart(name) do
    with {:ok, _app} <- Apps.find(name) do
      :ok = Engine.restart_deployments(name)
      {:ok, %{name: name, restart: "accepted"}}
    end
  end

  @doc """
  Removes one version from the app's ghosted list, and returns the versions that stay.
  """
  @spec remove_ghosted(name :: String.t(), version :: String.t()) :: {:ok, [map()]} | error()
  def remove_ghosted(name, version) do
    with {:ok, _app} <- Apps.find(name),
         :ok <- ghosted(name, version),
         {:ok, _list} <- Status.remove_ghosted_version(name, version) do
      Apps.ghosted(name)
    end
  end

  @doc """
  Clears the app's ghosted list.
  """
  @spec clear_ghosted(name :: String.t()) :: {:ok, [map()]} | error()
  def clear_ghosted(name) do
    with {:ok, _app} <- Apps.find(name),
         {:ok, _list} <- Status.clear_ghosted_versions(name) do
      Apps.ghosted(name)
    end
  end

  @doc """
  Sets the app's mode: `%{"mode" => "automatic"}`, or `%{"mode" => "manual", "version" => v}`
  with a version from the app's history.
  """
  @spec set_mode(name :: String.t(), params :: map()) :: {:ok, map()} | error()
  def set_mode(name, params) do
    with {:ok, _app} <- Apps.find(name),
         {:ok, mode, version} <- mode(name, params),
         {:ok, _config} <- Status.set_mode(name, mode, version || "") do
      {:ok, %{name: name, mode: to_string(mode), manual_version: version}}
    end
  end

  @doc """
  Logs one audit line for an operate call: the token, where it came from, the action, the
  app, extra fields and the result. Strings from the request are quoted, so they cannot
  forge a line.
  """
  @spec audit(
          caller :: %{token: String.t(), from: String.t()},
          action :: String.t(),
          app :: String.t() | nil,
          fields :: Keyword.t(),
          result :: term()
        ) :: :ok
  def audit(%{token: token, from: from}, action, app, fields, result) do
    app = if app, do: [app: app], else: []
    extra = Enum.map_join(app ++ fields, "", fn {key, value} -> " #{key}=#{inspect(value)}" end)

    Logger.info(
      "Agent API operate: token=#{token} from=#{from} action=#{action}#{extra} result=#{result_name(result)}"
    )
  end

  @doc """
  The client address of a request, as text.
  """
  @spec remote_ip(Plug.Conn.t()) :: String.t()
  def remote_ip(%Plug.Conn{remote_ip: ip}), do: ip |> :inet.ntoa() |> to_string()

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp ghosted(name, version) do
    if Enum.any?(Status.ghosted_version_list(name), &(&1.version == version)),
      do: :ok,
      else: {:error, :not_found}
  end

  defp mode(_name, %{"mode" => "automatic"}), do: {:ok, :automatic, nil}

  # A manual mode stores the matching history entry, so a version that is not there would
  # leave the app pinned to nothing
  defp mode(name, %{"mode" => "manual", "version" => version}) when is_binary(version) do
    if Enum.any?(Status.history_version_list(name, []), &(&1.version == version)),
      do: {:ok, :manual, version},
      else: {:error, {:invalid, "version #{inspect(version)} is not in the history of #{name}"}}
  end

  defp mode(_name, _params),
    do: {:error, {:invalid, "mode must be automatic, or manual with a version"}}

  defp result_name({:ok, _value}), do: "ok"
  defp result_name({:error, {:invalid, _detail}}), do: "invalid"
  defp result_name({:error, reason}) when is_atom(reason), do: Atom.to_string(reason)
  defp result_name(reason) when is_atom(reason), do: Atom.to_string(reason)
end
