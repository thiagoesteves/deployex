defmodule DeployexWeb.AgentApiCase do
  @moduledoc """
  Test case for the agent API endpoint, its HTTP routes and its socket.

  The tokens live in the application env, so these tests are not async.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint DeployexWeb.AgentApi.Endpoint

      import Plug.Conn
      import Phoenix.ConnTest, except: [connect: 2, connect: 3]
      import Phoenix.ChannelTest
      import DeployexWeb.AgentApiCase
    end
  end

  setup do
    on_exit(fn -> Application.delete_env(:deployex_web, DeployexWeb.AgentApi) end)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Sets `DEPLOYEX_API_TOKENS` to the given entries.
  """
  def put_api_tokens(tokens) do
    Application.put_env(:deployex_web, DeployexWeb.AgentApi, tokens: tokens)
  end

  @doc """
  Returns the `name:scopes:sha256` entry for a token.
  """
  def token_entry(name, scopes, token) do
    "#{name}:#{scopes}:" <> Base.encode16(:crypto.hash(:sha256, token), case: :lower)
  end

  def bearer(conn, token), do: Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> token)
end
