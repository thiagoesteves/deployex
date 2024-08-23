defmodule DeployexWeb.Applications.RestartTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  alias Deployex.Fixture.Monitoring

  test "Click restart Button, but cancel the operation", %{conn: conn} do
    topic = "topic-restart-000"

    Deployex.StatusMock
    |> expect(:state, fn -> {:ok, %{monitoring: Monitoring.list()}} end)
    |> expect(:listener_topic, fn -> topic end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-restart-1") |> render_click() =~
             "Are you sure you want to restart instance 1?"

    assert index_live |> element("#cancel-button-1", "Cancel") |> render_click()

    refute has_element?(index_live, "#cancel-button-1")
  end

  test "Click restart Button, confirm the operation", %{conn: conn} do
    topic = "topic-restart-001"

    Deployex.StatusMock
    |> expect(:state, fn -> {:ok, %{monitoring: Monitoring.list()}} end)
    |> expect(:listener_topic, fn -> topic end)

    Deployex.MonitorMock
    |> expect(:restart, 1, fn 1 -> :ok end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live |> element("#app-restart-1") |> render_click() =~
             "Are you sure you want to restart instance 1?"

    assert index_live |> element("#confirm-button-1", "Confirm") |> render_click()

    refute has_element?(index_live, "#cancel-button-1")
  end
end
