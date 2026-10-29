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
  alias DeployexWeb.UI.ShellHelp
  alias DeployexWeb.UI.Tags
  alias Foundation.Catalog

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:active_session, Enum.find(assigns.sessions, &(&1.target == assigns.active)))
      |> assign(:split_session, Enum.find(assigns.sessions, &(&1.target == assigns.split)))

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
                class={["dx-tab", session.target in [@active, @split] && "dx-tab-on"]}
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
              :if={@active_session && is_nil(@split_session)}
              id="terminal-split"
              type="button"
              class="dx-btn mb-1 min-h-[30px]"
              aria-pressed={to_string(@picking)}
              phx-click={if @picking, do: "unsplit", else: "split-pick"}
            >
              <Icons.icon name="split" stroke="1.8" class="dx-ico size-4" /> Split
            </button>
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
            <div class="dx-panes flex-[999_1_520px]">
              <.pane
                session={@active_session}
                host_name={@host_name}
                split={@split_session != nil or @picking}
              />
              <.pane
                :if={@split_session}
                session={@split_session}
                host_name={@host_name}
                split
                second
              />
              <div :if={@picking} class="dx-pane" role="group" aria-label="Show beside">
                <div class="dx-pane-head">
                  <span class="font-semibold">Show beside {title(@active_session.target, @host_name)}</span>
                  <button
                    id="terminal-unsplit"
                    type="button"
                    class="dx-ghost size-7"
                    aria-label="Close the second pane"
                    title="Close the pane"
                    phx-click="unsplit"
                  >
                    <Icons.icon name="x-mark" stroke="2.2" class="dx-ico size-[13px]" />
                  </button>
                </div>
                <div class="dx-picks">
                  <button
                    :for={option <- split_options(@active_session, @sessions, @available, @host_name)}
                    id={"pick-#{option.target}"}
                    type="button"
                    class="dx-pick"
                    phx-click="split-open"
                    phx-value-target={option.target}
                  >
                    <Tags.lang name={option.language} small />
                    <span class="dx-mono truncate">{option.title}</span>
                    <b>{option.kind}</b>
                    <span class="dx-muted ml-auto">{option.note}</span>
                  </button>
                </div>
              </div>
            </div>
            <ShellHelp.help :if={@help_open} kind={@active_session.kind} />
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

  attr :session, :map, required: true
  attr :host_name, :string, required: true
  attr :split, :boolean, default: false, doc: "whether two panes show, each with a head"
  attr :second, :boolean, default: false, doc: "the pane on the right, which Close takes away"

  # One shell. With a split, each pane names its session, and the second can close back to one pane
  defp pane(assigns) do
    ~H"""
    <div class="dx-pane">
      <div :if={@split} class="dx-pane-head">
        <span class="inline-flex min-w-0 items-center gap-2">
          <Tags.lang name={@session.language} small />
          <span class="dx-mono truncate">{title(@session.target, @host_name)}</span>
          <span class="dx-muted">{kind(@session.kind)}</span>
        </span>
        <button
          :if={@second}
          id="terminal-unsplit"
          type="button"
          class="dx-ghost size-7"
          aria-label="Close the second pane. The session keeps running"
          title="Close the pane"
          phx-click="unsplit"
        >
          <Icons.icon name="x-mark" stroke="2.2" class="dx-ico size-[13px]" />
        </button>
      </div>
      <div class="dx-term">
        <div
          id={"xterm-#{@session.id}"}
          class="dx-xterm flex-1"
          phx-hook="XTerm"
          phx-update="ignore"
          data-target={@session.target}
          data-focus={!@second}
          role="log"
          aria-label={"Output of #{title(@session.target, @host_name)}"}
        >
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:user, user_key(socket.assigns.current_user))
     |> assign(:host_name, host_name())
     |> assign(:help_open, true)
     |> assign(:attached, %{})
     |> assign(:split, nil)
     |> assign(:picking, false)
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

    # The second pane shows another open session, never the first one again
    split =
      with target when is_binary(target) and target != active <- params["split"],
           true <- Enum.any?(sessions, &(&1.target == target)) do
        target
      else
        _ -> nil
      end

    {:noreply, socket |> assign(active: active, split: split, picking: false) |> attach()}
  end

  @impl true
  def handle_event("select", %{"target" => target}, %{assigns: assigns} = socket) do
    # The second pane's tab swaps the panes, so both sessions stay in view
    split = if target == assigns.split, do: assigns.active, else: assigns.split
    {:noreply, push_patch(socket, to: pane_path(target, split))}
  end

  def handle_event("split-pick", _params, socket), do: {:noreply, assign(socket, :picking, true)}

  # A pick opens its session when it is not open yet, and shows it in the second pane
  def handle_event("split-open", %{"target" => target}, %{assigns: assigns} = socket) do
    if Enum.any?(assigns.sessions, &(&1.target == target)) do
      {:noreply, push_patch(socket, to: pane_path(assigns.active, target))}
    else
      case Shell.open(assigns.user, target) do
        {:ok, _session} ->
          {:noreply,
           socket |> load_sessions() |> push_patch(to: pane_path(assigns.active, target))}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "Could not open a shell on #{target}: #{inspect(reason)}")}
      end
    end
  end

  def handle_event("unsplit", _params, %{assigns: %{split: nil}} = socket),
    do: {:noreply, assign(socket, :picking, false)}

  def handle_event("unsplit", _params, %{assigns: %{active: active}} = socket),
    do: {:noreply, push_patch(socket, to: pane_path(active, nil))}

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
  def handle_info({:shell_output, id, data}, %{assigns: %{attached: attached}} = socket) do
    case Enum.find(attached, fn {_target, session} -> session.id == id end) do
      {target, _session} ->
        {:noreply, push_event(socket, "shell-output-#{target}", %{data: data})}

      nil ->
        {:noreply, socket}
    end
  end

  # A closed session leaves its pane. The other pane stays, alone
  def handle_info({:shell_closed, id}, %{assigns: assigns} = socket) do
    socket =
      socket
      |> update(:attached, &Map.reject(&1, fn {_target, session} -> session.id == id end))
      |> load_sessions()

    open = MapSet.new(socket.assigns.sessions, & &1.target)

    cond do
      MapSet.member?(open, assigns.active) and
          (is_nil(assigns.split) or MapSet.member?(open, assigns.split)) ->
        {:noreply, socket}

      MapSet.member?(open, assigns.active) ->
        {:noreply, push_patch(socket, to: pane_path(assigns.active, nil))}

      MapSet.member?(open, assigns.split || "") ->
        {:noreply, push_patch(socket, to: pane_path(assigns.split, nil))}

      true ->
        {:noreply, push_patch(socket, to: ~p"/terminal")}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # Follows the sessions in the panes, and stops following the others. Every session keeps running
  defp attach(%{assigns: %{active: active, split: split, attached: attached}} = socket) do
    wanted = Enum.reject([active, split], &is_nil/1)

    for {target, session} <- attached, target not in wanted, do: Shell.detach(session)
    socket = assign(socket, :attached, Map.take(attached, wanted))

    if connected?(socket) do
      Enum.reduce(wanted, socket, fn target, socket ->
        if Map.has_key?(socket.assigns.attached, target),
          do: socket,
          else: attach_target(socket, target)
      end)
    else
      socket
    end
  end

  defp attach_target(%{assigns: %{user: user}} = socket, target) do
    case Shell.attach(user, target) do
      {:ok, session, scrollback} ->
        socket
        |> update(:attached, &Map.put(&1, target, session))
        |> push_event("shell-reset-#{target}", %{data: scrollback})

      :error ->
        socket
    end
  end

  # What the picker offers beside a session: the other instances of its app first, then DeployEx, this
  # host, and the sessions open already
  defp split_options(active, sessions, available, host_name) do
    app = app_of(active.target)

    open =
      Enum.map(sessions, fn session ->
        %{
          target: session.target,
          title: title(session.target, host_name),
          kind: kind(session.kind),
          language: session.language
        }
      end)

    known = Map.new(open ++ available, &{&1.target, &1})

    siblings =
      for {target, option} <- known, app && String.starts_with?(target, "#{app}-"), do: option

    others = for target <- ["deployex", Shell.host()], option = known[target], do: option

    (Enum.map(siblings, &Map.put(&1, :note, "another instance")) ++
       Enum.map(
         others,
         &Map.put(&1, :note, if(&1.target == "deployex", do: "DeployEx", else: "this host"))
       ) ++
       Enum.map(open, &Map.put(&1, :note, "open")))
    |> Enum.uniq_by(& &1.target)
    |> Enum.reject(&(&1.target == active.target))
  end

  defp app_of(target) do
    case Catalog.node_info(target) do
      %{name: name} -> name
      _ -> nil
    end
  end

  defp pane_path(target, nil), do: ~p"/terminal?#{%{target: target}}"
  defp pane_path(target, split), do: ~p"/terminal?#{%{target: target, split: split}}"

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

  @doc false
  def user_key(%{username: username}) when is_binary(username), do: username
  def user_key(%{email: email}) when is_binary(email), do: email
  def user_key(_user), do: "unknown"

  defp host_name do
    {:ok, name} = :inet.gethostname()
    to_string(name)
  end
end
