defmodule DeployexWeb.Shell.Server do
  @moduledoc """
  One shell session. It runs the shell through `Host.Terminal`, keeps the last output for a page that
  attaches later, and broadcasts each new chunk to the pages that follow it.
  """
  use GenServer, restart: :temporary

  alias DeployexWeb.Shell
  alias DeployexWeb.Shell.Commands
  alias DeployexWeb.Shell.Session
  alias Host.Commander
  alias Host.Terminal

  @session_limit :timer.minutes(15)
  @scrollback_bytes 65_536
  @registry DeployexWeb.Shell.Registry

  ### ==========================================================================
  ### GenServer callbacks
  ### ==========================================================================
  def start_link({user, target}) do
    GenServer.start_link(__MODULE__, {user, target}, name: Shell.via(user, target))
  end

  @impl true
  def init({user, target}) do
    id = random_id()

    case Commands.build(target, id) do
      {:ok,
       %{commands: commands, options: options, kind: kind, language: language, command: command}} ->
        started_at = DateTime.utc_now(:second)

        session = %Session{
          id: id,
          user: user,
          target: target,
          kind: kind,
          language: language,
          command: command,
          started_at: started_at,
          expires_at: DateTime.add(started_at, @session_limit, :millisecond)
        }

        {:ok, terminal} =
          Terminal.new(%Terminal{
            node: Node.self(),
            commands: commands,
            options: options,
            target: self(),
            metadata: {:shell, id},
            timeout_session: @session_limit
          })

        Process.monitor(terminal)
        Registry.update_value(@registry, {user, target}, fn _ -> session end)
        Process.set_label({:shell_session, user, target})

        {:ok, %{session: session, terminal: terminal, os_pid: nil, scrollback: ""}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:session, _from, state), do: {:reply, state.session, state}
  def handle_call(:scrollback, _from, state), do: {:reply, state.scrollback, state}

  @impl true
  def handle_cast({:send_keys, keys}, %{os_pid: os_pid} = state) when is_integer(os_pid) do
    Commander.send(os_pid, keys)
    {:noreply, state}
  end

  def handle_cast({:resize, rows, cols}, %{os_pid: os_pid} = state) when is_integer(os_pid) do
    Commander.winsz(os_pid, rows, cols)
    {:noreply, state}
  end

  # Keys and sizes before the shell starts are dropped, the shell is not there to take them
  def handle_cast({:send_keys, _keys}, state), do: {:noreply, state}
  def handle_cast({:resize, _rows, _cols}, state), do: {:noreply, state}

  def handle_cast(:close, %{terminal: terminal} = state) do
    Terminal.async_terminate(terminal)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:terminal_update, %{status: :closed}}, state), do: {:stop, :normal, state}

  def handle_info({:terminal_update, %{process: os_pid, message: message}}, state) do
    state = %{state | os_pid: os_pid}

    if message in [nil, ""] do
      {:noreply, state}
    else
      Phoenix.PubSub.broadcast(
        DeployexWeb.PubSub,
        Shell.topic(state.session.id),
        {:shell_output, state.session.id, message}
      )

      {:noreply, %{state | scrollback: keep_last(state.scrollback <> message)}}
    end
  end

  def handle_info({:DOWN, _ref, :process, terminal, _reason}, %{terminal: terminal} = state),
    do: {:stop, :normal, state}

  def handle_info(_message, state), do: {:noreply, state}

  # The session leaves the registry before it says it closed, so a page that reloads the list does not see it
  @impl true
  def terminate(_reason, %{session: session}) do
    Registry.unregister(@registry, {session.user, session.target})

    Phoenix.PubSub.broadcast(
      DeployexWeb.PubSub,
      Shell.topic(session.id),
      {:shell_closed, session.id}
    )

    Commands.cleanup(session)
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================
  @spec session(pid()) :: Session.t()
  def session(pid), do: GenServer.call(pid, :session)

  @spec scrollback(pid()) :: binary()
  def scrollback(pid), do: GenServer.call(pid, :scrollback)

  @spec send_keys(pid(), String.t()) :: :ok
  def send_keys(pid, keys), do: GenServer.cast(pid, {:send_keys, keys})

  @spec resize(pid(), pos_integer(), pos_integer()) :: :ok
  def resize(pid, rows, cols), do: GenServer.cast(pid, {:resize, rows, cols})

  @spec close(pid()) :: :ok
  def close(pid), do: GenServer.cast(pid, :close)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp random_id, do: 8 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  # A cut can split a multibyte character, so the kept part starts at the next valid character
  defp keep_last(scrollback) when byte_size(scrollback) <= @scrollback_bytes, do: scrollback

  defp keep_last(scrollback) do
    scrollback
    |> binary_part(byte_size(scrollback) - @scrollback_bytes, @scrollback_bytes)
    |> drop_partial_char()
  end

  defp drop_partial_char(<<_::utf8, _::binary>> = text), do: text
  defp drop_partial_char(<<_, rest::binary>>), do: drop_partial_char(rest)
  defp drop_partial_char(<<>>), do: <<>>
end
