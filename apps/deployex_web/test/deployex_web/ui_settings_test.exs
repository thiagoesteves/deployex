defmodule DeployexWeb.UiSettingsTest do
  use DeployexWeb.ConnCase, async: true

  import DeployexWeb.AccountsFixtures

  alias DeployexWeb.Cache
  alias DeployexWeb.UiSettings
  alias Phoenix.LiveView

  setup %{conn: conn} do
    ui_settings = %Cache.UiSettings{nav_menu_collapsed: false}
    Cache.UiSettings.set(ui_settings)

    conn =
      conn
      |> Map.replace!(:secret_key_base, DeployexWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{user: user_fixture(), conn: conn, ui_settings: ui_settings}
  end

  describe "fetch_current_ui_settings/2" do
    test "Retrieve ui settings from session", %{conn: conn, ui_settings: ui_settings} do
      conn = conn |> UiSettings.fetch_current_ui_settings([])
      assert conn.assigns.ui_settings == ui_settings
    end
  end

  describe "on_mount: mount_ui_settings" do
    test "assigns ui settings to socket", %{conn: conn, ui_settings: ui_settings} do
      session = conn |> put_session(:ui_settings, ui_settings) |> get_session()

      {:cont, updated_socket} =
        UiSettings.on_mount(:mount_ui_settings, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.ui_settings == ui_settings
    end
  end
end
