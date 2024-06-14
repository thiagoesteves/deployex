defmodule DeployexWeb.ApplicationsLive.Terminal do
  @moduledoc """
  This live component is handling the remote terminal for the applications.

  This connection was inspired/copied/modified from the following links:
   * https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797
   * https://github.com/frerich/underthehood
   * https://hostiledeveloper.com/2017/05/02/something-useless-terminal-in-your-browser.html
  """
  use DeployexWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= "#{@title} [#{@id}]" %>
        <:subtitle>Bin: <%= @log_path %></:subtitle>
      </.header>
      <div :if={@log_path != "Binary not found"} phx-hook="IexTerminal" id={@id}>
        <div class="xtermjs_container" phx-update="ignore" id={"xtermjs-container-#{@id}"}></div>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> handle_terminal_update()

    {:ok, socket}
  end

  defp handle_terminal_update(%{assigns: %{id: "0", current_log: nil}} = socket) do
    path = Application.get_env(:deployex, :bin_path)

    socket
    |> remote_if_exists(path, "")
  end

  defp handle_terminal_update(%{assigns: %{id: id, current_log: nil}} = socket) do
    path = "#{Deployex.AppConfig.current_path(id)}/bin/#{Deployex.AppConfig.monitored_app()}"

    socket
    |> remote_if_exists(path, "-#{id}")
  end

  defp handle_terminal_update(
         %{
           assigns: %{
             id: id,
             terminal_process: process,
             current_log: {_type, os_process, message}
           }
         } = socket
       )
       when os_process == process do
    # message = String.replace(message, "\e[A", "\e[D")

    IO.puts("Send to terminal: #{inspect(message)}")

    socket
    |> push_event("print_#{id}", %{data: message})
  end

  @impl true
  def handle_event(
        "key",
        %{"key" => key},
        %{assigns: %{terminal_process: terminal_process}} = socket
      ) do
    IO.puts("Pressed Key: #{inspect(key)}")
    :exec.send(terminal_process, key)
    {:noreply, socket}
  end

  defp remote_if_exists(socket, path, suffix) do
    if File.exists?(path) do
      command =
        """
        export RELEASE_NODE_SUFFIX=#{suffix}
        export RELEASE_COOKIE=#{:cookie}
        #{path} remote
        """

      {:ok, _pid, process} = :exec.run_link("#{command}", [:stdin, :stdout, :pty, :pty_echo])

      socket
      |> assign(:terminal_process, process)
      |> assign(:log_path, path)
    else
      socket
      |> assign(:log_path, "Binary not found")
    end
  end
end
