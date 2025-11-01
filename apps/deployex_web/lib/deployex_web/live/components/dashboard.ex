defmodule DeployexWeb.Components.Dashboard do
  @moduledoc false
  use DeployexWeb, :html

  use Phoenix.Component
  alias DeployexWeb.Components.ApplicationDashboard
  alias DeployexWeb.Components.DeployexCard
  alias DeployexWeb.Helper

  attr :applications, :list, required: true

  attr :monitoring, :list,
    default: [
      {:memory,
       %{enable_restart: true, warning_threshold_percent: 80, restart_threshold_percent: 90}},
      {:atom,
       %{enable_restart: true, warning_threshold_percent: 50, restart_threshold_percent: 90}},
      {:process,
       %{enable_restart: true, warning_threshold_percent: 50, restart_threshold_percent: 90}}
    ]

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
      <DeployexCard.content
        :if={@deployex}
        deployex={@deployex}
        monitoring={@monitoring}
        restart_path={~p"/applications/deployex/deployex/restart"}
      />

      <div
        :if={@deployex != nil and @deployex.config}
        id={Helper.normalize_id("button-deployex-config")}
      >
        <ApplicationDashboard.content
          config={@deployex.config}
          monitored_apps={@monitored_apps}
          monitoring={@monitoring}
        />
      </div>
    </div>
    """
  end
end
