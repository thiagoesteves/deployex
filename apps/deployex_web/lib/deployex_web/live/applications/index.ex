defmodule DeployexWeb.ApplicationsLive do
  use DeployexWeb, :live_view

  alias Deployer.Deployex
  alias Deployer.Engine
  alias Deployer.Monitor
  alias Deployer.Status
  alias DeployexWeb.ApplicationsLive.Board
  alias DeployexWeb.ApplicationsLive.Ghosted
  alias DeployexWeb.ApplicationsLive.Versions
  alias DeployexWeb.ApplicationsLive.View
  alias DeployexWeb.Components.ConfigChangesModal
  alias DeployexWeb.Components.Confirm
  alias Sentinel.Config.Watcher

  @deployex_terminate_delay 300
  # A cleared ghosted version is cleared for real when its Undo window ends
  @undo_window :timer.seconds(10)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_path={@current_path}
      current_user={@current_user}
      host_info={@host_info}
      recent_events={@recent_events}
    >
      <div class="mx-auto flex max-w-[1140px] flex-col gap-5 px-8 pt-7 pb-14 max-md:px-4">
        <Board.page_head host_name={@host_name} attention={View.attention(@apps)} />
        <Board.host_card
          host={View.host(@deployex, @host_info)}
          pending_changes={pending_count(@yaml_config)}
          asking={@ask == :deployex}
        />
        <Board.app_table
          apps={@apps}
          open={@open}
          limits_open={@limits_open}
          ask={@ask}
          sent={@sent}
          cleared={Map.new(@cleared, fn {name, %{version: version}} -> {name, version} end)}
        />
      </div>
    </Layouts.app>

    <.modal
      :if={@live_action in [:versions]}
      id="app-versions-modal"
      show
      on_cancel={JS.patch(~p"/applications")}
    >
      <.live_component
        module={Versions}
        id={"version-#{@selected_name}-#{@selected_sname}"}
        name={@selected_name}
        sname={@selected_sname}
        title={@page_title}
        action={@live_action}
        patch={~p"/applications"}
      />
    </.modal>

    <.modal
      :if={@live_action in [:ghosted]}
      id="app-ghosted-modal"
      show
      on_cancel={JS.patch(~p"/applications")}
    >
      <.live_component
        module={Ghosted}
        id={"ghosted-#{@selected_name}"}
        name={@selected_name}
        title={@page_title}
        patch={~p"/applications"}
      />
    </.modal>

    <%= if @yaml_config.show_modal do %>
      <ConfigChangesModal.modal
        id="yaml"
        pending_changes={@yaml_config.pending_config_changes}
        on_cancel="confirm-close-modal"
        on_apply="config-changes-apply"
      />
    <% end %>

    <%= if @ghosted_confirmation do %>
      <Confirm.content id="app-ghosted-confirm-modal">
        <:header :if={@ghosted_confirmation.version}>Remove Ghosted Version</:header>
        <:header :if={is_nil(@ghosted_confirmation.version)}>Clear Ghosted Versions</:header>

        <div class="space-y-6">
          <div class="bg-base-200 border border-base-300 rounded-lg p-4">
            <p class="text-sm text-base-content/60">Application</p>
            <p class="font-semibold text-base-content">{@ghosted_confirmation.name}</p>
          </div>

          <p :if={@ghosted_confirmation.version} class="text-base-content/90 leading-relaxed">
            Remove version
            <span class="inline-flex items-center px-3 py-1 rounded-full text-sm font-mono font-semibold bg-warning/20 text-warning-content">
              {@ghosted_confirmation.version}
            </span>
            from the ghosted list?
          </p>

          <p :if={is_nil(@ghosted_confirmation.version)} class="text-base-content/90 leading-relaxed">
            Remove all <span class="font-semibold">{@ghosted_confirmation.count}</span>
            ghosted versions?
          </p>

          <div class="text-base-content/60 leading-relaxed">
            A ghosted version is skipped by every deployment. The engine offers it again on its
            next check, which deploys it if it is still the version to deploy.
          </div>
        </div>

        <:footer>
          <Confirm.cancel_button id="ghosted">Cancel</Confirm.cancel_button>
          <Confirm.danger_button
            :if={is_nil(@ghosted_confirmation.version)}
            event="ghosted-confirm"
            id="ghosted"
            value={@ghosted_confirmation.name}
          >
            Yes, Clear All
          </Confirm.danger_button>
          <Confirm.confirm_button
            :if={@ghosted_confirmation.version}
            event="ghosted-confirm"
            id="ghosted"
            value={@ghosted_confirmation.version}
          >
            Remove Version
          </Confirm.confirm_button>
        </:footer>
      </Confirm.content>
    <% end %>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Status.subscribe()
      Watcher.subscribe_new_config()
    end

    statuses =
      case connected?(socket) && Status.monitoring() do
        {:ok, statuses} -> statuses
        _ -> []
      end

    yaml_config =
      case connected?(socket) && Watcher.get_pending_changes() do
        {:ok, changes} -> %{default_yaml_config() | pending_config_changes: changes}
        _ -> default_yaml_config()
      end

    {:ok,
     socket
     |> assign(:node, Node.self())
     |> assign(:host_name, host_name())
     |> assign_statuses(statuses)
     |> assign(:open, MapSet.new())
     |> assign(:limits_open, %{})
     |> assign(:ask, nil)
     |> assign(:sent, MapSet.new())
     |> assign(:cleared, %{})
     |> assign(:selected_name, nil)
     |> assign(:selected_sname, nil)
     |> assign(:ghosted_confirmation, nil)
     |> assign(:yaml_config, yaml_config)
     |> assign(:current_path, "/applications")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, socket |> apply_action(socket.assigns.live_action, params) |> focus(params)}
  end

  defp apply_action(socket, :index, _params), do: assign(socket, :page_title, "Applications")

  defp apply_action(socket, :versions, %{"sname" => sname, "name" => name}) do
    socket
    |> assign(:page_title, "#{sname} version history")
    |> assign(:selected_name, name)
    |> assign(:selected_sname, sname)
  end

  defp apply_action(socket, :versions, %{"name" => name}) do
    socket
    |> assign(:page_title, "#{name} version history")
    |> assign(:selected_name, name)
    |> assign(:selected_sname, nil)
  end

  defp apply_action(socket, :ghosted, %{"name" => name}) do
    socket
    |> assign(:page_title, "#{name} ghosted versions")
    |> assign(:selected_name, name)
    |> assign(:selected_sname, nil)
  end

  # A search result opens its app, and its instance's limits
  defp focus(socket, %{"app" => name} = params) do
    socket
    |> update(:open, &MapSet.put(&1, name))
    |> update(:limits_open, fn limits ->
      case params["instance"] do
        nil -> limits
        sname -> Map.put(limits, sname, true)
      end
    end)
  end

  defp focus(socket, %{"review" => "config"}), do: open_config_changes(socket)
  defp focus(socket, _params), do: socket

  # The list the component is showing came from a read of its own. Nothing in the assigns it
  # is given changed, so it has to be told to read again, otherwise it keeps the stale list
  defp refresh_ghosted_list(name) do
    send_update(Ghosted, id: "ghosted-#{name}", name: name)
  end

  @impl true
  def handle_info(
        {:monitoring_app_updated, source_node, statuses},
        %{assigns: %{node: node}} = socket
      )
      when source_node == node do
    {:noreply, assign_statuses(socket, statuses)}
  end

  def handle_info({:monitoring_app_updated, _source_node, _statuses}, socket),
    do: {:noreply, socket}

  def handle_info({:commit_clear, name}, %{assigns: %{cleared: cleared}} = socket) do
    case Map.pop(cleared, name) do
      {%{version: version}, cleared} ->
        {:ok, _list} = Status.remove_ghosted_version(name, version)
        {:noreply, assign(socket, :cleared, cleared)}

      {nil, _cleared} ->
        {:noreply, socket}
    end
  end

  def handle_info(
        {:watcher_config_new, source_node, pending_changes},
        %{assigns: %{node: node, yaml_config: yaml_config}} = socket
      )
      when source_node == node do
    {:noreply,
     assign(socket, :yaml_config, %{yaml_config | pending_config_changes: pending_changes})}
  end

  def handle_info({:watcher_config_new, _source_node, _pending_changes}, socket) do
    # NOTE: Ignore changes from other nodes
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle-app", %{"name" => name}, socket) do
    {:noreply,
     update(socket, :open, fn open ->
       if MapSet.member?(open, name), do: MapSet.delete(open, name), else: MapSet.put(open, name)
     end)}
  end

  def handle_event("toggle-limits", %{"sname" => sname, "open" => open}, socket) do
    {:noreply, update(socket, :limits_open, &Map.put(&1, sname, open == "true"))}
  end

  def handle_event("ask", %{"target" => "deployex"}, socket),
    do: {:noreply, assign(socket, :ask, :deployex)}

  def handle_event("ask", %{"target" => "app:" <> name}, socket),
    do: {:noreply, assign(socket, :ask, {:app, name})}

  def handle_event("ask", %{"target" => sname}, socket),
    do: {:noreply, assign(socket, :ask, sname)}

  def handle_event("cancel-ask", _params, socket), do: {:noreply, assign(socket, :ask, nil)}

  def handle_event("restart-instance", %{"sname" => sname}, socket) do
    Monitor.restart(sname)
    {:noreply, socket |> assign(:ask, nil) |> update(:sent, &MapSet.put(&1, sname))}
  end

  def handle_event("restart-app", %{"name" => name}, socket) do
    Engine.restart_deployments(name)

    {:noreply,
     socket
     |> assign(:ask, nil)
     |> put_flash(:info, "Restarting every instance of #{name}")}
  end

  def handle_event("restart-deployex", _params, socket) do
    # NOTE: Say goodbye to your monitored applications
    Deployex.force_terminate(@deployex_terminate_delay)
    {:noreply, assign(socket, :ask, nil)}
  end

  def handle_event("clear-ghosted", %{"name" => name, "version" => version}, socket) do
    timer = Process.send_after(self(), {:commit_clear, name}, @undo_window)
    {:noreply, update(socket, :cleared, &Map.put(&1, name, %{version: version, timer: timer}))}
  end

  def handle_event("undo-clear", %{"name" => name}, %{assigns: %{cleared: cleared}} = socket) do
    case Map.pop(cleared, name) do
      {%{timer: timer}, cleared} ->
        Process.cancel_timer(timer)
        {:noreply, assign(socket, :cleared, cleared)}

      {nil, _cleared} ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "ghosted-remove-request",
        %{"version" => version},
        %{assigns: %{selected_name: name}} = socket
      ) do
    {:noreply, assign(socket, :ghosted_confirmation, %{name: name, version: version, count: 1})}
  end

  def handle_event("ghosted-clear-request", _params, %{assigns: %{selected_name: name}} = socket) do
    count = name |> Status.ghosted_version_list() |> length()

    {:noreply, assign(socket, :ghosted_confirmation, %{name: name, version: nil, count: count})}
  end

  def handle_event(
        "ghosted-confirm",
        _params,
        %{assigns: %{ghosted_confirmation: %{name: name, version: nil}}} = socket
      ) do
    {:ok, _list} = Status.clear_ghosted_versions(name)

    refresh_ghosted_list(name)

    {:noreply,
     socket
     |> assign(:ghosted_confirmation, nil)
     |> put_flash(:info, "All ghosted versions removed for #{name}")}
  end

  def handle_event(
        "ghosted-confirm",
        _params,
        %{assigns: %{ghosted_confirmation: %{name: name, version: version}}} = socket
      ) do
    {:ok, _list} = Status.remove_ghosted_version(name, version)

    refresh_ghosted_list(name)

    {:noreply,
     socket
     |> assign(:ghosted_confirmation, nil)
     |> put_flash(:info, "Version #{version} removed from the ghosted list")}
  end

  def handle_event(
        "show-config-changes",
        _any,
        %{assigns: %{yaml_config: yaml_config}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:yaml_config, %{yaml_config | show_modal: true})
     |> push_patch(to: ~p"/applications")}
  end

  def handle_event("config-changes-apply", _any, socket) do
    Watcher.apply_changes()

    {:noreply,
     socket
     |> assign(:yaml_config, default_yaml_config())
     |> put_flash(:info, "New config changes applied with success!")
     |> push_patch(to: ~p"/applications")}
  end

  # Cancelling this confirmation goes back to the list it was opened from, not out of it
  def handle_event(
        "confirm-close-modal",
        _,
        %{assigns: %{ghosted_confirmation: %{name: name}}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:ghosted_confirmation, nil)
     |> push_patch(to: ~p"/applications/#{name}/ghosted")}
  end

  def handle_event("confirm-close-modal", _, %{assigns: %{yaml_config: yaml_config}} = socket) do
    {:noreply,
     socket
     |> assign(:yaml_config, %{yaml_config | show_modal: false})
     |> push_patch(to: ~p"/applications")}
  end

  # The clear is held back for its Undo window, so the row shows it gone at once
  defp assign_statuses(%{assigns: assigns} = socket, statuses) do
    cleared = Map.get(assigns, :cleared, %{})

    apps =
      statuses
      |> View.apps()
      |> Enum.map(fn app ->
        if (Map.has_key?(cleared, app.name) and app.alert) && app.alert.kind == :ghosted,
          do: %{app | alert: nil},
          else: app
      end)

    socket
    |> assign(:monitoring_apps_data, statuses)
    |> assign(:deployex, Enum.find(statuses, &(&1.name == "deployex")))
    |> assign(:apps, apps)
  end

  defp open_config_changes(%{assigns: %{yaml_config: yaml_config}} = socket),
    do:
      assign(socket, :yaml_config, %{
        yaml_config
        | show_modal: yaml_config.pending_config_changes != nil
      })

  defp pending_count(%{pending_config_changes: %{changes_count: count}}), do: count
  defp pending_count(_yaml_config), do: 0

  defp host_name do
    {:ok, name} = :inet.gethostname()
    to_string(name)
  end

  defp default_yaml_config do
    %{
      show_modal: false,
      pending_config_changes: nil
    }
  end
end
