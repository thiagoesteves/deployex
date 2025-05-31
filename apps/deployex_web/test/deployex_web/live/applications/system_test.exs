defmodule DeployexWeb.Applications.SystemTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias DeployexWeb.Fixture.Status, as: FixtureStatus

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

    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)
    |> expect(:subscribe, fn ->
      send(test_pid_process, {:liveview_pid, self()})
      :ok
    end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, liveview, _html} = live(conn, ~p"/applications")

    assert_receive {:liveview_pid, liveview_pid}, 1_000

    send(
      liveview_pid,
      {:update_system_info,
       %Host.Memory{
         host: host,
         description: description,
         memory_free: 17_201_512_448,
         memory_total: 68_719_476_736,
         cpu: 211.4,
         cpus: 5
       }}
    )

    html = render(liveview)

    assert html =~ host
    assert html =~ description
    assert html =~ total_memory
  end
end
