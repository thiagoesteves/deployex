defmodule DeployexWeb.AgentApi.Socket do
  @moduledoc """
  The agent API socket. The client sends its bearer token as the Phoenix
  `authToken`, and each channel checks the token scope on join.
  """
  use Phoenix.Socket

  alias DeployexWeb.AgentApi.Tokens

  channel "events", DeployexWeb.AgentApi.EventsChannel
  channel "apps", DeployexWeb.AgentApi.AppsChannel

  @impl true
  def connect(_params, socket, connect_info) do
    case Tokens.authenticate(connect_info[:auth_token]) do
      {:ok, token} -> {:ok, assign(socket, :api_token, token)}
      :error -> :error
    end
  end

  @impl true
  def id(_socket), do: nil
end
