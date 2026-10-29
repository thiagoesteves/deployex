defmodule DeployexWeb.DockLive do
  @moduledoc """
  The dock: a panel at the bottom of every page with tabs for logs and shell sessions.

  It is a sticky nested LiveView in the layout, so it stays open with its tabs while the user moves
  between pages. The shell sessions belong to `DeployexWeb.Shell`, the same ones the Terminal page shows.
  A page opens a tab with the `dx:dock-open` window event, which the `Dock` hook passes on.
  """
  use DeployexWeb, :live_view

  alias DeployexWeb.Shell
  alias DeployexWeb.UI.Icons
  alias DeployexWeb.UI.ShellHelp
  alias DeployexWeb.UI.Tags
  alias Foundation.Catalog
  alias Sentinel.Logs

  @log_minutes 30
  @log_cap 500
  @types ["stdout", "stderr"]

  @impl true
  def render(assigns) do
    active_tab = Enum.find(assigns.tabs, &(&1.id == assigns.active))
    split_tab = Enum.find(assigns.tabs, &(&1.id == assigns.split))
    visible = Enum.reject([active_tab, split_tab], &is_nil/1)
    picking = assigns.split == :picker and active_tab != nil

    assigns =
      assign(assigns,
        active_tab: active_tab,
        split_tab: split_tab,
        visible: visible,
        picking: picking,
        shell_tab: Enum.find(visible, &(&1.kind == :shell)),
        options: if(picking, do: split_options(assigns.tabs, active_tab), else: [])
      )

    ~H"""
    <div id="dock" phx-hook="Dock">
      <section :if={@tabs != []} class="dx-dock" aria-label="Dock" data-dock-panel>
        <button
          type="button"
          class="dx-dock-grip"
          data-dock-grip
          aria-label="Resize the dock. Drag it, or use the up and down arrow keys."
          title="Drag to resize"
        ></button>
        <div class="dx-dock-bar">
          <div class="dx-dock-tabs" role="group" aria-label="Dock sessions">
            <div
              :for={tab <- @tabs}
              class={[
                "dx-dtab",
                tab.kind == :shell && "dx-dtab-term",
                tab.id in [@active, @split] && "dx-dtab-on"
              ]}
            >
              <button
                id={"dock-tab-#{tab.id}"}
                type="button"
                class="dx-dtab-sel"
                aria-pressed={to_string(tab.id == @active)}
                phx-click="select"
                phx-value-id={tab.id}
              >
                <Tags.lang name={tab.language} small />{tab.target}<span class="dx-dtab-kind">{tab.label}</span>
              </button>
              <button
                id={"dock-close-#{tab.id}"}
                type="button"
                class="dx-dtab-x"
                aria-label={close_label(tab)}
                title={close_label(tab)}
                phx-click="close-tab"
                phx-value-id={tab.id}
              >
                <Icons.icon name="x-mark" stroke="2.2" class="dx-ico size-[13px]" />
              </button>
            </div>
          </div>
          <div class="dx-dock-ctl">
            <button
              :if={@active_tab && is_nil(@split_tab)}
              id="dock-split"
              type="button"
              class="dx-tog dx-tog-sm mr-2"
              aria-pressed={to_string(@picking)}
              phx-click={if @picking, do: "unsplit", else: "split-pick"}
            >
              <Icons.icon name="split" stroke="1.8" class="dx-ico size-3.5" /> Split
            </button>
            <button
              :if={@shell_tab}
              id="dock-shortcuts"
              type="button"
              class="dx-tog dx-tog-sm mr-2"
              aria-pressed={to_string(@help_open)}
              phx-click="toggle-help"
            >
              Shortcuts
            </button>
            <span :if={@shell_tab} class="dx-muted mr-2 text-[0.8125rem] whitespace-nowrap">
              Closes in
              <b
                id={"dock-countdown-#{@shell_tab.id}"}
                class="dx-mono text-(--dx-base-content)"
                phx-hook="Countdown"
                data-expires={DateTime.to_iso8601(@shell_tab.session.expires_at)}
              ></b>
            </span>
            <button
              type="button"
              class="dx-ghost"
              data-dock="taller"
              aria-label="Make the dock taller"
              title="Taller"
            >
              <Icons.icon name="arrow-up" stroke="2" class="dx-ico size-4" />
            </button>
            <button
              type="button"
              class="dx-ghost"
              data-dock="shorter"
              aria-label="Make the dock shorter"
              title="Shorter"
            >
              <Icons.icon name="arrow-down" stroke="2" class="dx-ico size-4" />
            </button>
            <button
              type="button"
              class="dx-ghost"
              data-dock="minimize"
              aria-label="Minimize the dock"
              title="Minimize"
            >
              <Icons.icon name="chevron-down" stroke="2" class="dx-ico size-4" />
            </button>
            <button
              type="button"
              class="dx-ghost"
              data-dock="maximize"
              aria-pressed="false"
              aria-label="Expand the dock"
              title="Full size"
            >
              <Icons.icon name="arrows-out" stroke="2" class="dx-ico size-4" />
            </button>
            <button
              id="dock-close"
              type="button"
              class="dx-ghost"
              aria-label="Close the dock and end its sessions"
              title="Close the dock"
              phx-click="close"
            >
              <Icons.icon name="x-mark" stroke="2" class="dx-ico size-4" />
            </button>
          </div>
        </div>
        <div :if={@asking_close} class="dx-ask" role="group" aria-label="Confirm closing the dock">
          <span class="flex-[1_1_320px]">
            <b>Close the dock?</b> It ends {shell_count(@tabs)} and closes every tab.
          </span>
          <button
            id="dock-close-confirm"
            type="button"
            class="dx-btn dx-btn-danger"
            phx-click="confirm-close"
          >
            End and close
          </button>
          <button type="button" class="dx-btn" phx-click="cancel-close">Cancel</button>
        </div>
        <div class="dx-dock-body">
          <div class="dx-panes dx-dpanes">
            <.pane
              :for={tab <- @visible}
              tab={tab}
              lines={@streams.lines}
              split={@split_tab != nil or @picking}
              second={tab.id == @split}
              help={@help_open && @shell_tab != nil && tab.id == @shell_tab.id}
            />
            <div :if={@picking} class="dx-pane" role="group" aria-label="Show beside">
              <div class="dx-pane-head">
                <span class="font-semibold">Show beside {@active_tab.target}</span>
                <button
                  id="dock-unsplit"
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
                  :for={option <- @options}
                  id={"dock-pick-#{option.kind}-#{option.target}"}
                  type="button"
                  class="dx-pick"
                  phx-click="split-open"
                  phx-value-kind={option.kind}
                  phx-value-target={option.target}
                  phx-value-app={option.app}
                >
                  <Tags.lang name={option.language} small />
                  <span class="dx-mono truncate">{option.target}</span>
                  <b>{option.label}</b>
                  <span class="dx-muted ml-auto">{option.note}</span>
                </button>
                <p :if={@options == []} class="dx-muted p-3 text-[0.8125rem]">
                  Nothing else to show beside it.
                </p>
              </div>
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end

  attr :tab, :map, required: true
  attr :lines, :any, required: true, doc: "the log lines stream, for a logs tab"
  attr :split, :boolean, required: true, doc: "whether two panes show, each with a head"
  attr :second, :boolean, required: true, doc: "the pane on the right, which Close takes away"
  attr :help, :boolean, required: true, doc: "whether this shell pane shows the shortcuts"

  # One tab of the dock: its logs or its shell. With a split, each pane names its tab
  defp pane(assigns) do
    ~H"""
    <div class="dx-pane">
      <div :if={@split} class="dx-pane-head">
        <span class="inline-flex min-w-0 items-center gap-2">
          <Tags.lang name={@tab.language} small />
          <span class="dx-mono truncate">{@tab.target}</span>
          <span class="dx-muted">{@tab.label}</span>
        </span>
        <button
          :if={@second}
          id="dock-unsplit"
          type="button"
          class="dx-ghost size-7"
          aria-label="Close the second pane. Its tab stays"
          title="Close the pane"
          phx-click="unsplit"
        >
          <Icons.icon name="x-mark" stroke="2.2" class="dx-ico size-[13px]" />
        </button>
      </div>
      <%= if @tab.kind == :logs do %>
        <div class="dx-k-head">
          <span class="dx-muted dx-mono text-xs">{logs_subtitle(@tab)} · last 30 minutes, then live</span>
          <div class="flex flex-wrap items-center gap-1.5">
            <form id="dock-filter" phx-change="filter-logs" phx-submit="filter-logs">
              <input
                class="dx-filter dx-filter-sm"
                type="search"
                name="filter"
                value={@tab.filter}
                placeholder="Filter these lines"
                aria-label={"Filter the logs of #{@tab.target}"}
                phx-debounce="200"
                autocomplete="off"
              />
            </form>
            <button
              :for={type <- ["stdout", "stderr"]}
              id={"dock-stream-#{type}"}
              type="button"
              class="dx-tog dx-tog-sm"
              aria-pressed={to_string(type in @tab.types)}
              phx-click="toggle-stream"
              phx-value-type={type}
            >
              <Icons.icon
                :if={type in @tab.types}
                name="check"
                stroke="2.4"
                class="dx-ico dx-tog-check size-3"
              />
              <span style={type == "stderr" && "color: var(--dx-error-text)"}>{type}</span>
            </button>
            <button
              id="dock-open-logs"
              type="button"
              class="dx-btn"
              phx-click={
                JS.push("close-tab", value: %{id: @tab.id})
                |> JS.navigate(~p"/logs/live?#{logs_query(@tab)}")
              }
            >
              Open in Logs
            </button>
          </div>
        </div>
        <div
          id="dock-log"
          class="dx-k-log"
          role="log"
          aria-live="off"
          aria-label="Log lines"
          tabindex="0"
          phx-hook="ScrollBottom"
        >
          <div id="dock-lines" phx-update="stream">
            <div
              :for={{dom_id, line} <- @lines}
              id={dom_id}
              class="dx-k-row"
              style={"grid-template-columns: #{if line.many, do: "96px 160px 54px minmax(0, 1fr)", else: "96px 54px minmax(0, 1fr)"}"}
            >
              <span class="dx-muted">{Calendar.strftime(line.at, "%H:%M:%S.%f")
              |> String.slice(0, 12)}</span>
              <span :if={line.many} class="truncate">{line.source}</span>
              <span style={"color: #{if line.type == "stderr", do: "var(--dx-error-text)", else: "var(--dx-muted)"}"}>
                {line.type}
              </span>
              <span class="dx-k-msg" style={"color: #{message_color(line)}"} phx-no-format>{line.text}</span>
            </div>
          </div>
          <p :if={@tab.empty} class="dx-muted p-3.5 text-[0.8125rem]">
            {if @tab.filter == "",
              do: "No lines for these streams.",
              else: "No line holds #{@tab.filter}. Open in Logs reads the history too."}
          </p>
        </div>
      <% else %>
        <div class="dx-k-term flex-row">
          <div
            id={"dock-xterm-#{@tab.session.id}"}
            class="dx-xterm min-w-0 flex-1"
            phx-hook="XTerm"
            phx-update="ignore"
            data-target={@tab.target}
            data-focus={!@second}
            role="log"
            aria-label={"Shell output of #{@tab.target}"}
          >
          </div>
          <ShellHelp.help :if={@help} kind={@tab.session.kind} class="dx-help-dock" />
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:user, session["user"])
     |> assign(:tabs, [])
     |> assign(:active, nil)
     |> assign(:split, nil)
     |> assign(:attached, %{})
     |> assign(:asking_close, false)
     |> assign(:help_open, false)
     |> stream(:lines, []), layout: false}
  end

  @impl true
  def handle_event("open", %{"kind" => kind, "target" => target} = params, socket) do
    case open_tab(socket, kind, target, params["app"]) do
      {socket, nil} -> {:noreply, socket}
      {socket, id} -> {:noreply, activate(socket, id)}
    end
  end

  # A pick in the split picker opens its tab, or finds it open, in the second pane
  def handle_event("split-open", %{"kind" => kind, "target" => target} = params, socket) do
    case open_tab(socket, kind, target, params["app"]) do
      {socket, nil} -> {:noreply, socket}
      {socket, id} -> {:noreply, socket |> assign(:split, id) |> activate(socket.assigns.active)}
    end
  end

  def handle_event("split-pick", _params, socket),
    do: {:noreply, assign(socket, :split, :picker)}

  def handle_event("toggle-help", _params, socket),
    do: {:noreply, update(socket, :help_open, &(!&1))}

  # The second pane's tab swaps the panes. Another tab takes the first pane, and keeps the second
  # when the two can show together
  def handle_event("select", %{"id" => id}, %{assigns: %{active: active, split: split}} = socket) do
    split =
      cond do
        split == :picker -> nil
        id == split -> active
        both_logs?(socket.assigns.tabs, id, split) -> nil
        true -> split
      end

    {:noreply, socket |> assign(:split, split) |> activate(id)}
  end

  def handle_event("unsplit", _params, socket),
    do: {:noreply, socket |> assign(:split, nil) |> activate(socket.assigns.active)}

  def handle_event("close-tab", %{"id" => id}, socket), do: {:noreply, close_tab(socket, id)}

  def handle_event("close", _params, %{assigns: %{tabs: tabs}} = socket) do
    if Enum.any?(tabs, &(&1.kind == :shell)) do
      {:noreply, assign(socket, :asking_close, true)}
    else
      {:noreply, close_all(socket)}
    end
  end

  def handle_event("confirm-close", _params, socket), do: {:noreply, close_all(socket)}

  def handle_event("cancel-close", _params, socket),
    do: {:noreply, assign(socket, :asking_close, false)}

  def handle_event("filter-logs", %{"filter" => filter}, socket),
    do: {:noreply, socket |> update_tab(logs_id(socket), &%{&1 | filter: filter}) |> show_logs()}

  def handle_event("toggle-stream", %{"type" => type}, socket) when type in @types do
    socket =
      update_tab(socket, logs_id(socket), fn tab ->
        types = if type in tab.types, do: List.delete(tab.types, type), else: tab.types ++ [type]
        %{tab | types: types}
      end)

    {:noreply, show_logs(socket)}
  end

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
  def handle_info({:logs_new_data, sname, type, message}, %{assigns: %{tabs: tabs}} = socket) do
    shown_id = logs_id(socket)

    socket =
      Enum.reduce(tabs, socket, fn
        %{kind: :logs, snames: snames} = tab, socket ->
          if sname in snames do
            lines = lines(sname, type, [message], tab.whole_app)

            socket =
              update_tab(
                socket,
                tab.id,
                &%{&1 | buffer: Enum.take(Enum.reverse(lines) ++ &1.buffer, @log_cap)}
              )

            shown = Enum.filter(lines, &holds?(&1, tab.filter))

            if tab.id == shown_id and type in tab.types and shown != [] do
              socket
              |> stream(:lines, shown, limit: -@log_cap)
              |> update_tab(tab.id, &%{&1 | empty: false})
            else
              socket
            end
          else
            socket
          end

        _tab, socket ->
          socket
      end)

    {:noreply, socket}
  end

  def handle_info({:shell_output, id, data}, %{assigns: %{attached: attached}} = socket) do
    case Enum.find(attached, fn {_target, session} -> session.id == id end) do
      {target, _session} ->
        {:noreply, push_event(socket, "shell-output-#{target}", %{data: data})}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_info({:shell_closed, id}, %{assigns: %{tabs: tabs}} = socket) do
    case Enum.find(tabs, &(&1.kind == :shell and &1.session.id == id)) do
      nil -> {:noreply, socket}
      tab -> {:noreply, close_tab(socket, tab.id, false)}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # Opens a logs or shell tab, or finds it open, and returns its id, or nil when the shell does not start
  defp open_tab(socket, kind, target, app) do
    id = "#{kind}:#{target}"

    cond do
      Enum.any?(socket.assigns.tabs, &(&1.id == id)) -> {socket, id}
      kind == "logs" -> {update(socket, :tabs, &(&1 ++ [logs_tab(id, target, app)])), id}
      kind == "shell" -> open_shell(socket, id, target, app)
      true -> {socket, nil}
    end
  end

  defp logs_tab(id, target, app) do
    snames = log_snames(target, app)
    whole_app = target == app and target != "deployex"
    for sname <- snames, type <- @types, do: Logs.subscribe_for_new_logs(sname, type)

    %{
      id: id,
      kind: :logs,
      target: target,
      app: app || app_of(target),
      label: "Logs",
      language: language(app || target),
      snames: snames,
      whole_app: whole_app,
      types: @types,
      buffer: read_logs(snames, @types, whole_app),
      filter: "",
      empty: false
    }
  end

  defp open_shell(%{assigns: %{user: user}} = socket, id, target, app) do
    case Shell.open(user, target) do
      {:ok, session} ->
        tab = %{
          id: id,
          kind: :shell,
          target: target,
          app: app || app_of(target),
          label: if(session.kind == :iex, do: "IEx", else: "Erlang shell"),
          language: language(app || target),
          session: session
        }

        {update(socket, :tabs, &(&1 ++ [tab])), id}

      {:error, reason} ->
        {put_flash(socket, :error, "Could not open a shell on #{target}: #{inspect(reason)}"),
         nil}
    end
  end

  defp app_of("deployex"), do: "deployex"

  defp app_of(target) do
    case Catalog.node_info(target) do
      %{name: name} -> name
      _ -> target
    end
  end

  # What the split picker offers beside a tab: its own logs or shell first, then the app's other
  # instances, then the logs of every instance, then the tabs open already. Never two logs tabs
  defp split_options(tabs, %{} = active) do
    siblings = Enum.reject(instances(active.app), &(&1 == active.target))

    own =
      case active do
        %{kind: :shell, target: target} -> [{"logs", target, "this instance"}]
        %{kind: :logs, whole_app: false, target: target} -> [{"shell", target, "this instance"}]
        _whole_app_logs -> []
      end

    siblings =
      Enum.flat_map(siblings, fn sname ->
        [{"shell", sname, "another instance"}, {"logs", sname, "another instance"}]
      end)

    app_logs =
      if active.app != "deployex" and length(instances(active.app)) > 1,
        do: [{"logs", active.app, "every instance"}],
        else: []

    open = for tab <- tabs, do: {Atom.to_string(tab.kind), tab.target, "open"}

    (own ++ siblings ++ app_logs ++ open)
    |> Enum.uniq_by(fn {kind, target, _note} -> {kind, target} end)
    |> Enum.reject(fn {kind, target, _note} ->
      "#{kind}:#{target}" == active.id or (kind == "logs" and active.kind == :logs)
    end)
    |> Enum.map(fn {kind, target, note} ->
      %{
        kind: kind,
        target: target,
        app: active.app,
        note: note,
        language: language(active.app),
        label: option_label(kind, active.app)
      }
    end)
  end

  defp split_options(_tabs, nil), do: []

  defp option_label("logs", _app), do: "Logs"

  defp option_label("shell", app),
    do: if(language(app) == "elixir" or app == "deployex", do: "IEx", else: "Erlang shell")

  # The running instances of an app, by name
  defp instances("deployex"), do: []

  defp instances(app) do
    Deployer.Monitor.list()
    |> Enum.map(&to_string/1)
    |> Enum.filter(&String.starts_with?(&1, "#{app}-"))
  end

  defp activate(socket, id) do
    socket
    |> assign(:active, id)
    |> assign(:asking_close, false)
    |> attach()
    |> show_logs()
  end

  # Follows the shell sessions in the panes, and stops following the others. Every session keeps running
  defp attach(%{assigns: %{attached: attached}} = socket) do
    shells = for tab <- visible(socket.assigns), tab.kind == :shell, do: tab
    wanted = Enum.map(shells, & &1.target)

    for {target, session} <- attached, target not in wanted, do: Shell.detach(session)
    socket = assign(socket, :attached, Map.take(attached, wanted))

    Enum.reduce(shells, socket, fn %{target: target} = tab, socket ->
      if Map.has_key?(socket.assigns.attached, target),
        do: socket,
        else: attach_shell(socket, tab)
    end)
  end

  defp attach_shell(%{assigns: %{user: user}} = socket, %{id: id, target: target}) do
    case Shell.attach(user, target) do
      {:ok, session, scrollback} ->
        socket
        |> update(:attached, &Map.put(&1, target, session))
        |> push_event("shell-reset-#{target}", %{data: scrollback})

      :error ->
        close_tab(socket, id, false)
    end
  end

  # Two logs tabs cannot show together, as the dock has one stream of log lines
  defp both_logs?(tabs, id, split) do
    kinds = for tab <- tabs, tab.id in [id, split], do: tab.kind
    kinds == [:logs, :logs]
  end

  # The tabs in the panes: the active one, and the split one beside it
  defp visible(%{split: :picker} = assigns), do: visible(%{assigns | split: nil})

  defp visible(%{tabs: tabs, active: active, split: split}),
    do:
      Enum.filter([active, split], & &1)
      |> Enum.map(fn id -> Enum.find(tabs, &(&1.id == id)) end)
      |> Enum.reject(&is_nil/1)

  # The logs tab in view, which the one stream of lines shows
  defp logs_id(%{assigns: assigns}) do
    case Enum.find(visible(assigns), &(&1.kind == :logs)) do
      %{id: id} -> id
      nil -> nil
    end
  end

  defp show_logs(%{assigns: %{tabs: tabs}} = socket) do
    id = logs_id(socket)

    case Enum.find(tabs, &(&1.id == id)) do
      %{kind: :logs} = tab ->
        lines =
          tab.buffer
          |> Enum.reverse()
          |> Enum.filter(&(&1.type in tab.types and holds?(&1, tab.filter)))

        socket
        |> stream(:lines, lines, reset: true, limit: -@log_cap)
        |> update_tab(tab.id, &%{&1 | empty: lines == []})

      _shell_or_none ->
        stream(socket, :lines, [], reset: true)
    end
  end

  defp close_tab(
         %{assigns: %{tabs: tabs, active: active, user: user}} = socket,
         id,
         end_session \\ true
       ) do
    case Enum.find(tabs, &(&1.id == id)) do
      nil ->
        socket

      tab ->
        stop(tab, user, end_session)
        rest = Enum.reject(tabs, &(&1.id == id))
        {next, split} = after_close(active, socket.assigns.split, id, rest)

        socket
        |> assign(:tabs, rest)
        |> assign(:split, split)
        |> update(:attached, &Map.delete(&1, tab.target))
        |> activate(next)
    end
  end

  # The second pane takes the first one's place when the first one's tab closes, and an open picker
  # closes with it
  defp after_close(active, :picker, id, rest), do: after_close(active, nil, id, rest)
  defp after_close(id, nil, id, rest), do: {rest |> List.last() |> then(&(&1 && &1.id)), nil}
  defp after_close(id, split, id, _rest), do: {split, nil}
  defp after_close(active, id, id, _rest), do: {active, nil}
  defp after_close(active, split, _id, _rest), do: {active, split}

  defp close_all(%{assigns: %{tabs: tabs, user: user}} = socket) do
    Enum.each(tabs, &stop(&1, user, true))

    socket
    |> assign(tabs: [], active: nil, split: nil, attached: %{}, asking_close: false)
    |> stream(:lines, [], reset: true)
  end

  defp stop(%{kind: :logs, snames: snames}, _user, _end_session) do
    for sname <- snames, type <- @types, do: Logs.unsubscribe_for_new_logs(sname, type)
  end

  defp stop(%{kind: :shell, target: target, session: session}, user, end_session) do
    Shell.detach(session)
    if end_session, do: Shell.close(user, target)
  end

  defp update_tab(socket, id, fun) do
    update(socket, :tabs, fn tabs -> Enum.map(tabs, &if(&1.id == id, do: fun.(&1), else: &1)) end)
  end

  # The logs of one instance, or of every instance of an app
  defp log_snames(target, app) when target == app do
    case Enum.filter(
           Enum.map(Deployer.Monitor.list(), &to_string/1),
           &String.starts_with?(&1, "#{app}-")
         ) do
      [] -> [target]
      snames -> snames
    end
  end

  defp log_snames(target, _app), do: [target]

  # A tab for every instance of an app shows the source of each line
  defp read_logs(snames, types, many) do
    # Only the streams the log server has for each instance
    for(
      sname <- snames,
      type <- Logs.get_types_by_sname(sname),
      (type = to_string(type)) in types,
      do: {sname, type}
    )
    |> Enum.flat_map(fn {sname, type} ->
      lines(
        sname,
        type,
        Logs.list_data_by_sname_log_type(sname, type, from: @log_minutes, order: :asc),
        many
      )
    end)
    |> Enum.sort_by(& &1.timestamp)
    |> Enum.take(-@log_cap)
    |> Enum.reverse()
  end

  defp lines(sname, type, messages, many) do
    Enum.flat_map(messages, fn %{timestamp: timestamp, log: log} ->
      (log || "")
      |> String.split(["\n", "\r"], trim: true)
      |> Enum.map(fn text ->
        %{
          id: System.unique_integer([:positive, :monotonic]),
          timestamp: timestamp,
          at: DateTime.from_unix!(timestamp, :millisecond),
          source: sname,
          type: type,
          text: text,
          many: many
        }
      end)
    end)
  end

  defp language("deployex"), do: "deployex"

  defp language(name_or_sname) do
    case Catalog.node_info(name_or_sname) do
      %{language: language} when language in ["elixir", "erlang", "gleam"] ->
        language

      _ ->
        case Enum.find(Catalog.applications(), &(&1.name == name_or_sname)) do
          %{language: language} -> language
          _ -> "elixir"
        end
    end
  end

  defp logs_subtitle(%{whole_app: true, target: app}), do: "every instance of #{app}"
  defp logs_subtitle(%{target: target}), do: target

  # Live Logs with this tab's instances, its stream when only one is on, and its filter
  defp logs_query(tab) do
    stream = with [type] <- tab.types, do: type

    %{source: Enum.join(tab.snames, ","), stream: is_binary(stream) && stream, filter: tab.filter}
    |> Enum.reject(fn {_key, value} -> value in [false, nil, ""] end)
  end

  # A line holds the filter text in its message or its source, in any case
  defp holds?(_line, ""), do: true

  defp holds?(line, filter) do
    needle = String.downcase(filter)

    String.contains?(String.downcase(line.text), needle) or
      String.contains?(String.downcase(line.source), needle)
  end

  defp close_label(%{kind: :shell, label: label, target: target}),
    do: "End the #{label} session on #{target}"

  defp close_label(%{target: target}), do: "Close the logs of #{target}"

  defp shell_count(tabs) do
    case Enum.count(tabs, &(&1.kind == :shell)) do
      1 -> "1 shell session"
      count -> "#{count} shell sessions"
    end
  end

  defp message_color(%{type: "stderr"}), do: "var(--dx-error-text)"

  defp message_color(%{text: text}) do
    cond do
      String.contains?(text, "[error]") -> "var(--dx-error-text)"
      String.contains?(text, "[warning]") -> "var(--dx-warning-text)"
      true -> "var(--dx-base-content)"
    end
  end
end
