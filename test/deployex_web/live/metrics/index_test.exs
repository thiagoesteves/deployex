defmodule DeployexWeb.Metrics.IndexTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Deployex.Fixture.Monitoring
  alias Deployex.Fixture.Status, as: FixtureStatus

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user,
    :node_list
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
           |> element("a", "Live Metrics")
           |> render_click()
  end

  test "GET /metrics", %{conn: conn, node_list: node_list} do
    test_pid_process = self()

    Deployex.TelemetryMock
    |> expect(:subscribe_for_new_keys, fn -> :ok end)
    |> stub(:node_by_instance, fn instance ->
      if instance == 3, do: send(test_pid_process, {:liveview_pid, self()})
      node_list[instance]
    end)
    |> stub(:get_keys_by_instance, fn _ -> [] end)

    {:ok, _index_live, html} = live(conn, ~p"/metrics")

    assert_receive {:liveview_pid, _liveview_pid}, 1_000

    assert html =~ "Live Metrics"
  end
end
