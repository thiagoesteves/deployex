defmodule DeployexWeb.ApplicationsLive do
  use DeployexWeb, :live_view

  alias Deployer.Deployex
  alias Deployer.Engine
  alias Deployer.Monitor
  alias Deployer.Status
  alias DeployexWeb.ApplicationsLive.Board
  alias DeployexWeb.ApplicationsLive.Filter
  alias DeployexWeb.ApplicationsLive.View
  alias DeployexWeb.Components.ConfigChangesModal
  alias Sentinel.Config.Watcher

  @deployex_terminate_delay 300
  # How long a restart button says Restart sent
  @sent_window :timer.seconds(4)

  @impl true
  def render(assigns) do
    shown = Filter.select(assigns.apps, assigns.tags)

    # The apps that need attention come worst first
    shown =
      if {"status", "attention"} in assigns.tags,
        do: Enum.sort_by(shown, &{-&1.severity, &1.name}),
        else: shown

    assigns =
      assign(assigns,
        attention: View.attention(assigns.apps),
        shown: shown,
        hidden: length(assigns.apps) - length(shown)
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      current_path={@current_path}
      current_user={@current_user}
      host_info={@host_info}
      recent_events={@recent_events}
      search_tags={@tags}
      socket={@socket}
    >
      <div class="mx-auto flex max-w-[1140px] flex-col gap-5 px-8 pt-7 pb-14 max-md:px-4">
        <Board.page_head
          host_name={@host_name}
          attention={@attention}
          only_attention={{"status", "attention"} in @tags}
        />
        <Board.host_card
          host={View.host(@deployex, @host_info)}
          pending_changes={pending_count(@yaml_config)}
          asking={@ask == :deployex}
        />
        <Board.app_table
          apps={@shown}
          total={length(@apps)}
          filtered={@tags != []}
          open={@open}
          limits_open={@limits_open}
          ask={@ask}
          sent={@sent}
          cleared={@cleared}
        />
      </div>
    </Layouts.app>

    <%= if @yaml_config.show_modal do %>
      <ConfigChangesModal.modal
        id="yaml"
        pending_changes={@yaml_config.pending_config_changes}
        on_cancel="confirm-close-modal"
        on_apply="config-changes-apply"
      />
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
     |> assign(:tags, [])
     |> assign(:ask, nil)
     |> assign(:sent, MapSet.new())
     |> assign(:cleared, %{})
     |> assign(:yaml_config, yaml_config)
     |> assign(:current_path, "/applications")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> apply_action(socket.assigns.live_action, params)
     |> tags(Filter.parse(params))
     |> focus(params)}
  end

  # New tags start from collapsed apps, so Clear does not leave open what a tag opened
  defp tags(%{assigns: %{tags: tags}} = socket, tags), do: socket

  defp tags(socket, tags),
    do: assign(socket, tags: tags, open: MapSet.new(), limits_open: %{})

  defp apply_action(socket, :index, _params), do: assign(socket, :page_title, "Applications")

  defp focus(socket, %{"review" => "config"}), do: open_config_changes(socket)

  # An app tag opens its app, and an instance tag also its details
  defp focus(%{assigns: %{tags: tags}} = socket, _params) do
    Enum.reduce(tags, socket, fn
      {"app", name}, socket ->
        update(socket, :open, &MapSet.put(&1, name))

      {"instance", sname}, socket ->
        socket
        |> update(:open, &MapSet.put(&1, String.replace(sname, ~r/-[^-]+$/, "")))
        |> update(:limits_open, &Map.put(&1, sname, true))

      _tag, socket ->
        socket
    end)
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

  def handle_info({:clear_sent, sname}, socket),
    do: {:noreply, update(socket, :sent, &MapSet.delete(&1, sname))}

  def handle_info({:clear_shown, name}, socket),
    do: {:noreply, update(socket, :cleared, &Map.delete(&1, name))}

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
  def handle_event("toggle-attention", _params, %{assigns: %{tags: tags}} = socket),
    do:
      {:noreply,
       push_patch(socket, to: Filter.path(Filter.toggle(tags, {"status", "attention"})))}

  def handle_event("show-instance", %{"name" => name, "sname" => sname}, socket) do
    {:noreply,
     socket
     |> update(:open, &MapSet.put(&1, name))
     |> update(:limits_open, &Map.put(&1, sname, true))}
  end

  def handle_event("toggle-app", %{"name" => name, "open" => "true"}, socket),
    do: {:noreply, update(socket, :open, &MapSet.put(&1, name))}

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

  def handle_event("ask", %{"target" => "ghosted:" <> name}, socket),
    do: {:noreply, assign(socket, :ask, {:ghosted, name})}

  def handle_event("ask", %{"target" => sname}, socket),
    do: {:noreply, assign(socket, :ask, sname)}

  def handle_event("cancel-ask", _params, socket), do: {:noreply, assign(socket, :ask, nil)}

  def handle_event("restart-instance", %{"sname" => sname}, socket) do
    Monitor.restart(sname)
    Process.send_after(self(), {:clear_sent, sname}, @sent_window)
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

  # The clear happens at once. The row says it was cleared until the next status shows it gone
  def handle_event("clear-ghosted", %{"name" => name, "version" => version}, socket) do
    {:ok, _list} = Status.remove_ghosted_version(name, version)
    Process.send_after(self(), {:clear_shown, name}, @sent_window)

    {:noreply, socket |> assign(:ask, nil) |> update(:cleared, &Map.put(&1, name, version))}
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

  def handle_event("confirm-close-modal", _, %{assigns: %{yaml_config: yaml_config}} = socket) do
    {:noreply,
     socket
     |> assign(:yaml_config, %{yaml_config | show_modal: false})
     |> push_patch(to: ~p"/applications")}
  end

  # A version cleared a moment ago shows as cleared, not ghosted, until the status catches up
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
