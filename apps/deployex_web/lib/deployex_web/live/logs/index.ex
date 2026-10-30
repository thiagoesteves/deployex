defmodule DeployexWeb.LogsLive do
  @moduledoc """
  The Logs page: the stdout and stderr of DeployEx and every instance, live or from the stored history.

  The page opens on DeployEx and its events. An app is shown only when it is selected, so the page reads
  what was asked for, not every source of the host. `/logs/live` opens with the last 5 minutes and then
  follows new lines, sent to the browser in batches. `/logs/history` reads a time range. `source` (one or
  a comma list) and `stream` in the query select the sources and the stream.
  `since` (unix seconds) picks the shortest range that covers it, and `filter` sets the text filter. The page keeps at most #{2_000} lines,
  newest at the bottom.
  """
  use DeployexWeb, :live_view

  alias DeployexWeb.HostTime
  alias DeployexWeb.LogsExport
  alias DeployexWeb.RecentEvents
  alias DeployexWeb.UI.Icons
  alias DeployexWeb.UI.LogActions
  alias DeployexWeb.UI.Menu
  alias Foundation.Notifications.Recent

  # The events source follows this host's notifications, which the bell's hook passes on
  on_mount {RecentEvents, :forward}

  alias Deployer.Monitor
  alias DeployexWeb.UI.Tags
  alias Foundation.Catalog
  alias Sentinel.Logs

  @cap 2_000
  # New lines wait this long, so a busy source updates the page a few times a second, not once a line
  @flush_ms 250
  @default_sources ["events", "deployex"]
  @live_minutes 5
  @default_range 30
  @types ["stdout", "stderr"]
  @ranges [
    {"1m", 1},
    {"5m", 5},
    {"15m", 15},
    {"30m", 30},
    {"1h", 60},
    {"6h", 360},
    {"12h", 720},
    {"1d", 1_440},
    {"3d", 4_320},
    {"1w", 10_080}
  ]
  @colors [
    "--dx-info-text",
    "--dx-success-text",
    "--dx-primary-text",
    "--dx-warning-text",
    "--dx-hot-text"
  ]

  @impl true
  def render(assigns) do
    assigns = assign(assigns, ranges: @ranges, cap: @cap)

    ~H"""
    <Layouts.app
      flash={@flash}
      current_path={@current_path}
      current_user={@current_user}
      host_info={@host_info}
      recent_events={@recent_events}
      socket={@socket}
    >
      <div class="mx-auto flex max-w-[1180px] flex-col gap-4 px-7 pt-6 pb-12 max-md:px-4">
        <header class="flex flex-wrap items-center justify-between gap-x-6 gap-y-3">
          <div>
            <h1 class="text-[1.625rem] font-bold tracking-[-0.02em]">Logs</h1>
            <p class="dx-muted dx-mono mt-1 text-[0.8125rem]">
              {@host_name} · stdout and stderr of DeployEx and every instance
            </p>
          </div>
          <div class="dx-seg2" role="group" aria-label="Log mode">
            <button
              id="logs-live"
              type="button"
              aria-pressed={to_string(@mode == :live)}
              phx-click="mode"
              phx-value-mode="live"
            >
              Live
            </button>
            <button
              id="logs-history"
              type="button"
              aria-pressed={to_string(@mode == :history)}
              phx-click="mode"
              phx-value-mode="history"
            >
              History
            </button>
          </div>
        </header>

        <section class="dx-card flex flex-col gap-3 px-4 py-3.5" aria-label="Log filters">
          <div class="flex flex-wrap items-center gap-2">
            <span class="dx-lbl w-16">Sources</span>
            <ul class="contents" aria-label="Selected sources">
              <li :for={chip <- chips(@groups, @selected)} id={chip.id} class="dx-src">
                <span class="dx-dot" style={"color: var(#{chip.color})"}></span>
                <Icons.icon :if={chip.icon == :bell} name="bell" class="dx-ico size-4" />
                <Tags.lang :if={chip.icon != :bell} name={chip.icon} small />{chip.label}
                <button
                  type="button"
                  class="dx-s-untag"
                  aria-label={"Remove #{chip.label}"}
                  phx-click={chip.event}
                  phx-value-name={chip.name}
                >
                  <Icons.icon name="x-mark" stroke="2.2" class="dx-ico size-3.5" />
                </button>
              </li>
            </ul>
            <span :if={MapSet.size(@selected) == 0} class="dx-muted text-[0.8125rem]">None selected.</span>
            <.source_picker groups={@groups} selected={@selected} />
          </div>
          <div class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2.5">
            <div class="flex min-w-0 max-w-full flex-wrap items-center gap-2">
              <span class="dx-lbl w-16">Streams</span>
              <button
                :for={type <- ["stdout", "stderr"]}
                id={"stream-#{type}"}
                type="button"
                class="dx-tog"
                aria-pressed={to_string(MapSet.member?(@types, type))}
                phx-click="toggle-stream"
                phx-value-type={type}
              >
                <Icons.icon
                  :if={MapSet.member?(@types, type)}
                  name="check"
                  stroke="2.4"
                  class="dx-ico dx-tog-check size-3.5"
                />
                <span style={type == "stderr" && "color: var(--dx-error-text)"}>{type}</span>
              </button>
              <form
                id="logs-filter"
                phx-change="filter"
                phx-submit="filter"
                class="w-80 max-w-full"
              >
                <input
                  class="dx-filter"
                  type="search"
                  name="filter"
                  value={@filter}
                  placeholder="Filter lines, for example error"
                  aria-label="Filter log lines"
                  phx-debounce="200"
                  autocomplete="off"
                />
              </form>
            </div>
            <div :if={@mode == :live} class="flex items-center gap-2.5">
              <Tags.status
                text={if @paused, do: "Paused", else: "Streaming"}
                tone={if @paused, do: :warning, else: :success}
              />
              <button id="logs-pause" type="button" class="dx-btn" phx-click="pause">
                {if @paused, do: "Resume", else: "Pause"}
              </button>
              <button id="logs-clear" type="button" class="dx-btn" phx-click="clear">Clear</button>
            </div>
            <div
              :if={@mode == :history}
              role="group"
              aria-label="Time range"
              class="flex flex-wrap items-center gap-0.5"
            >
              <span class="dx-lbl mr-1.5">Last</span>
              <button
                :for={{label, minutes} <- @ranges}
                id={"range-#{label}"}
                type="button"
                class="dx-rng"
                aria-pressed={to_string(@range == minutes)}
                phx-click="range"
                phx-value-minutes={minutes}
              >
                {label}
              </button>
            </div>
          </div>
        </section>

        <section class="dx-card overflow-hidden" aria-label="Log lines">
          <div class="flex flex-wrap items-center justify-between gap-2 border-b border-(--dx-base-300) px-[18px] py-2.5 text-[0.8125rem]">
            <span class="dx-muted" id="logs-summary">{summary(
              @shown,
              @cap,
              @selected,
              @sources,
              @types
            )}</span>
            <div class="flex items-center gap-3">
              <span class="dx-muted">Host time {@zone} · newest at the bottom</span>
              <LogActions.actions
                id="logs"
                rows="logs-lines"
                empty={@shown == 0}
                export={export_params(assigns)}
              />
            </div>
          </div>
          <div
            id="logs-pane"
            class="dx-logpane"
            role="log"
            aria-live="off"
            aria-label="Log lines"
            tabindex="0"
            phx-hook="ScrollBottom"
          >
            <div id="logs-lines" phx-update="stream">
              <div :for={{dom_id, line} <- @streams.lines} id={dom_id} class="dx-lrow">
                <span class="dx-muted">{HostTime.format(line.at, "%H:%M:%S.%f")
                |> String.slice(0, 12)}</span>
                <span class="truncate" style={"color: var(#{line.color})"} title={line.source}>{line.source}</span>
                <span style={"color: #{if line.type == "stderr", do: "var(--dx-error-text)", else: "var(--dx-muted)"}"}>
                  {line.type}
                </span>
                <span class="dx-lmsg" style={"color: #{message_color(line)}"} phx-no-format>{highlight(line.text, @filter)}</span>
              </div>
            </div>
            <p :if={@shown == 0} class="dx-muted px-[18px] py-6 text-[0.8125rem]">
              {if @mode == :live,
                do: "No lines yet. New lines show here as they arrive.",
                else: "No lines in this range. Pick a longer range or turn on more sources."}
            </p>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :groups, :list, required: true
  attr :selected, :any, required: true

  # Every source by app: an app button takes all its instances, an instance button one
  defp source_picker(assigns) do
    apps = Enum.reject(assigns.groups, &is_nil(&1.app))
    instances = Enum.flat_map(apps, & &1.sources)

    assigns =
      assign(assigns,
        apps: apps,
        count: length(instances),
        every: all?(instances, assigns.selected)
      )

    ~H"""
    <Menu.menu
      id="logs-sources"
      label="Select the sources"
      button_class="dx-btn"
      panel_class="dx-menu-below dx-picker left-0 right-auto"
      panel_label="Sources"
    >
      <:button>
        <Icons.icon name="plus" stroke="2" class="dx-ico size-3.5" /> Select
        <Icons.icon name="chevron-down" stroke="2" class="dx-ico size-3" />
      </:button>
      <div :for={group <- @groups} class="dx-picker-row">
        <%= if group.app do %>
          <.pick
            id={"pick-app-#{group.app}"}
            pressed={pressed(group.sources, @selected)}
            color={group.color}
            label={group.app}
            event="toggle-app"
            name={group.app}
          >
            <Tags.lang name={group.lang} small />{group.app}
            <span :if={length(group.sources) > 1} class="dx-muted">{length(group.sources)}</span>
          </.pick>
          <.pick
            :for={source <- group.sources}
            :if={length(group.sources) > 1}
            id={"pick-#{source.sname}"}
            pressed={pressed([source], @selected)}
            color={source.color}
            label={source.sname}
            event="toggle-source"
            name={source.sname}
          >
            {source.sname |> String.split("-") |> List.last()}
          </.pick>
        <% else %>
          <.pick
            :for={source <- group.sources}
            id={"pick-#{source.sname}"}
            pressed={pressed([source], @selected)}
            color={source.color}
            label={source.sname}
            event="toggle-source"
            name={source.sname}
          >
            <Icons.icon :if={source.sname == "events"} name="bell" class="dx-ico size-4" />
            <Tags.lang :if={source.sname != "events"} name={source.lang} small />{source.sname}
          </.pick>
        <% end %>
      </div>
      <div :if={@apps != []} class="dx-picker-foot">
        <button id="pick-every-app" type="button" class="dx-btn" phx-click="every-app">
          {if @every,
            do: "Remove every app",
            else: "Add every app (#{@count} #{if @count == 1, do: "instance", else: "instances"})"}
        </button>
      </div>
      <p :if={@apps == []} class="dx-muted px-2.5 py-2 text-[0.8125rem]">
        No app on this host has logs yet.
      </p>
    </Menu.menu>
    """
  end

  attr :id, :string, required: true

  attr :pressed, :string,
    required: true,
    doc: "true, false, or mixed for an app with some instances on"

  attr :color, :string, required: true
  attr :label, :string, required: true, doc: "the accessible name, the full source or app name"
  attr :event, :string, required: true
  attr :name, :string, required: true
  slot :inner_block, required: true

  defp pick(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      class="dx-tog dx-tog-sm"
      aria-pressed={@pressed}
      aria-label={@label}
      phx-click={@event}
      phx-value-name={@name}
    >
      <Icons.icon
        :if={@pressed == "true"}
        name="check"
        stroke="2.4"
        class="dx-ico dx-tog-check size-3"
      />
      <Icons.icon
        :if={@pressed == "mixed"}
        name="minus"
        stroke="2.4"
        class="dx-ico dx-tog-check size-3"
      />
      <span class="dx-dot" style={"color: var(#{@color})"}></span>
      {render_slot(@inner_block)}
    </button>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:host_name, host_name())
     |> assign(:zone, HostTime.zone())
     |> assign(:filter, "")
     |> assign(:paused, false)
     |> assign(:pending, [])
     |> assign(:queued, [])
     |> assign(:flushing, false)
     |> assign(:buffer, [])
     |> assign(:shown, 0)
     |> assign(:range, @default_range)
     |> assign(:opened_at, System.os_time(:millisecond))
     |> assign(:cleared_at, 0)
     |> assign(:subscribed, [])
     |> stream(:lines, [])}
  end

  @impl true
  def handle_params(params, _url, %{assigns: %{live_action: mode}} = socket) do
    sources = sources(mode)
    snames = MapSet.new(sources, & &1.sname)

    # A comma list of sources selects the known ones, and DeployEx and its events when none is known
    picked =
      case params["source"] do
        list when is_binary(list) ->
          list |> String.split(",") |> MapSet.new() |> MapSet.intersection(snames)

        _ ->
          MapSet.new()
      end

    selected =
      if Enum.empty?(picked),
        do: MapSet.intersection(MapSet.new(@default_sources), snames),
        else: picked

    types =
      if params["stream"] in @types, do: MapSet.new([params["stream"]]), else: MapSet.new(@types)

    socket = assign(socket, :range, range_since(params["since"], socket.assigns.range))

    socket =
      if is_binary(params["filter"]), do: assign(socket, :filter, params["filter"]), else: socket

    {:noreply,
     socket
     |> assign(:mode, mode)
     |> assign(:page_title, if(mode == :live, do: "Live Logs", else: "History Logs"))
     |> assign(:current_path, if(mode == :live, do: "/logs/live", else: "/logs/history"))
     |> assign(:sources, sources)
     |> assign(:groups, groups(sources))
     |> assign(:selected, selected)
     |> assign(:types, types)
     |> subscribe()
     |> reload()}
  end

  @impl true
  def handle_event("mode", %{"mode" => "live"}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/logs/live")}

  def handle_event("mode", %{"mode" => "history"}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/logs/history")}

  def handle_event("toggle-source", %{"name" => sname}, socket) do
    {:noreply, socket |> update(:selected, &toggle(&1, sname)) |> subscribe() |> reload()}
  end

  def handle_event("toggle-app", %{"name" => app}, socket) do
    snames = for %{app: ^app, sname: sname} <- socket.assigns.sources, do: sname
    {:noreply, socket |> update(:selected, &toggle_all(&1, snames)) |> subscribe() |> reload()}
  end

  def handle_event("every-app", _params, socket) do
    snames = for %{app: app, sname: sname} <- socket.assigns.sources, app != nil, do: sname
    {:noreply, socket |> update(:selected, &toggle_all(&1, snames)) |> subscribe() |> reload()}
  end

  def handle_event("toggle-stream", %{"type" => type}, socket) when type in @types do
    {:noreply, socket |> update(:types, &toggle(&1, type)) |> subscribe() |> reload()}
  end

  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply, socket |> assign(:filter, filter) |> show_lines(socket.assigns.buffer)}
  end

  def handle_event("pause", _params, %{assigns: %{paused: false}} = socket),
    do: {:noreply, assign(socket, :paused, true)}

  # New lines that arrived during the pause are kept, and show now
  def handle_event("pause", _params, %{assigns: %{pending: pending}} = socket) do
    {:noreply, socket |> assign(paused: false, pending: []) |> append(Enum.reverse(pending))}
  end

  def handle_event("clear", _params, socket) do
    {:noreply,
     socket
     |> assign(
       cleared_at: System.os_time(:millisecond),
       buffer: [],
       pending: [],
       queued: [],
       shown: 0
     )
     |> stream(:lines, [], reset: true)}
  end

  def handle_event("range", %{"minutes" => minutes}, socket) do
    {:noreply, socket |> assign(:range, String.to_integer(minutes)) |> reload()}
  end

  @impl true
  def handle_info({:recent_notification, recent}, %{assigns: %{mode: :live} = assigns} = socket) do
    cond do
      not MapSet.member?(assigns.selected, "events") ->
        {:noreply, socket}

      assigns.paused ->
        {:noreply, update(socket, :pending, &Enum.take([event_line(recent) | &1], @cap))}

      true ->
        {:noreply, queue(socket, [event_line(recent)])}
    end
  end

  def handle_info({:recent_notification, _recent}, socket), do: {:noreply, socket}

  def handle_info({:logs_new_data, sname, type, message}, %{assigns: assigns} = socket) do
    lines = lines(sname, type, [message], color(assigns.sources, sname))

    cond do
      # A line already in the mailbox when Live changed to History, or its source turned off
      assigns.mode != :live or {sname, type} not in assigns.subscribed ->
        {:noreply, socket}

      assigns.paused ->
        {:noreply, update(socket, :pending, &Enum.take(Enum.reverse(lines) ++ &1, @cap))}

      true ->
        {:noreply, queue(socket, lines)}
    end
  end

  # The queued lines show at once. A pause that came after they arrived keeps them for Resume
  def handle_info(:flush_lines, %{assigns: %{queued: queued}} = socket) do
    socket = assign(socket, queued: [], flushing: false)

    if socket.assigns.paused do
      {:noreply, update(socket, :pending, &Enum.take(queued ++ &1, @cap))}
    else
      {:noreply, append(socket, Enum.reverse(queued))}
    end
  end

  # Follows each selected source and stream, and stops following the ones turned off
  defp subscribe(%{assigns: %{mode: :live, subscribed: subscribed} = assigns} = socket) do
    wanted = if connected?(socket), do: pairs(assigns), else: []

    for {sname, type} <- subscribed -- wanted, do: Logs.unsubscribe_for_new_logs(sname, type)
    for {sname, type} <- wanted -- subscribed, do: Logs.subscribe_for_new_logs(sname, type)

    assign(socket, :subscribed, wanted)
  end

  defp subscribe(%{assigns: %{subscribed: subscribed}} = socket) do
    for {sname, type} <- subscribed, do: Logs.unsubscribe_for_new_logs(sname, type)
    assign(socket, :subscribed, [])
  end

  # Reads the stored lines again: the last minutes since the page opened, or the history range
  defp reload(%{assigns: assigns} = socket) do
    minutes =
      case assigns.mode do
        :live ->
          max(@live_minutes, div(System.os_time(:millisecond) - assigns.opened_at, 60_000) + 1)

        :history ->
          assigns.range
      end

    lines =
      if connected?(socket) do
        assigns
        |> pairs()
        |> Enum.flat_map(fn {sname, type} ->
          messages =
            Logs.list_data_by_sname_log_type(sname, type, from: minutes, order: :asc, limit: @cap)

          lines(sname, type, messages, color(assigns.sources, sname))
        end)
        |> Kernel.++(event_lines(assigns, minutes))
        |> Enum.filter(&(assigns.mode == :history or &1.timestamp > assigns.cleared_at))
        |> Enum.sort_by(& &1.timestamp)
        |> Enum.take(-@cap)
      else
        []
      end

    # The read holds the queued lines too
    socket
    |> assign(buffer: Enum.reverse(lines), queued: [])
    |> show_lines(Enum.reverse(lines))
  end

  # New lines wait in a queue for one flush, so they reach the page in one update
  defp queue(socket, lines) do
    socket = update(socket, :queued, &Enum.take(Enum.reverse(lines) ++ &1, @cap))

    if socket.assigns.flushing do
      socket
    else
      Process.send_after(self(), :flush_lines, @flush_ms)
      assign(socket, :flushing, true)
    end
  end

  # The buffer keeps the newest lines first, so the cap drops the oldest
  defp append(socket, lines) do
    socket
    |> update(:buffer, &Enum.take(Enum.reverse(lines) ++ &1, @cap))
    |> then(fn socket ->
      shown = Enum.filter(lines, &shows?(&1, socket.assigns.filter))

      socket
      |> stream(:lines, shown, limit: -@cap)
      |> assign(:shown, min(socket.assigns.shown + length(shown), @cap))
    end)
  end

  defp show_lines(socket, buffer) do
    shown = buffer |> Enum.reverse() |> Enum.filter(&shows?(&1, socket.assigns.filter))

    socket
    |> stream(:lines, shown, reset: true, limit: -@cap)
    |> assign(:shown, length(shown))
  end

  defp lines(sname, type, messages, color) do
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
          color: color
        }
      end)
    end)
  end

  defp sources(mode) do
    snames =
      case mode do
        :live -> Enum.map(Monitor.list(), &to_string/1)
        :history -> Enum.map(Logs.list_active_snames(), &to_string/1)
      end

    # The events, then only the sources the log server tails, with the streams it has for each
    events = %{sname: "events", app: nil, types: ["event"], lang: nil, color: "--dx-warning-text"}

    tailed =
      (["deployex"] ++ Enum.sort(snames -- ["deployex"]))
      |> Enum.map(&{&1, Enum.map(Logs.get_types_by_sname(&1), fn type -> to_string(type) end)})
      |> Enum.reject(fn {_sname, types} -> types == [] end)
      |> Enum.map(fn {sname, types} ->
        %{sname: sname, app: app_of(sname), types: types, lang: language(sname)}
      end)

    # One color for each app, so the instances of an app share it
    colors =
      tailed
      |> Enum.map(& &1.app)
      |> Enum.uniq()
      |> Enum.with_index(fn app, index ->
        {app, Enum.at(@colors, rem(index, length(@colors)))}
      end)
      |> Map.new()

    [events | Enum.map(tailed, &Map.put(&1, :color, colors[&1.app]))]
  end

  # DeployEx and its events first, then each app with its instances
  defp groups(sources) do
    {own, instances} = Enum.split_with(sources, &is_nil(&1.app))

    apps =
      instances
      |> Enum.group_by(& &1.app)
      |> Enum.sort_by(fn {app, _sources} -> app end)
      |> Enum.map(fn {app, [first | _] = sources} ->
        %{app: app, sources: sources, lang: first.lang, color: first.color}
      end)

    [%{app: nil, sources: own} | apps]
  end

  # The selected sources, with one chip for an app of several instances when all of them are on
  defp chips(groups, selected) do
    Enum.flat_map(groups, fn group ->
      on = Enum.filter(group.sources, &MapSet.member?(selected, &1.sname))

      if group.app && length(on) > 1 && length(on) == length(group.sources) do
        [
          %{
            id: "chip-app-#{group.app}",
            label: "#{group.app} · #{length(on)} instances",
            color: group.color,
            icon: group.lang,
            event: "toggle-app",
            name: group.app
          }
        ]
      else
        Enum.map(on, fn source ->
          %{
            id: "chip-#{source.sname}",
            label: source.sname,
            color: source.color,
            icon: if(source.sname == "events", do: :bell, else: source.lang),
            event: "toggle-source",
            name: source.sname
          }
        end)
      end
    end)
  end

  defp pressed(sources, selected) do
    case Enum.count(sources, &MapSet.member?(selected, &1.sname)) do
      0 -> "false"
      count when count == length(sources) -> "true"
      _some -> "mixed"
    end
  end

  defp all?(sources, selected), do: sources != [] and pressed(sources, selected) == "true"

  # An app's instances are added or removed together: all of them off when all are on, else all on
  defp toggle_all(selected, snames) do
    if Enum.all?(snames, &MapSet.member?(selected, &1)),
      do: MapSet.difference(selected, MapSet.new(snames)),
      else: MapSet.union(selected, MapSet.new(snames))
  end

  defp app_of("deployex"), do: nil

  defp app_of(sname) do
    case Catalog.node_info(sname) do
      %{name: name} when is_binary(name) and name != "" -> name
      _ -> sname
    end
  end

  # since (unix seconds) picks the shortest range that still covers that time, like a bell item's
  defp range_since(since, current) do
    with since when is_binary(since) <- since,
         {seconds, ""} <- Integer.parse(since) do
      minutes = div(System.os_time(:second) - seconds, 60) + 1

      Enum.find_value(@ranges, elem(List.last(@ranges), 1), fn {_label, range} ->
        range >= minutes && range
      end)
    else
      _ -> current
    end
  end

  # The events of this host in the read window, like the log lines. The store keeps the last ones
  defp event_lines(%{selected: selected}, minutes) do
    if MapSet.member?(selected, "events") do
      since = DateTime.add(DateTime.utc_now(), -minutes * 60)

      Recent.list()
      |> Enum.filter(&(DateTime.compare(&1.at, since) != :lt))
      |> Enum.map(&event_line/1)
    else
      []
    end
  end

  defp event_line(%Recent{at: at, event: event} = recent) do
    {tone, text} = RecentEvents.line(recent)

    %{
      id: System.unique_integer([:positive, :monotonic]),
      timestamp: DateTime.to_unix(at, :millisecond),
      at: at,
      source: "events",
      type: "event",
      text: text,
      event: event,
      color: "--dx-warning-text",
      tone: tone
    }
  end

  # The source and stream pairs to read and follow: the selected ones that the log server has
  defp pairs(%{sources: sources, selected: selected, types: types}) do
    for %{sname: sname, types: source_types} <- sources,
        MapSet.member?(selected, sname),
        type <- source_types,
        MapSet.member?(types, type),
        do: {sname, type}
  end

  defp language("deployex"), do: "deployex"

  defp language(sname) do
    case Catalog.node_info(sname) do
      %{language: language} when language in ["elixir", "erlang", "gleam"] -> language
      _ -> "deployex"
    end
  end

  defp color(sources, sname) do
    case Enum.find(sources, &(&1.sname == sname)) do
      %{color: color} -> color
      _ -> "--dx-muted"
    end
  end

  defp toggle(set, value),
    do:
      if(MapSet.member?(set, value), do: MapSet.delete(set, value), else: MapSet.put(set, value))

  defp shows?(_line, ""), do: true

  defp shows?(line, filter) do
    needle = String.downcase(filter)

    String.contains?(String.downcase(line.text), needle) or
      String.contains?(String.downcase(line.source), needle)
  end

  defp message_color(%{type: "stderr"}), do: "var(--dx-error-text)"

  defp message_color(%{type: "event", tone: tone}) when tone in [:error, :ghost],
    do: "var(--dx-error-text)"

  defp message_color(%{type: "event", tone: :warning}), do: "var(--dx-warning-text)"
  defp message_color(%{type: "event"}), do: "var(--dx-base-content)"

  defp message_color(%{text: text}) do
    cond do
      String.contains?(text, "[error]") -> "var(--dx-error-text)"
      String.contains?(text, "[warning]") -> "var(--dx-warning-text)"
      true -> "var(--dx-base-content)"
    end
  end

  # Marks each match of the filter, in any case. Each part is escaped before it goes in the markup
  defp highlight(text, ""), do: text

  defp highlight(text, filter) do
    pattern = Regex.compile!(Regex.escape(filter), "i")

    parts =
      pattern
      |> Regex.split(text, include_captures: true)
      |> Enum.map(fn part ->
        {:safe, escaped} = Phoenix.HTML.html_escape(part)

        if Regex.match?(pattern, part),
          do: [~s(<mark class="dx-mark">), escaped, "</mark>"],
          else: escaped
      end)

    {:safe, parts}
  end

  defp summary(shown, cap, selected, sources, types) do
    lines =
      if shown >= cap,
        do: "#{cap} lines, the newest",
        else: "#{shown} #{if shown == 1, do: "line", else: "lines"}"

    streams =
      case Enum.filter(@types, &MapSet.member?(types, &1)) do
        [_stdout, _stderr] -> "stdout and stderr"
        [type] -> "#{type} only"
        [] -> "no stream"
      end

    "#{lines} · #{MapSet.size(selected)} of #{length(sources)} sources · #{streams}"
  end

  # Export what the page selects. Live reads from 5 minutes before the page opened, or from Clear
  defp export_params(assigns) do
    window =
      cond do
        assigns.mode == :history -> %{minutes: assigns.range}
        assigns.cleared_at > 0 -> %{since: div(assigns.cleared_at, 1000)}
        true -> %{since: div(assigns.opened_at, 1000) - @live_minutes * 60}
      end

    Map.merge(window, %{
      sources: Enum.sort(assigns.selected),
      types: Enum.filter(@types, &MapSet.member?(assigns.types, &1)),
      filter: assigns.filter
    })
    |> LogsExport.params()
  end

  defp host_name do
    {:ok, name} = :inet.gethostname()
    to_string(name)
  end
end
