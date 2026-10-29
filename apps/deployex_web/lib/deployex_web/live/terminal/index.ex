defmodule DeployexWeb.TerminalLive do
  @moduledoc """
  The Terminal page: a tab for each of the user's shell sessions, the host shell and the IEx or Erlang
  shell of an instance. The sessions belong to `DeployexWeb.Shell`, so they stay open when the user goes
  to another page, and the dock shows the same ones.
  """
  use DeployexWeb, :live_view

  alias Deployer.Monitor
  alias DeployexWeb.Shell
  alias DeployexWeb.UI.Icons
  alias DeployexWeb.UI.Menu
  alias DeployexWeb.UI.Tags
  alias Foundation.Catalog

  @shortcuts %{
    iex: [
      {"#iex:break", "back to prompt"},
      {"ESCAPE + o", "multi-line command with an editor"},
      {"c filename.exs", "compile"},
      {"r Module", "reload"},
      {"h Module.method", "help"},
      {"i var", "display type information"},
      {"recompile", "recompile and load"},
      {"CTRL+G", "user switch command"},
      {"v[n]", "session history"},
      {"exports Map", "list public functions of a module"},
      {"clear", "clear the screen"},
      {"break!(MyModule.my_func/1)", "set a breakpoint"}
    ],
    erlang_shell: [
      {"CTRL+G", "user switch command"},
      {"c(filename.erl).", "compile"},
      {"h(Module).", "help"},
      {"b().", "print the current variable bindings"},
      {"f().", "clear all variable bindings"},
      {"f(X).", "remove the binding of X"},
      {"rl().", "print all record definitions"},
      {"q().", "quit the Erlang shell"},
      {"e(N).", "evaluate expression N again"},
      {"v(N).", "value of expression N"}
    ],
    host_shell: [
      {"Ctrl+B d", "detach, the session keeps running"},
      {"Ctrl+B c", "new window"},
      {"Ctrl+B n", "next window"},
      {"Ctrl+B %", "split side by side"},
      {"Ctrl+B [", "scroll mode, q to leave"},
      {"clear", "clear the screen"}
    ]
  }

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :active_session,
        Enum.find(assigns.sessions, &(&1.target == assigns.active))
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      current_path={@current_path}
      current_user={@current_user}
      host_info={@host_info}
      recent_events={@recent_events}
      socket={@socket}
    >
      <div class="mx-auto flex max-w-[1240px] flex-col gap-4 px-7 pt-6 pb-12 max-md:px-4">
        <header class="flex flex-wrap items-center justify-between gap-x-6 gap-y-3">
          <div class="min-w-0">
            <h1 class="text-[1.625rem] font-bold tracking-[-0.02em]">Terminal</h1>
            <p class="dx-muted dx-mono mt-1 text-[0.8125rem]">
              {if @active_session, do: @active_session.command, else: "No open session"}
            </p>
          </div>
          <div :if={@active_session} class="flex items-center gap-3">
            <span class="dx-muted text-[0.8125rem]">
              Session closes in
              <b
                id={"countdown-#{@active_session.id}"}
                class="dx-mono text-(--dx-base-content)"
                phx-hook="Countdown"
                data-expires={DateTime.to_iso8601(@active_session.expires_at)}
              ></b>
            </span>
            <button
              id="terminal-disconnect"
              type="button"
              class="dx-btn dx-btn-er"
              phx-click="close"
              phx-value-target={@active_session.target}
            >
              Disconnect
            </button>
          </div>
        </header>

        <section class="dx-card overflow-visible" aria-label="Terminal sessions">
          <div class="dx-tabs">
            <div role="group" aria-label="Sessions" class="flex flex-wrap gap-1">
              <div
                :for={session <- @sessions}
                class={["dx-tab", session.target == @active && "dx-tab-on"]}
              >
                <button
                  id={"tab-#{session.id}"}
                  type="button"
                  class="dx-tab-sel"
                  aria-pressed={to_string(session.target == @active)}
                  phx-click="select"
                  phx-value-target={session.target}
                >
                  <Tags.lang name={session.language} small />{title(session.target, @host_name)}
                  <span class="dx-tab-kind">{kind(session.kind)}</span>
                </button>
                <button
                  type="button"
                  class="dx-tab-x"
                  aria-label={"Close the session on #{title(session.target, @host_name)}"}
                  phx-click="close"
                  phx-value-target={session.target}
                >
                  <Icons.icon name="x-mark" stroke="2.2" class="dx-ico size-[13px]" />
                </button>
              </div>
            </div>
            <div class="mb-1">
              <Menu.menu
                id="new-session"
                label="New session"
                button_class="dx-btn"
                panel_class="left-0 right-auto w-[300px]"
              >
                <:button><Icons.icon name="plus" stroke="2" class="dx-ico size-4" /> New session</:button>
                <Menu.item
                  :for={target <- @available}
                  id={"new-#{target.target}"}
                  class="justify-between"
                  phx-click="new"
                  phx-value-target={target.target}
                >
                  <span class="inline-flex items-center gap-2">
                    <Tags.lang name={target.language} small /><span class="dx-mono text-[0.8125rem]">{target.title}</span>
                  </span>
                  <span class="dx-muted text-xs">{target.kind}</span>
                </Menu.item>
                <p :if={@available == []} class="dx-muted p-2.5 text-[0.8125rem]">
                  Every session is open.
                </p>
              </Menu.menu>
            </div>
            <button
              id="terminal-shortcuts"
              type="button"
              class="dx-btn mb-1 ml-auto min-h-[30px]"
              aria-pressed={to_string(@help_open)}
              phx-click="toggle-help"
            >
              Shortcuts
            </button>
          </div>

          <div :if={@active_session} class="flex flex-wrap">
            <div class="dx-term flex-[999_1_520px]">
              <div
                id={"xterm-#{@active_session.id}"}
                class="dx-xterm flex-1"
                phx-hook="XTerm"
                phx-update="ignore"
                data-target={@active_session.target}
                data-focus
                role="log"
                aria-label={"Output of #{title(@active_session.target, @host_name)}"}
              >
              </div>
            </div>
            <aside :if={@help_open} class="dx-help" aria-label="Shortcuts" tabindex="0">
              <h2 class="text-sm font-bold">{help_title(@active_session.kind)}</h2>
              <p
                :if={@active_session.kind == :host_shell}
                class="text-[0.8125rem] font-semibold text-warning-text"
              >
                This shell runs as the deployex user. It can read the release and the logs of every app on this host.
              </p>
              <div>
                <div :for={{command, description} <- shortcuts(@active_session.kind)} class="dx-sc">
                  <code>{command}</code><span>{description}</span>
                </div>
              </div>
            </aside>
          </div>

          <div
            :if={is_nil(@active_session)}
            class="flex flex-col items-center gap-2.5 px-6 py-12 text-center"
          >
            <p class="text-base font-semibold">No open session</p>
            <p class="dx-muted text-[0.8125rem]">
              Open an IEx shell on an instance, or a shell on this host, with New session.
            </p>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:user, user_key(socket.assigns.current_user))
     |> assign(:host_name, host_name())
     |> assign(:help_open, true)
     |> assign(:attached, nil)
     |> assign(:page_title, "Terminal")
     |> assign(:current_path, "/terminal")
     |> load_sessions()}
  end

  @impl true
  def handle_params(params, _url, %{assigns: %{sessions: sessions}} = socket) do
    active =
      case params["target"] do
        target when is_binary(target) -> target
        _ -> sessions |> List.first() |> then(&(&1 && &1.target))
      end

    {:noreply, socket |> assign(:active, active) |> attach()}
  end

  @impl true
  def handle_event("select", %{"target" => target}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/terminal?target=#{target}")}

  def handle_event("new", %{"target" => target}, %{assigns: %{user: user}} = socket) do
    case Shell.open(user, target) do
      {:ok, _session} ->
        {:noreply, socket |> load_sessions() |> push_patch(to: ~p"/terminal?target=#{target}")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Could not open a shell on #{target}: #{inspect(reason)}")}
    end
  end

  def handle_event("close", %{"target" => target}, %{assigns: %{user: user}} = socket) do
    Shell.close(user, target)
    {:noreply, socket}
  end

  def handle_event("toggle-help", _params, socket),
    do: {:noreply, update(socket, :help_open, &(!&1))}

  def handle_event(
        "shell-keys",
        %{"target" => target, "keys" => keys},
        %{assigns: %{user: user}} = socket
      ) do
    Shell.send_keys(user, target, keys)
    {:noreply, socket}
  end

  def handle_event("shell-resize", %{"target" => target, "rows" => rows, "cols" => cols}, socket)
      when is_integer(rows) and is_integer(cols) do
    Shell.resize(socket.assigns.user, target, rows, cols)
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:shell_output, id, data},
        %{assigns: %{attached: %{id: id, target: target}}} = socket
      ),
      do: {:noreply, push_event(socket, "shell-output-#{target}", %{data: data})}

  def handle_info({:shell_closed, _id}, %{assigns: %{active: active}} = socket) do
    socket = socket |> assign(:attached, nil) |> load_sessions()

    if Enum.any?(socket.assigns.sessions, &(&1.target == active)) do
      {:noreply, socket}
    else
      {:noreply, push_patch(socket, to: ~p"/terminal")}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # Follows the active session, and stops following the one before. Both keep running
  defp attach(%{assigns: %{active: active, attached: attached}} = socket) do
    if attached && attached.target != active, do: Shell.detach(attached)

    cond do
      not connected?(socket) or is_nil(active) -> assign(socket, :attached, nil)
      attached && attached.target == active -> socket
      true -> attach_active(socket)
    end
  end

  defp attach_active(%{assigns: %{user: user, active: active}} = socket) do
    case Shell.attach(user, active) do
      {:ok, session, scrollback} ->
        socket
        |> assign(:attached, session)
        |> push_event("shell-reset-#{active}", %{data: scrollback})

      :error ->
        assign(socket, :attached, nil)
    end
  end

  defp load_sessions(%{assigns: %{user: user, host_name: host_name}} = socket) do
    sessions = Shell.list(user)
    open = MapSet.new(sessions, & &1.target)

    available =
      [Shell.host(), "deployex" | Enum.map(Monitor.list(), &to_string/1)]
      |> Enum.reject(&MapSet.member?(open, &1))
      |> Enum.map(&target(&1, host_name))

    assign(socket, sessions: sessions, available: available)
  end

  defp target("host", host_name),
    do: %{target: "host", title: host_name, kind: "Host shell", language: "linux"}

  defp target("deployex", _host_name),
    do: %{target: "deployex", title: "deployex", kind: "IEx", language: "deployex"}

  defp target(sname, _host_name) do
    language =
      case Catalog.node_info(sname) do
        %{language: language} when is_binary(language) -> language
        _ -> "elixir"
      end

    %{
      target: sname,
      title: sname,
      kind: if(language == "elixir", do: "IEx", else: "Erlang shell"),
      language: language
    }
  end

  defp title("host", host_name), do: host_name
  defp title(target, _host_name), do: target

  defp kind(:host_shell), do: "Host shell"
  defp kind(:iex), do: "IEx"
  defp kind(:erlang_shell), do: "Erlang shell"

  defp help_title(:iex), do: "IEx shortcuts"
  defp help_title(:erlang_shell), do: "Erlang shell shortcuts"
  defp help_title(:host_shell), do: "tmux keys"

  defp shortcuts(kind), do: Map.fetch!(@shortcuts, kind)

  @doc false
  def user_key(%{username: username}) when is_binary(username), do: username
  def user_key(%{email: email}) when is_binary(email), do: email
  def user_key(_user), do: "unknown"

  defp host_name do
    {:ok, name} = :inet.gethostname()
    to_string(name)
  end
end
