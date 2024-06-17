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
        <%= "Terminal for #{@monitored_app} [#{@id}]" %>
        <:subtitle>Bin: <%= @bin_path %></:subtitle>
      </.header>

      <form :if={@cookie == nil} id="auth-form" method="post" phx-target={@myself} phx-submit="connect">
        <div class="flex  justify-between p-5">
          <div class="w-32">
            <div class="relative h-10 w-full min-w-[500px]">
              <input
                placeholder="Erlang cookie"
                class="peer h-full w-full rounded-[7px] border border-blue-gray-200 border-t-transparent bg-white px-3 py-2.5 font-sans text-sm font-normal text-blue-gray-700 outline outline-0 transition-all placeholder-shown:border placeholder-shown:border-blue-gray-200 placeholder-shown:border-t-blue-gray-200 focus:border-2 focus:border-gray-900 focus:border-t-transparent focus:outline-0 disabled:border-0 disabled:bg-blue-gray-50 placeholder:opacity-0 focus:placeholder:opacity-100"
                id="auth-form_cookie"
                name="cookie"
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
      </form>

      <div :if={@cookie != nil and @bin_path != "Binary not found"} phx-hook="IexTerminal" id={@id}>
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
      |> assign(:connected?, false)
      |> assign(:bin_path, "")

    {:ok, socket}
  end

  @impl true
  def update(assigns, %{assigns: %{connected?: true}} = socket) do
    socket =
      socket
      |> assign(assigns)
      |> handle_terminal_update()

    {:ok, socket}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  defp handle_terminal_update(
         %{
           assigns: %{
             id: id,
             terminal_process: process,
             process_stdout_log: {_type, os_process, message}
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

  def handle_event("connect", %{"cookie" => cookie}, socket) do
    {:noreply,
     socket
     |> assign(:cookie, cookie)
     |> try_to_connect()}
  end

  defp try_to_connect(%{assigns: %{id: "0", process_stdout_log: nil}} = socket) do
    path = Application.get_env(:deployex, :bin_path)

    socket
    |> remote_if_exists(path, "")
  end

  defp try_to_connect(
         %{assigns: %{id: id, process_stdout_log: nil, monitored_app: monitored_app}} = socket
       ) do
    path = "#{Deployex.AppConfig.current_path(id)}/bin/#{monitored_app}"

    socket
    |> remote_if_exists(path, "-#{id}")
  end

  defp remote_if_exists(%{assigns: %{cookie: cookie}} = socket, path, suffix) when cookie not in ["", nil] do
    if File.exists?(path) do
      {:ok, _pid, process} =
        :exec.run_link("#{path} remote", [
          :stdin,
          :stdout,
          :pty,
          :pty_echo,
          {:env, [{"RELEASE_NODE_SUFFIX", "#{suffix}"}, {"RELEASE_COOKIE", "#{cookie}"}]}
        ])

      socket
      |> assign(:terminal_process, process)
      |> assign(:bin_path, path)
      |> assign(:connected?, true)
    else
      socket
      |> assign(:bin_path, "Binary not found")
      |> assign(:connected?, false)
    end
  end

  defp remote_if_exists( socket, _path, _suffix), do: assign(socket, :cookie, nil)
end
