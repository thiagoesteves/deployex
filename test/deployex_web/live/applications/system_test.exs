defmodule DeployexWeb.Applications.SystemTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Deployex.Fixture.Monitoring
  alias Deployex.Fixture.Status, as: FixtureStatus

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  test "GET /applications with system info", %{conn: conn} do
    test_pid_process = self()
    host = "macOS"
    description = "15.1.1"
    total_memory = "64.00"

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn ->
      send(test_pid_process, {:liveview_pid, self()})
      :ok
    end)
    |> stub(:monitored_app_name, fn -> "testapp" end)
    |> stub(:monitored_app_lang, fn -> "elixir" end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    assert_receive {:liveview_pid, liveview_pid}, 1_000

    send(
      liveview_pid,
      {:update_system_info,
       %Deployex.System{
         host: host,
         description: description,
         memory_free: 17_201_512_448,
         memory_total: 68_719_476_736,
         cpu: 211,
         cpus: 5
       }}
    )

    html = render(liveview)

    assert html =~ host
    assert html =~ description
    assert html =~ total_memory
  end
end
