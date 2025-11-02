defmodule DeployexWeb.Components.Dashboard do
  @moduledoc false
  use DeployexWeb, :html

  use Phoenix.Component
  alias DeployexWeb.Components.ApplicationDashboard
  alias DeployexWeb.Components.DeployexCard

  attr :applications, :list, required: true

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
        restart_path={~p"/applications/deployex/deployex/restart"}
      />

      <div>
        <ApplicationDashboard.content monitored_apps={@monitored_apps} />
      </div>
    </div>
    """
  end
end
