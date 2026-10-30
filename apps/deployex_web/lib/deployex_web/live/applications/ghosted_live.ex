defmodule DeployexWeb.GhostedLive do
  @moduledoc """
  The ghosted versions of one application. Clear asks first, then clears at once, so a page that closes
  right after the click does not lose it.
  """
  use DeployexWeb, :live_view

  alias Deployer.Status
  alias DeployexWeb.ApplicationsLive.Board
  alias DeployexWeb.ApplicationsLive.View
  alias DeployexWeb.HostTime
  alias DeployexWeb.UI.Icons

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :shown, assigns.ghosted)

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
        <div class="flex flex-col gap-2.5">
          <Board.app_head
            name={@name}
            language={@language}
            logo={@logo}
            subtitle={"Ghosted versions · #{@summary}"}
          >
            <span :if={@shown != []} class="dx-chip dx-s-ghost">
              <Icons.icon name="ghost" class="dx-gh" />
              {if length(@shown) == 1,
                do: "1 ghosted version",
                else: "#{length(@shown)} ghosted versions"}
            </span>
          </Board.app_head>
          <p class="dx-muted max-w-[720px] text-[0.875rem]">
            A ghosted version failed on this host, and DeployEx does not deploy it here again. Clear it when the
            release is fixed, or to try it once more.
          </p>
        </div>

        <section class="dx-card overflow-hidden" aria-label={"Ghosted versions of #{@name}"}>
          <div class="flex flex-wrap items-center justify-between gap-2.5 px-5 py-3">
            <h2 class="text-base font-bold">Ghosted</h2>
            <button
              :if={@shown != []}
              id="ghosted-clear-all"
              type="button"
              class="dx-btn dx-btn-er"
              phx-click="clear-all"
            >
              Clear all
            </button>
          </div>
          <div :if={@asking} class="dx-ask" role="group" aria-label="Confirm the clear">
            <span class="flex-[1_1_320px]">
              <b>
                {if @asking == :all,
                  do: "Clear all #{length(@shown)} ghosted versions?",
                  else: "Clear ghosted #{@asking}?"}
              </b>
              This host can deploy {if @asking == :all, do: "them", else: "it"} again on its next check.
            </span>
            <button
              id="ghosted-clear-confirm"
              type="button"
              class="dx-btn dx-btn-danger"
              phx-click="confirm-clear"
            >
              {if @asking == :all, do: "Clear all", else: "Clear #{@asking}"}
            </button>
            <button type="button" class="dx-btn" phx-click="cancel-clear">Cancel</button>
          </div>
          <div :if={@shown != []} class="overflow-x-auto">
            <div class="min-w-[700px]">
              <div class="dx-grow min-h-[38px]">
                <div class="dx-lbl">Version</div>
                <div class="dx-lbl">Instance</div>
                <div class="dx-lbl">Ghosted, host time {HostTime.zone()}</div>
                <div></div>
              </div>
              <div :for={version <- @shown} id={"ghosted-#{version.version}"} class="dx-grow">
                <div class="flex items-center gap-2 text-(--dx-error-text)">
                  <Icons.icon name="ghost" class="dx-gh" />
                  <b class="dx-mono text-sm text-(--dx-base-content)">{version.version}</b>
                </div>
                <div class="dx-mono text-[0.8125rem]">{version.sname}</div>
                <div class="flex items-baseline gap-2.5">
                  <span class="dx-mono text-[0.8125rem]">{at(version)}</span>
                  <span class="dx-muted text-[0.8125rem]">{View.age(datetime(version), @now)}</span>
                </div>
                <div class="flex justify-end">
                  <button
                    id={"ghosted-clear-#{version.version}"}
                    type="button"
                    class="dx-btn"
                    aria-label={"Clear ghosted #{version.version}"}
                    phx-click="clear"
                    phx-value-version={version.version}
                  >
                    Clear
                  </button>
                </div>
              </div>
            </div>
          </div>
          <p
            :if={@shown == []}
            class="dx-muted border-t border-(--dx-base-300) px-5 py-[18px] text-[0.875rem]"
          >
            No ghosted versions. Any version can deploy on this host.
          </p>
          <div :if={@cleared != []} class="dx-done" role="status">
            <span class="flex-[1_1_320px]">
              {if length(@cleared) == 1,
                do: "Cleared #{hd(@cleared)}. It can deploy on this host again.",
                else:
                  "Cleared #{length(@cleared)} ghosted versions. They can deploy on this host again."}
            </span>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"name" => name}, _session, socket) do
    if connected?(socket), do: Status.subscribe_ghosted_versions(name)

    {:ok,
     socket
     |> assign(name: name, asking: nil, cleared: [], current_path: "/applications")
     |> assign(:page_title, "#{name} ghosted versions")
     |> load()}
  end

  @impl true
  def handle_event("clear", %{"version" => version}, socket),
    do: {:noreply, assign(socket, asking: version, cleared: [])}

  def handle_event("clear-all", _params, socket),
    do: {:noreply, assign(socket, asking: :all, cleared: [])}

  def handle_event("cancel-clear", _params, socket), do: {:noreply, assign(socket, :asking, nil)}

  def handle_event("confirm-clear", _params, %{assigns: %{asking: asking, name: name}} = socket) do
    versions =
      if asking == :all, do: Enum.map(socket.assigns.ghosted, & &1.version), else: [asking]

    Enum.each(versions, &Status.remove_ghosted_version(name, &1))
    {:noreply, socket |> assign(asking: nil, cleared: versions) |> load()}
  end

  @impl true
  def handle_info({:ghosted_versions_updated, _node, _name, _list}, socket),
    do: {:noreply, load(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load(%{assigns: %{name: name}} = socket) do
    {known, language, children, replicas} =
      case connected?(socket) && Status.monitoring() do
        {:ok, statuses} ->
          case Enum.find(statuses, &(&1.name == name)) do
            %{language: language, children: children, replicas: replicas} ->
              {true, language, children, replicas}

            nil ->
              {false, "elixir", [], 0}
          end

        _ ->
          {false, "elixir", [], 0}
      end

    socket
    |> assign(:language, language)
    |> assign(:logo, Enum.find_value(children, & &1.logo))
    |> assign(:summary, summary(children, replicas))
    # An app this host does not run, like a mistyped name in the URL, has no catalog to read
    |> assign(:ghosted, if(known, do: Status.ghosted_version_list(name), else: []))
    |> assign(:now, DateTime.utc_now())
  end

  defp summary(children, replicas) do
    total = max(replicas, length(children))
    running = Enum.count(children, &View.running?/1)
    count = if total == 1, do: "1 instance", else: "#{total} instances"
    "#{count} · #{running}/#{total} running"
  end

  defp datetime(%{inserted_at: %NaiveDateTime{} = at}), do: DateTime.from_naive!(at, "Etc/UTC")
  defp datetime(_version), do: nil

  defp at(version) do
    case datetime(version) do
      nil -> "--"
      at -> HostTime.format(at, "%Y-%m-%d %H:%M")
    end
  end
end
