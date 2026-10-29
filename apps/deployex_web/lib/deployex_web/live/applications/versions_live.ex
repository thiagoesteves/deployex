defmodule DeployexWeb.VersionsLive do
  @moduledoc """
  Versions and mode of one application: whether DeployEx follows `current.json` or keeps a pinned
  version, and the version history of its instances.
  """
  use DeployexWeb, :live_view

  alias Deployer.Status
  alias DeployexWeb.ApplicationsLive.Board
  alias DeployexWeb.ApplicationsLive.View
  alias DeployexWeb.UI.Icons
  alias DeployexWeb.UI.Tags

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_path={@current_path}
      current_user={@current_user}
      host_info={@host_info}
      recent_events={@recent_events}
      socket={@socket}
    >
      <div class="mx-auto flex max-w-[1140px] flex-col gap-5 px-8 pt-5 pb-14 max-md:px-4">
        <Board.app_head
          name={@name}
          language={@language}
          logo={@logo}
          subtitle={"Versions and mode · #{instances(@count)} · current #{@current || "none"}"}
        />

        <section class="dx-card" aria-labelledby="mode-h">
          <div class="flex flex-wrap items-end justify-between gap-x-6 gap-y-3.5 px-[18px] py-4">
            <div class="flex min-w-0 flex-[1_1_360px] flex-col gap-2">
              <div class="flex items-center gap-2.5">
                <h2 id="mode-h" class="text-base font-bold">Mode</h2>
                <span :if={@pinned} class="dx-chip dx-s-info"><span class="dx-dot"></span>Pinned to {@pinned}</span>
                <span :if={is_nil(@pinned)} class="dx-chip dx-s-ok"><span class="dx-dot"></span>Automatic</span>
              </div>
              <p class="dx-muted text-[0.84375rem]">{mode_text(@pinned, @count)}</p>
              <p :if={@timing} class="dx-muted text-[0.84375rem]">{@timing}</p>
            </div>
            <form id="mode-form" phx-change="pick" class="flex flex-wrap items-end gap-2.5">
              <div class="dx-seg-group" role="group" aria-label="Mode">
                <button
                  id="mode-automatic"
                  type="button"
                  class="dx-seg px-3.5"
                  aria-pressed={to_string(@segment == :automatic)}
                  phx-click="segment"
                  phx-value-segment="automatic"
                >
                  Automatic
                </button>
                <button
                  id="mode-pin"
                  type="button"
                  class="dx-seg px-3.5"
                  aria-pressed={to_string(@segment == :pin)}
                  phx-click="segment"
                  phx-value-segment="pin"
                >
                  Pin a version
                </button>
              </div>
              <div :if={@segment == :pin} class="dx-field">
                <label for="pin-version">Version to pin</label>
                <select id="pin-version" name="version">
                  <option :for={version <- @versions} value={version} selected={version == @pick}>
                    {if version == @current, do: "#{version} (current)", else: version}
                  </option>
                </select>
              </div>
              <button
                :if={
                  changing?(@segment, @pick, @pinned) and not @asking and
                    (@segment == :automatic or @pick != nil)
                }
                id="mode-save"
                type="button"
                class="dx-btn dx-btn-primary min-h-10 text-[0.8125rem]"
                phx-click="ask"
              >
                {if @segment == :pin, do: "Pin #{@pick}…", else: "Set Automatic…"}
              </button>
            </form>
          </div>
          <div
            :if={@asking}
            class="dx-ask dx-ask-warn"
            role="group"
            aria-label="Confirm the mode change"
          >
            <span class="flex-[1_1_360px]">{ask_text(
              @segment,
              @name,
              @pick,
              @current,
              @count
            )}</span>
            <button
              id="mode-confirm"
              type="button"
              class="dx-btn dx-btn-primary min-h-10 text-[0.8125rem]"
              phx-click="confirm"
            >
              {if @segment == :pin, do: "Pin #{@pick}", else: "Set Automatic"}
            </button>
            <button type="button" class="dx-btn min-h-10 text-[0.8125rem]" phx-click="cancel">Cancel</button>
          </div>
        </section>

        <section class="dx-card overflow-hidden" aria-labelledby="hist-h">
          <div class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2.5 px-5 py-3.5">
            <h2 id="hist-h" class="text-base font-bold">History</h2>
            <div role="group" aria-label="Show the versions of" class="flex flex-wrap gap-1.5">
              <.link
                :for={
                  {label, sname} <- [{"All instances", nil} | Enum.map(@snames, &{suffix(&1), &1})]
                }
                class="dx-tog min-h-9 no-underline"
                aria-pressed={to_string(@filter == sname)}
                patch={
                  if sname,
                    do: ~p"/applications/#{@name}/#{sname}/versions",
                    else: ~p"/applications/#{@name}/versions"
                }
              >
                <Icons.icon
                  :if={@filter == sname}
                  name="check"
                  stroke="2.4"
                  class="dx-ico dx-tog-check size-3.5"
                />
                {label}
              </.link>
            </div>
          </div>
          <div class="overflow-x-auto">
            <div class="min-w-[720px]">
              <div class="dx-vrow min-h-[38px]">
                <div class="dx-lbl">Version</div>
                <div class="dx-lbl">Instance</div>
                <div class="dx-lbl">Deploy</div>
                <div class="dx-lbl">Deployed</div>
              </div>
              <div :for={row <- rows(@history, @filter, @currents, @now)} class="dx-vrow">
                <div class="flex items-center gap-2">
                  <b class="dx-mono text-sm">{row.version}</b>
                  <span :if={row.current} class="dx-chip dx-s-ok px-2 py-px text-xs">current</span>
                </div>
                <div class="dx-mono text-[0.8125rem]">{row.sname}</div>
                <div>
                  <Tags.deploy_tag
                    type={if row.deployment == :hot_upgrade, do: :hot, else: :full}
                    label={if row.deployment == :hot_upgrade, do: "Hot upgrade", else: "Full"}
                  />
                </div>
                <div class="flex items-baseline gap-2.5">
                  <span class="dx-mono text-[0.8125rem]">{row.at}</span>
                  <span class="dx-muted text-[0.78125rem]">{row.age}</span>
                </div>
              </div>
              <p
                :if={@history == []}
                class="dx-muted border-t border-(--dx-base-300) px-5 py-4 text-[0.84375rem]"
              >
                No version has run on this host yet.
              </p>
            </div>
          </div>
          <p class="dx-muted border-t border-(--dx-base-300) px-5 pt-3 pb-3.5 text-[0.78125rem]">
            This host keeps the releases of the last {retention()} versions.
            <.link class="dx-link" navigate={~p"/applications/#{@name}/ghosted"}>Ghosted versions</.link>
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"name" => name}, _session, socket) do
    if connected?(socket), do: Status.subscribe()

    {:ok,
     socket
     |> assign(name: name, segment: nil, pick: nil, asking: false, current_path: "/applications")
     |> assign(:page_title, "#{name} versions and mode")
     |> load()}
  end

  @impl true
  def handle_params(params, _url, socket),
    do: {:noreply, assign(socket, :filter, params["sname"])}

  @impl true
  def handle_event("segment", %{"segment" => "automatic"}, socket),
    do: {:noreply, assign(socket, segment: :automatic, asking: false)}

  def handle_event("segment", %{"segment" => "pin"}, %{assigns: assigns} = socket),
    do:
      {:noreply,
       assign(socket, segment: :pin, asking: false, pick: assigns.pick || default_pick(assigns))}

  def handle_event("pick", %{"version" => version}, socket),
    do: {:noreply, assign(socket, pick: version, asking: false)}

  def handle_event("pick", _params, socket), do: {:noreply, socket}

  def handle_event("ask", _params, socket), do: {:noreply, assign(socket, :asking, true)}
  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, :asking, false)}

  def handle_event(
        "confirm",
        _params,
        %{assigns: %{segment: :pin, pick: version, name: name}} = socket
      ) do
    Status.set_mode(name, :manual, version)

    {:noreply,
     socket
     |> assign(asking: false, segment: nil)
     |> put_flash(:info, "#{name} is pinned to #{version}")
     |> load()}
  end

  def handle_event("confirm", _params, %{assigns: %{name: name}} = socket) do
    Status.set_mode(name, :automatic, "")

    {:noreply,
     socket
     |> assign(asking: false, segment: nil)
     |> put_flash(:info, "#{name} follows current.json")
     |> load()}
  end

  @impl true
  def handle_info({:monitoring_app_updated, source_node, _statuses}, socket)
      when source_node == node(),
      do: {:noreply, load(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load(%{assigns: %{name: name}} = socket) do
    app = find_app(socket, name)
    children = app.children
    pinned = pinned(app.config)

    socket =
      socket
      |> assign(:language, app.language)
      |> assign(:logo, Enum.find_value(app.children, & &1.logo))
      |> assign(:timing, timing(app))
      |> assign(:snames, Enum.map(children, & &1.sname))
      |> assign(:count, max(app.replicas, length(children)))
      |> assign(:currents, Map.new(children, &{&1.sname, &1.version}))
      |> assign(:current, children |> Enum.map(& &1.version) |> Enum.find(& &1))
      |> assign(:pinned, pinned)
      |> assign(:versions, Map.get(app.config, :versions, []))
      |> assign(:history, history(socket, name))
      |> assign(:now, DateTime.utc_now())

    socket
    |> assign(:segment, socket.assigns.segment || if(pinned, do: :pin, else: :automatic))
    |> assign(:pick, socket.assigns.pick || pinned || default_pick(socket.assigns))
  end

  # The app's status, or an empty one before it is known
  defp find_app(socket, name) do
    statuses =
      case connected?(socket) && Status.monitoring() do
        {:ok, statuses} -> statuses
        _ -> []
      end

    case Enum.find(statuses, &(&1.name == name)) do
      %{config: config} = app when is_map(config) -> app
      app when is_map(app) -> %{app | config: %{}}
      nil -> %Status{name: name, config: %{}}
    end
  end

  defp history(socket, name),
    do: if(connected?(socket), do: Status.history_version_list(name, []), else: [])

  defp pinned(%{mode: :manual, manual_version: %{version: version}}), do: version
  defp pinned(_config), do: nil

  defp default_pick(%{versions: [latest | _] = versions, current: current}),
    do: Enum.find(versions, latest, &(&1 != current))

  defp default_pick(_assigns), do: nil

  defp changing?(:pin, pick, pinned), do: pick != pinned
  defp changing?(:automatic, _pick, pinned), do: pinned != nil
  defp changing?(_segment, _pick, _pinned), do: false

  # The newest record of each instance with the instance's running version is its current one
  defp rows(history, filter, currents, now) do
    {rows, _seen} =
      history
      |> Enum.filter(&(is_nil(filter) or &1.sname == filter))
      |> Enum.map_reduce(MapSet.new(), fn version, seen ->
        current =
          version.version == currents[version.sname] and not MapSet.member?(seen, version.sname)

        at = version.inserted_at && DateTime.from_naive!(version.inserted_at, "Etc/UTC")

        row = %{
          version: version.version,
          sname: version.sname,
          deployment: version.deployment,
          current: current,
          at: at && Calendar.strftime(at, "%Y-%m-%d %H:%M"),
          age: View.age(at, now)
        }

        {row, MapSet.put(seen, version.sname)}
      end)

    rows
  end

  defp mode_text(nil, _count),
    do: "DeployEx deploys the version that current.json names in the release bucket."

  defp mode_text(pinned, count),
    do:
      "DeployEx keeps #{every(count)} on #{pinned} and does not follow current.json until you set Automatic again."

  defp ask_text(:pin, name, pick, _current, count),
    do:
      "Pin #{name} to #{pick}? DeployEx deploys #{pick} to #{every(count)} and stops following current.json."

  defp ask_text(_segment, name, _pick, _current, _count),
    do: "Set #{name} to Automatic? DeployEx deploys the version in current.json, if it differs."

  # How often DeployEx checks for a new version, and how long a new version has to reach running
  defp timing(%{deploy_schedule_interval_ms: every, deploy_rollback_timeout_ms: within})
       when is_integer(every) and every > 0 and is_integer(within) and within > 0,
       do:
         "DeployEx checks for a new version every #{View.duration(every)}. A new version that is not " <>
           "running within #{View.duration(within)} is ghosted, and the instance goes back to the version before it."

  defp timing(_app), do: nil

  defp every(0), do: "its instances"
  defp every(1), do: "the instance"
  defp every(2), do: "both instances"
  defp every(count), do: "all #{count} instances"

  defp instances(1), do: "1 instance"
  defp instances(count), do: "#{count} instances"

  defp suffix(sname), do: sname |> String.split("-") |> List.last()

  defp retention do
    case Application.get_env(:foundation, :releases_retention) do
      value when is_integer(value) -> max(value, 2)
      _ -> 2
    end
  end
end
