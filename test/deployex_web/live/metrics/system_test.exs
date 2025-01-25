defmodule DeployexWeb.Metrics.SystemTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  test "GET /metrics with system info", %{conn: conn} do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    test_pid_process = self()
    host = "macOS"
    description = "15.1.1"
    total_memory = "64.00"

    Deployex.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      send(test_pid_process, {:liveview_pid, self()})
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    {:ok, liveview, _html} = live(conn, ~p"/metrics")

    liveview
    |> element("#metrics-multi-select-toggle-options")
    |> render_click()

    liveview
    |> element("#metrics-multi-select-services-#{service}-add-item")
    |> render_click()

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
