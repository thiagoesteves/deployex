defmodule DeployexWeb.TerminalLive do
  @moduledoc """

  References:
  https://man.openbsd.org/tmux.1
  https://forum.proxmox.com/threads/xterm-js-console-doesnt-set-terminal-size-correctly.92205/
  """
  use DeployexWeb, :live_view

  alias Foundation.Common
  alias Host.Commander
  alias Host.Terminal

  @terminal_cols 120
  @terminal_rows 35
  @shell_timeout :timer.minutes(15)

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(terminal_cols: @terminal_cols)
      |> assign(terminal_rows: @terminal_rows)

    ~H"""
    <div class="flex min-h-screen bg-gray-700">
      <div :if={@id}>
        <div
          id={"host-shell-#{@id}"}
          phx-hook="Terminal"
          data-rows={@terminal_rows}
          data-cols={@terminal_cols}
        >
          <div class="xtermjs_container" phx-update="ignore" id={"xtermjs-container-#{@id}"}></div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) when is_connected?(socket) do
    id = Common.random_number(1_000, 10_000)

    tmux_config_path = "#{:code.priv_dir(:deployex_web)}/static/.tmux.conf"
    session_name = "DeployEx-#{id}"

    cmd = """
    tmux kill-session -t #{session_name}
    stty cols #{@terminal_cols} rows #{@terminal_rows}
    tmux new-session -s #{session_name} -d
    tmux source-file #{tmux_config_path} -t #{session_name}
    tmux attach -t #{session_name}
    """

    {:ok, _pid} =
      Terminal.new(%Terminal{
        instance: id,
        commands: cmd,
        options: [:stdin, :stdout, :pty, :pty_echo],
        target: self(),
        metadata: :shell_terminal,
        timeout_session: @shell_timeout
      })

    socket =
      socket
      |> assign(:terminal_process, nil)
      |> assign(:id, id)

    {:ok, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:terminal_process, nil)
     |> assign(:id, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(%{assigns: %{terminal_process: nil}} = socket, :index, _params) do
    socket
    |> assign(:page_title, "Host Terminal")
  end

  @impl true
  def handle_info({:terminal_update, %{metadata: :shell_terminal, status: :closed}}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/applications")}
  end

  def handle_info(
        {:terminal_update, %{metadata: :shell_terminal, process: process, message: ""}},
        %{assigns: %{terminal_process: nil}} = socket
      ) do
    {:noreply, assign(socket, :terminal_process, process)}
  end

  def handle_info(
        {:terminal_update, %{metadata: :shell_terminal, process: process, message: message}},
        %{assigns: %{terminal_process: terminal_process}} = socket
      )
      when terminal_process == process do
    {:noreply,
     socket
     |> push_event("print-host-shell-#{socket.assigns.id}", %{data: message})}
  end

  @impl true
  def handle_event(
        "key",
        %{"key" => key},
        %{assigns: %{terminal_process: terminal_process}} = socket
      ) do
    Commander.send(terminal_process, key)
    {:noreply, socket}
  end
end
