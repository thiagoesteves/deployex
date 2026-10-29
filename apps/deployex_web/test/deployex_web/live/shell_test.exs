defmodule DeployexWeb.ShellTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias DeployexWeb.Fixture.Status, as: FixtureStatus

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  @nav_items [
    {"/applications", "Applications"},
    {"/logs/live", "Live Logs"},
    {"/logs/history", "History Logs"},
    {"/embedded-observer", "Observer Web"},
    {"/terminal", "Host Terminal"},
    {"/hotupgrade", "Hot Upgrade"},
    {"/documentation", "Documentation"}
  ]

  @tag :capture_log
  test "the sidebar has every page as a live link, with the current page active", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/documentation")

    for {path, label} <- @nav_items do
      assert html =~ ~r/<a href="#{path}" data-phx-link="redirect"[^>]*title="#{label}"/
    end

    assert [_active] = Regex.scan(~r/aria-current="page"/, html)
    assert html =~ ~r/href="\/documentation"[^>]*aria-current="page"/
  end

  @tag :capture_log
  test "a sidebar link changes the page with live navigation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/documentation")

    Deployer.HotUpgradeMock
    |> stub(:subscribe_events, fn -> :ok end)

    assert {:ok, _view, html} =
             view
             |> element(~s(a[href="/hotupgrade"]))
             |> render_click()
             |> follow_redirect(conn, ~p"/hotupgrade")

    assert html =~ ~r/href="\/hotupgrade"[^>]*aria-current="page"/
  end

  @tag :capture_log
  test "the top bar has the console name, the theme switch and the account menu", %{
    conn: conn,
    user: user
  } do
    {:ok, _view, html} = live(conn, ~p"/documentation")

    assert html =~ "Agent Console"
    assert html =~ ~s(id="theme-switch")
    assert html =~ ~s(aria-label="Account menu for #{user.username}")
    assert html =~ "Match system theme"
    assert html =~ ~r/href="\/users\/log_out"[^>]*data-method="delete"/
    refute html =~ "Settings"
  end

  @tag :capture_log
  test "the host meters follow this host's readings on any page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/documentation")

    send(
      view.pid,
      {:update_system_info,
       %Host.Info{
         source_node: Node.self(),
         memory_total: 8 * 1_073_741_824,
         memory_free: 2 * 1_073_741_824,
         cpu: 368,
         cpus: 4
       }}
    )

    html = render(view)

    assert html =~
             ~s(aria-label="Host CPU" aria-valuemin="0" aria-valuemax="100" aria-valuenow="92")

    assert html =~ ~s(aria-valuetext="92% of 4 cores")

    assert html =~
             ~s(aria-label="Host memory" aria-valuemin="0" aria-valuemax="100" aria-valuenow="75")

    assert html =~ ~s(aria-valuetext="75% of 8.0 GB")

    # A connected DeployEx peer shares the PubSub, and its readings stay out of this top bar
    send(view.pid, {:update_system_info, %Host.Info{source_node: :peer@host, cpu: 10, cpus: 4}})

    assert render(view) =~ ~s(aria-valuetext="92% of 4 cores")
  end

  @tag :capture_log
  test "other messages still reach the page", %{conn: conn} do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, [FixtureStatus.deployex()]} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, _options -> FixtureStatus.versions() end)

    {:ok, view, html} = live(conn, ~p"/applications")
    refute html =~ "4.5.6"

    send(view.pid, {:monitoring_app_updated, Node.self(), FixtureStatus.list()})

    assert render(view) =~ "4.5.6"
  end
end
