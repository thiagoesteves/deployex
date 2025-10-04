defmodule DeployexWeb.HealthController do
  use DeployexWeb, :controller

  def health(conn, _params) do
    json(conn, %{status: "ok", timestamp: DateTime.utc_now()})
  end
end
