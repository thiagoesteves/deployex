defmodule DeployexWeb.UiSettings do
  @moduledoc false
  use DeployexWeb, :verified_routes

  import Plug.Conn

  alias DeployexWeb.Cache

  @doc """
  Retrieve its current UI settings
  """
  def fetch_current_ui_settings(conn, _opts) do
    ui_settings = Cache.UiSettings.get()

    conn
    |> put_session(:ui_settings, ui_settings)
    |> assign(:ui_settings, ui_settings)
  end

  @doc """
  Save UI settings to cache
  """
  def set(ui_settings) do
    Cache.UiSettings.set(ui_settings)
  end

  def on_mount(:mount_ui_settings, _params, session, socket) do
    {:cont, Phoenix.Component.assign_new(socket, :ui_settings, fn -> session["ui_settings"] end)}
  end
end
