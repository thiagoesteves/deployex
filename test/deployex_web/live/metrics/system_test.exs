defmodule DeployexWeb.Metrics.SystemTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user,
    :node_list
  ]

  test "GET /metrics with system info", %{conn: conn, node_list: node_list} do
    service = String.replace(node_list[0] |> to_string, "@", "-")

    test_pid_process = self()
    host = "macOS"
    description = "15.1.1"
    total_memory = "64.00"

    Deployex.TelemetryMock
    |> expect(:subscribe_for_new_keys, fn -> :ok end)
    |> stub(:node_by_instance, fn instance ->
      if instance == 3, do: send(test_pid_process, {:liveview_pid, self()})
      node_list[instance]
    end)
    |> stub(:get_keys_by_instance, fn _ -> [] end)

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
