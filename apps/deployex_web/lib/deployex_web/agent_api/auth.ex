defmodule DeployexWeb.AgentApi.Auth do
  @moduledoc """
  Plug that lets a request through only with a bearer token that has the given scope.

      plug DeployexWeb.AgentApi.Auth, scope: "read"

  No token or an unknown token gets 401, a token without the scope gets 403.
  """

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias DeployexWeb.AgentApi.Operate
  alias DeployexWeb.AgentApi.Tokens

  @impl Plug
  def init(opts), do: Keyword.fetch!(opts, :scope)

  @impl Plug
  def call(conn, scope) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, entry} <- Tokens.authenticate(token) do
      if Tokens.allows?(entry, scope) do
        assign(conn, :api_token_name, entry.name)
      else
        if scope == "operate", do: audit_forbidden(conn, entry.name)
        halt_with(conn, 403, "Forbidden")
      end
    else
      _ ->
        conn
        |> put_resp_header("www-authenticate", "Bearer")
        |> halt_with(401, "Unauthorized")
    end
  end

  # An operate call that a token may not make is part of the audit trail too
  defp audit_forbidden(conn, token_name) do
    Operate.audit(
      %{token: token_name, from: Operate.remote_ip(conn)},
      inspect("#{conn.method} #{conn.request_path}"),
      nil,
      [],
      :forbidden
    )
  end

  defp bearer_token(conn) do
    with [header | _] <- get_req_header(conn, "authorization"),
         [scheme, token] <- String.split(header, " ", parts: 2),
         "bearer" <- String.downcase(scheme) do
      {:ok, String.trim(token)}
    else
      _ -> :error
    end
  end

  defp halt_with(conn, status, detail) do
    conn
    |> put_status(status)
    |> json(%{errors: %{detail: detail}})
    |> halt()
  end
end
