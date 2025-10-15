defmodule DeployexWeb.Logger do
  @moduledoc """
  Custom router logger that disables or enables logs based on route.
  """

  alias Plug.Conn

  @doc """
  Filters logging based on route path.
  """
  @spec log(conn :: Conn.t()) :: Logger.level() | false
  def log(%Conn{path_info: ["health"]}) do
    if Application.get_env(:foundation, :healthcheck_logging) do
      :info
    else
      false
    end
  end

  def log(%Conn{}), do: :info
end
