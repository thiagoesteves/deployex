defmodule DeployexWeb.GhostedLive do
  @moduledoc """
  The ghosted versions of one application. A cleared version leaves the list at once, and is cleared
  for real when its Undo window ends, so this host does not deploy it before Undo.
  """
  use DeployexWeb, :live_view

  alias Deployer.Status
  alias DeployexWeb.ApplicationsLive.Board
  alias DeployexWeb.ApplicationsLive.View
  alias DeployexWeb.HostTime
  alias DeployexWeb.UI.Icons

  @undo_window :timer.seconds(10)

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, :shown, Enum.reject(assigns.ghosted, &(&1.version in assigns.cleared)))

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
            <button id="ghosted-undo" type="button" class="dx-btn" phx-click="undo">Undo</button>
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
     |> assign(name: name, cleared: [], timer: nil, current_path: "/applications")
     |> assign(:page_title, "#{name} ghosted versions")
     |> load()}
  end

  @impl true
  def handle_event("clear", %{"version" => version}, socket),
    do: {:noreply, clear(socket, [version])}

  def handle_event("clear-all", _params, %{assigns: %{ghosted: ghosted}} = socket),
    do: {:noreply, clear(socket, Enum.map(ghosted, & &1.version))}

  def handle_event("undo", _params, %{assigns: %{timer: timer}} = socket) do
    if timer, do: Process.cancel_timer(timer)
    {:noreply, assign(socket, cleared: [], timer: nil)}
  end

  @impl true
  def handle_info(:commit_clear, %{assigns: %{name: name, cleared: cleared}} = socket) do
    Enum.each(cleared, &Status.remove_ghosted_version(name, &1))
    {:noreply, socket |> assign(cleared: [], timer: nil) |> load()}
  end

  def handle_info({:ghosted_versions_updated, _node, _name, _list}, socket),
    do: {:noreply, load(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  # A new clear joins the open Undo window, and the window starts again
  defp clear(%{assigns: %{cleared: cleared, timer: timer}} = socket, versions) do
    if timer, do: Process.cancel_timer(timer)

    socket
    |> assign(:cleared, Enum.uniq(cleared ++ versions))
    |> assign(:timer, Process.send_after(self(), :commit_clear, @undo_window))
  end

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
    running = Enum.count(children, &(&1.status == :running))
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
