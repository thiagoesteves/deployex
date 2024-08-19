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

      <.form
        :if={@cookie == nil}
        id={"terminal-form-#{@id}"}
        for={@form}
        phx-target={@myself}
        phx-submit="connect"
      >
        <div class="flex  justify-between p-5">
          <div class="w-32">
            <div class="relative h-10 w-full min-w-[500px]">
              <.input
                placeholder="Erlang cookie"
                class="peer h-full w-full rounded-[7px] border border-blue-gray-200 border-t-transparent bg-white px-3 py-2.5 font-sans text-sm font-normal text-blue-gray-700 outline outline-0 transition-all placeholder-shown:border placeholder-shown:border-blue-gray-200 placeholder-shown:border-t-blue-gray-200 focus:border-2 focus:border-gray-900 focus:border-t-transparent focus:outline-0 disabled:border-0 disabled:bg-blue-gray-50 placeholder:opacity-0 focus:placeholder:opacity-100"
                id={"terminal-form-#{@id}-cookie"}
                name="cookie"
                type="text"
                field={@form[:cookie]}
              />
              <label class="before:content[' '] after:content[' '] pointer-events-none absolute left-0 -top-1.5 flex h-full w-full select-none !overflow-visible truncate text-[11px] font-normal leading-tight text-gray-500 transition-all before:pointer-events-none before:mt-[6.5px] before:mr-1 before:box-border before:block before:h-1.5 before:w-2.5 before:rounded-tl-md before:border-t before:border-l before:border-blue-gray-200 before:transition-all after:pointer-events-none after:mt-[6.5px] after:ml-1 after:box-border after:block after:h-1.5 after:w-2.5 after:flex-grow after:rounded-tr-md after:border-t after:border-r after:border-blue-gray-200 after:transition-all peer-placeholder-shown:text-sm peer-placeholder-shown:leading-[3.75] peer-placeholder-shown:text-blue-gray-500 peer-placeholder-shown:before:border-transparent peer-placeholder-shown:after:border-transparent peer-focus:text-[11px] peer-focus:leading-tight peer-focus:text-gray-900 peer-focus:before:border-t-2 peer-focus:before:border-l-2 peer-focus:before:!border-gray-900 peer-focus:after:border-t-2 peer-focus:after:border-r-2 peer-focus:after:!border-gray-900 peer-disabled:text-transparent peer-disabled:before:border-transparent peer-disabled:after:border-transparent peer-disabled:peer-placeholder-shown:text-blue-gray-500">
                Erlang cookie
              </label>
            </div>
          </div>
          <.button class="w-32 h-10" type="submit">
            Connect <span aria-hidden="true">→</span>
          </.button>
        </div>
      </.form>

      <div
        :if={@cookie != nil and @bin_path != "Binary not found"}
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
    monitored_app = Deployex.AppConfig.monitored_app()

    socket =
      socket
      |> assign(:monitored_app, monitored_app)
      |> assign(:cookie, nil)
      |> assign(:bin_path, "")
      |> assign(:form, to_form(%{"cookie" => nil}))

    {:ok, socket}
  end

  @impl true
  def update(%{terminal_process: nil} = assigns, socket) do
    {:ok, assign(socket, assigns)}
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

  def handle_event("connect", %{"cookie" => cookie}, socket) do
    {:noreply,
     socket
     |> assign(:cookie, cookie)
     |> maybe_connect()}
  end

  defp maybe_connect(%{assigns: %{id: instance, cookie: cookie, terminal_message: nil}} = socket)
       when cookie not in ["", nil] do
    bin_path =
      instance
      |> String.to_integer()
      |> Deployex.AppConfig.bin_path()

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
            "Maximum number of terminals achieved for instance: #{instance} type: :iex_terminal"

          Logger.warning(message)

          socket
          |> assign(:cookie, nil)
      end
    else
      socket
      |> assign(:bin_path, "Binary not found")
    end
  end

  defp maybe_connect(socket), do: assign(socket, :cookie, nil)
end
