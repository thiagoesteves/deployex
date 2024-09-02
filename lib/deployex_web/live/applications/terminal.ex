defmodule DeployexWeb.ApplicationsLive.Terminal do
  @moduledoc """
  This live component is handling the remote terminal for the applications.

  This connection was inspired/copied/modified from the following links:
   * https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797
   * https://github.com/frerich/underthehood
   * https://hostiledeveloper.com/2017/05/02/something-useless-terminal-in-your-browser.html
  """
  use DeployexWeb, :live_component

  alias Deployex.OpSys

  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= "Terminal for #{@monitored_app} [#{@id}]" %>
        <:subtitle>Bin: <%= @bin_path %></:subtitle>
      </.header>

      <div
        :if={@bin_path != "Binary not found"}
        phx-target={@myself}
        phx-hook="IexTerminal"
        id={"iex-#{@id}"}
      >
        <div class="xtermjs_container" phx-update="ignore" id={"xtermjs-container-#{@id}"}></div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    monitored_app = Deployex.Storage.monitored_app()

    socket =
      socket
      |> assign(:monitored_app, monitored_app)
      |> assign(:bin_path, "")

    {:ok, socket}
  end

  @impl true
  def update(%{terminal_process: nil} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> maybe_connect()}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> handle_terminal_update()

    {:ok, socket}
  end

  defp handle_terminal_update(
         %{assigns: %{id: id, terminal_message: %{message: message}}} = socket
       ) do
    # Xterm only allows "\e" as escape character
    message = String.replace(message, "^[", "\e")

    socket
    |> push_event("print-iex-#{id}", %{data: message})
  end

  @impl true
  def handle_event("key", _key, %{assigns: %{terminal_process: nil}} = socket) do
    # Ignore keys until it is connected
    {:noreply, socket}
  end

  def handle_event(
        "key",
        %{"key" => key},
        %{assigns: %{terminal_process: terminal_process}} = socket
      ) do
    OpSys.send(terminal_process, key)
    {:noreply, socket}
  end

  defp maybe_connect(%{assigns: %{id: instance, cookie: cookie}} = socket)
       when cookie != :nocookie do
    bin_path =
      instance
      |> String.to_integer()
      |> Deployex.Storage.bin_path()

    suffix = if instance == "0", do: "", else: "-#{instance}"

    if File.exists?(bin_path) do
      commands =
        """
        unset $(env | grep RELEASE | awk -F'=' '{print $1}')
        export RELEASE_NODE_SUFFIX=#{suffix}
        export RELEASE_COOKIE=#{cookie}
        #{bin_path} remote
        """

      options = [:stdin, :stdout, :pty, :pty_echo]

      case Deployex.Terminal.Supervisor.new(%Deployex.Terminal.Server{
             instance: instance,
             commands: commands,
             options: options,
             target: self(),
             type: :iex_terminal
           }) do
        {:ok, _pid} ->
          socket
          |> assign(:bin_path, bin_path)

        {:error, {:already_started, _pid}} ->
          message =
            "Maximum number of terminals achieved for instance: #{instance}"

          Logger.warning(message)

          socket
          |> assign(:bin_path, message)
      end
    else
      socket
      |> assign(:bin_path, "Binary not found")
    end
  end

  defp maybe_connect(socket), do: assign(socket, :cookie, :nocookie)
end
