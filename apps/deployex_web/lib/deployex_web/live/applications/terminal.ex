defmodule DeployexWeb.ApplicationsLive.Terminal do
  @moduledoc """
  This live component is handling the remote terminal for the applications.

  This connection was inspired/copied/modified from the following links:
   * https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797
   * https://github.com/frerich/underthehood
   * https://hostiledeveloper.com/2017/05/02/something-useless-terminal-in-your-browser.html
  """
  use DeployexWeb, :live_component

  alias Foundation.Catalog
  alias Foundation.Common
  alias Host.Commander
  alias Host.Terminal

  require Logger

  @impl true
  @spec render(any()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {"Terminal for #{@id}"}
        <:subtitle>Bin: {@bin_path}</:subtitle>
      </.header>

      <div
        :if={@bin_path != "Binary not found"}
        phx-target={@myself}
        phx-hook="Terminal"
        id={"iex-#{@id}"}
      >
        <div class="xtermjs_container" phx-update="ignore" id={"xtermjs-container-#{@id}"}></div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    socket =
      socket
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
    Commander.send(terminal_process, key)
    {:noreply, socket}
  end

  defp maybe_connect(
         %{
           assigns: %{
             id: sname,
             cookie: cookie
           }
         } =
           socket
       )
       when cookie != :nocookie do
    %{node: node, hostname: hostname, language: app_lang} =
      Catalog.node_info(sname)

    bin_path = Catalog.bin_path(sname, :current)
    path = Common.remove_deployex_from_path()

    ssl_options =
      if Common.check_mtls() == :supported do
        "-proto_dist inet_tls -ssl_dist_optfile /tmp/inet_tls.conf"
      else
        ""
      end

    if File.exists?(bin_path) do
      commands =
        cond do
          app_lang == "gleam" and sname != "deployex" ->
            """
            unset $(env | grep '^RELEASE_' | awk -F'=' '{print $1}')
            unset BINDIR ELIXIR_ERL_OPTIONS ROOTDIR
            export PATH=#{path}
            erl -remsh #{sname}@#{hostname} -setcookie #{cookie} #{ssl_options}
            """

          app_lang == "erlang" and sname != "deployex" ->
            """
            unset $(env | grep '^RELEASE_' | awk -F'=' '{print $1}')
            unset BINDIR ELIXIR_ERL_OPTIONS ROOTDIR
            export PATH=#{path}
            export RELX_REPLACE_OS_VARS=true
            export RELEASE_NODE=#{sname}
            export RELEASE_COOKIE=#{cookie}
            export RELEASE_SSL_OPTIONS=\"#{ssl_options}\"
            #{bin_path} remote_console
            """

          sname == "deployex" ->
            """
            unset $(env | grep '^RELEASE_' | awk -F'=' '{print $1}')
            unset BINDIR ELIXIR_ERL_OPTIONS ROOTDIR
            export PATH=#{path}
            export RELEASE_COOKIE=#{cookie}
            #{bin_path} remote
            """

          true ->
            """
            unset $(env | grep '^RELEASE_' | awk -F'=' '{print $1}')
            unset BINDIR ELIXIR_ERL_OPTIONS ROOTDIR
            export PATH=#{path}
            export RELEASE_NODE=#{sname}
            export RELEASE_COOKIE=#{cookie}
            #{bin_path} remote
            """
        end

      options = [:stdin, :stdout, :pty, :pty_echo]

      {:ok, _pid} =
        Terminal.new(%Terminal{
          node: node,
          commands: commands,
          options: options,
          target: self(),
          metadata: :iex_terminal
        })

      socket
      |> assign(:bin_path, bin_path)
    else
      socket
      |> assign(:bin_path, "Binary not found")
    end
  end

  defp maybe_connect(socket) do
    socket
    |> assign(:cookie, :nocookie)
    |> assign(:bin_path, "Cookie not set")
  end
end
