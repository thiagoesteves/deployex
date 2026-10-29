defmodule DeployexWeb.UI.ComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias DeployexWeb.UI.Menu
  alias DeployexWeb.UI.Meter
  alias DeployexWeb.UI.Shell
  alias DeployexWeb.UI.ThemeSwitch

  describe "Meter.meter/1" do
    test "is a meter with its value and capacity" do
      html =
        render_component(&Meter.meter/1,
          label: "CPU",
          name: "Host CPU",
          value: 23,
          detail: "2 cores"
        )

      assert html =~ ~s(role="meter")
      assert html =~ ~s(aria-label="Host CPU")
      assert html =~ ~s(aria-valuenow="23")
      assert html =~ ~s(aria-valuetext="23% of 2 cores")
      assert html =~ "23%"
      assert html =~ "2 cores"
    end

    test "is blue below 75, amber from 75 and red from 90" do
      assert render_component(&Meter.meter/1, label: "CPU", name: "CPU", value: 74) =~ "bg-info"

      assert render_component(&Meter.meter/1, label: "CPU", name: "CPU", value: 75) =~
               "bg-warning"

      assert render_component(&Meter.meter/1, label: "CPU", name: "CPU", value: 89) =~
               "bg-warning"

      assert render_component(&Meter.meter/1, label: "CPU", name: "CPU", value: 90) =~ "bg-error"
    end

    test "keeps the bar in range and shows the reading as it is" do
      html = render_component(&Meter.meter/1, label: "CPU", name: "CPU", value: 151)

      assert html =~ ~s(aria-valuenow="100")
      assert html =~ "width: 100%"
      assert html =~ "151%"
    end

    test "shows no value before the first reading" do
      html = render_component(&Meter.meter/1, label: "Memory", name: "Host memory", value: nil)

      assert html =~ ~s(aria-valuenow="0")
      assert html =~ ~s(aria-valuetext="No reading yet")
      assert html =~ "--"
    end

    test "names the value alone with no capacity" do
      assert render_component(&Meter.meter/1, label: "CPU", name: "CPU", value: 5) =~
               ~s(aria-valuetext="5%")
    end
  end

  describe "Menu.menu/1" do
    test "is a closed disclosure button with its panel" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <Menu.menu id="account" label="Account menu for admin">
          <:button>AD</:button>
          <Menu.item href="/users/log_out" method="delete">Log out</Menu.item>
          <Menu.item phx-click="noop">Act</Menu.item>
        </Menu.menu>
        """)

      assert html =~ ~s(id="account-button")
      assert html =~ ~s(aria-expanded="false")
      assert html =~ ~s(aria-controls="account-panel")
      assert html =~ ~s(aria-label="Account menu for admin")
      assert html =~ ~s(phx-hook="Menu")
      assert html =~ "data-escape"
      assert html =~ "phx-click-away"
      assert html =~ ~s(data-method="delete")
      assert html =~ ~r/<button type="button" class="[^"]*" phx-click="noop">\s*Act/
    end
  end

  describe "ThemeSwitch.theme_switch/1" do
    test "is a labeled switch that raises the toggle event" do
      html = render_component(&ThemeSwitch.theme_switch/1, %{})

      assert html =~ ~s(role="switch")
      assert html =~ ~s(aria-label="Dark mode")
      assert html =~ ~s(phx-hook="ShellState")
      assert html =~ "dx:toggle-theme"
    end
  end

  describe "Shell" do
    test "shell/1 has the top bar, the sidebar and the content" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <Shell.shell console="Agent Console" home="/applications">
          <:top_bar_center><input id="search" /></:top_bar_center>
          <:top_bar_end><span id="meters"></span></:top_bar_end>
          <:sidebar><a id="nav">Nav</a></:sidebar>
          <p id="page">Page</p>
        </Shell.shell>
        """)

      assert html =~ "Agent Console"
      assert html =~ ~s(href="/applications")
      assert html =~ ~s(id="shell-sidebar-toggle")
      assert html =~ "dx:toggle-sidebar"
      assert html =~ ~s(id="search")
      assert html =~ ~s(id="meters")
      assert html =~ ~s(id="nav")
      assert html =~ ~s(id="page")
    end

    test "nav_item/1 marks only the active page" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <Shell.nav_item navigate="/logs/live" label="Live Logs" active>
          <:icon>i</:icon>
        </Shell.nav_item>
        <Shell.nav_item navigate="/terminal" label="Host Terminal">
          <:icon>i</:icon>
        </Shell.nav_item>
        """)

      assert html =~ ~s(data-phx-link="redirect")
      assert [_active] = Regex.scan(~r/aria-current="page"/, html)
      assert html =~ ~r/href="\/logs\/live"[^>]*aria-current="page"/
      assert html =~ "bg-nav-active"
    end
  end
end
