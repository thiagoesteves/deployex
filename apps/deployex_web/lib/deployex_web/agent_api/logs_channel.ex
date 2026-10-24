defmodule DeployexWeb.AgentApi.LogsChannel do
  @moduledoc """
  Pushes `logs` with the new lines of one instance and log type, on the topic
  `logs:<sname>:<type>`. Each push has the body of `GET /v1/apps/:name/logs`.
  """
  use DeployexWeb, :channel

  alias DeployexWeb.AgentApi.Logs
  alias DeployexWeb.AgentApi.Tokens

  @impl true
  def join("logs:" <> source, _payload, socket) do
    with :ok <- read(socket),
         [sname, type] <- String.split(source, ":"),
         :ok <- Logs.subscribe(sname, type) do
      {:ok, socket}
    else
      {:error, reason} when reason in [:forbidden, :unavailable] ->
        {:error, %{reason: Atom.to_string(reason)}}

      _not_found ->
        {:error, %{reason: "not_found"}}
    end
  end

  @impl true
  def handle_info({:logs_new_data, _sname, _type, message}, socket) do
    case Logs.entries(message) do
      [] -> :ok
      logs -> push(socket, "logs", %{logs: logs})
    end

    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp read(socket) do
    if Tokens.allows?(socket.assigns.api_token, "read"), do: :ok, else: {:error, :forbidden}
  end
end
