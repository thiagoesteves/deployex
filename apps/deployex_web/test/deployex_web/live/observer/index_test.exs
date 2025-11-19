defmodule DeployexWeb.Terminal.ObserverTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  setup [
    :set_mox_global,
    :log_in_default_user
  ]

  test "GET /embedded-observer", %{conn: conn} do
    {:ok, _index_live, html} = live(conn, ~p"/embedded-observer")

    assert html =~ "Observer Web"
  end

  test "GET /embedded-observer system info", %{conn: conn} do
    host = "macOS"
    description = "15.1.1"
    total_memory = "64.00"

    {:ok, liveview, _html} = live(conn, ~p"/embedded-observer")

    Phoenix.PubSub.broadcast(
      Host.PubSub,
      "deployex::system_info_updated",
      {:update_system_info,
       %Host.Info{
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
