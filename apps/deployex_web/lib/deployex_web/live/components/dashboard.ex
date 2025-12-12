defmodule DeployexWeb.Components.Dashboard do
  @moduledoc false
  use DeployexWeb, :html

  use Phoenix.Component
  alias DeployexWeb.Components.ApplicationDashboard
  alias DeployexWeb.Components.DeployexCard

  attr :applications, :list, required: true
  attr :metrics, :map, required: true
  attr :pending_config_changes, :map, default: nil
  attr :active_tab, :string, required: true

  def content(assigns) do
    {deployex, monitored_apps} =
      case Enum.split_with(assigns.applications, fn app -> app.name == "deployex" end) do
        {[deployex], monitored_apps} ->
          {deployex, monitored_apps}

        _ ->
          {nil, []}
      end

    assigns =
      assigns
      |> assign(:restart_path, ~p"/applications/deployex/deployex/restart")
      |> assign(:deployex, deployex)
      |> assign(:monitored_apps, monitored_apps)

    ~H"""
    <div>
      <!-- Tab Navigation -->
      <div class="tabs tabs-lift bg-base-200 p-1 mb-6 ">
        <a
          id="tab-deployex"
          phx-click="swicth-app-tab"
          phx-value-tab="deployex"
          class={[
            "tab tab-lg",
            if(@active_tab == "deployex", do: "tab-active", else: "")
          ]}
        >
          <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"
            >
            </path>
          </svg>
          Deployex
          <div :if={@pending_config_changes} class="badge badge-warning badge-sm ml-2">
            {@pending_config_changes.changes_count}
          </div>
        </a>
        <div class="tab-content bg-base-100 border-base-300 p-6">
          <DeployexCard.content
            :if={@deployex}
            deployex={@deployex}
            metrics={@metrics}
            pending_config_changes={@pending_config_changes}
            restart_path={~p"/applications/deployex/deployex/restart"}
          />
        </div>

        <%= for monitored_app  <- @monitored_apps do %>
          <a
            id={"tab-application-#{monitored_app.name}"}
            phx-click="swicth-app-tab"
            phx-value-tab={monitored_app.name}
            class={[
              "tab tab-lg",
              if(@active_tab == monitored_app.name, do: "tab-active", else: "")
            ]}
          >
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
              >
              </path>
            </svg>
            {monitored_app.name}
            <%!-- <div class="badge badge-primary badge-sm ml-2">
            {length(@monitored_apps)}
          </div> --%>
          </a>
          <div class="tab-content bg-base-100 border-base-300 p-6">
            <ApplicationDashboard.content monitored_app={monitored_app} metrics={@metrics} />
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
