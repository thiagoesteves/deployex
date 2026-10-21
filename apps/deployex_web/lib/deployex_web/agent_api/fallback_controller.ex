defmodule DeployexWeb.AgentApi.FallbackController do
  use DeployexWeb, :controller

  def call(conn, {:error, :not_found}), do: error(conn, 404, :"404")

  # The status server did not answer, for example while DeployEx starts
  def call(conn, {:error, :unavailable}), do: error(conn, 503, :"503")

  def call(conn, {:error, {:invalid, detail}}) do
    conn
    |> put_status(422)
    |> json(%{errors: %{detail: detail}})
  end

  defp error(conn, status, template) do
    conn
    |> put_status(status)
    |> put_view(json: DeployexWeb.ErrorJSON)
    |> render(template)
  end
end
