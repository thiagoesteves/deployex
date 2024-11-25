defmodule DeployexWeb.Observer.IndexTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox
  import Mock

  alias Deployex.Fixture.Monitoring
  alias Deployex.Fixture.Status, as: FixtureStatus
  alias Deployex.Fixture.Terminal, as: FixtureTerminal

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  test "GET /applications check buttom", %{conn: conn} do
    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:monitored_app_name, fn -> "testapp" end)
    |> stub(:monitored_app_lang, fn -> "elixir" end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live
           |> element("a", "Observer")
           |> render_click()
  end

  test "GET /observer", %{conn: conn} do
    {:ok, _index_live, html} = live(conn, ~p"/observer")

    assert html =~ "Live Observer"
  end

  test "Add Local Service + Kernel App", %{conn: conn} do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    {:ok, index_live, _html} = live(conn, ~p"/observer")

    index_live
    |> element("#observer-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#observer-multi-select-services-#{service}-add-item")
    |> render_click()

    html =
      index_live
      |> element("#observer-multi-select-apps-kernel-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "apps:kernel"
  end

  test "Add Kernel App + Local Service", %{conn: conn} do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    {:ok, index_live, _html} = live(conn, ~p"/observer")

    index_live
    |> element("#observer-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#observer-multi-select-apps-kernel-add-item")
    |> render_click()

    html =
      index_live
      |> element("#observer-multi-select-services-#{service}-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "apps:kernel"
  end
end
