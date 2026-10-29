defmodule DeployexWeb.Applications.VersionsTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias DeployexWeb.Fixture.Status, as: FixtureStatus
  alias Foundation.Catalog

  setup [:set_mox_global, :verify_on_exit!, :log_in_default_user]

  @name "myphoenixapp"
  @sname "myphoenixapp-abc123"

  defp version(version, deployment, inserted_at) do
    %Catalog.Version{
      version: version,
      name: @name,
      sname: @sname,
      deployment: deployment,
      inserted_at: inserted_at
    }
  end

  defp stub_status(config, test_pid \\ self()) do
    Deployer.StatusMock
    |> stub(:monitoring, fn ->
      {:ok,
       [
         FixtureStatus.deployex(),
         FixtureStatus.application(%{name: @name, version: "1.4.2"}, config)
       ]}
    end)
    |> stub(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn @name, [] ->
      [
        version("1.4.2", :hot_upgrade, ~N[2026-10-28 12:14:00]),
        version("1.4.1", :full_deployment, ~N[2026-10-25 09:02:00])
      ]
    end)
    |> stub(:set_mode, fn @name, mode, version ->
      send(test_pid, {:set_mode, mode, version})
      {:ok, %{}}
    end)
  end

  defp config(mode \\ :automatic, manual_version \\ nil) do
    %{
      last_ghosted_version: "-/-",
      mode: mode,
      manual_version: manual_version,
      versions: ["1.4.2", "1.4.1", "1.4.0"]
    }
  end

  @tag :capture_log
  test "shows the mode and the version history of an app", %{conn: conn} do
    stub_status(config())

    {:ok, _view, html} = live(conn, ~p"/applications/#{@name}/versions")

    assert html =~ "Versions and mode · 1 instance · current 1.4.2"
    assert html =~ "Automatic"
    assert html =~ "DeployEx deploys the version that current.json names in the release bucket."
    assert html =~ "2026-10-28 12:14"
    assert html =~ "Hot upgrade"
    assert html =~ "2026-10-25 09:02"
    assert [_current] = Regex.scan(~r/>current</, html)
    assert html =~ "This host keeps the releases of the last 2 versions."
    assert html =~ ~s(href="/applications/#{@name}/ghosted")
    refute html =~ ~s(id="mode-save")
  end

  @tag :capture_log
  test "pins a version after a confirmation", %{conn: conn} do
    stub_status(config())

    {:ok, view, _html} = live(conn, ~p"/applications/#{@name}/versions")

    html = view |> element("#mode-pin") |> render_click()
    assert html =~ "Version to pin"
    assert html =~ "1.4.2 (current)"
    assert html =~ "Pin 1.4.1…"

    html = view |> element("#mode-form") |> render_change(%{"version" => "1.4.0"})
    assert html =~ "Pin 1.4.0…"

    html = view |> element("#mode-save") |> render_click()

    assert html =~
             "Pin myphoenixapp to 1.4.0? DeployEx deploys 1.4.0 to the instance and stops following current.json."

    html = view |> element("button", "Cancel") |> render_click()
    refute html =~ "stops following current.json."

    view |> element("#mode-save") |> render_click()
    view |> element("#mode-confirm") |> render_click()
    assert_receive {:set_mode, :manual, "1.4.0"}
  end

  @tag :capture_log
  test "a pinned app goes back to Automatic after a confirmation", %{conn: conn} do
    stub_status(config(:manual, %Catalog.Version{version: "1.4.1"}))

    {:ok, view, html} = live(conn, ~p"/applications/#{@name}/versions")
    assert html =~ "Pinned to 1.4.1"
    assert html =~ "DeployEx keeps the instance on 1.4.1"

    view |> element("#mode-automatic") |> render_click()
    html = view |> element("#mode-save") |> render_click()
    assert html =~ "Set myphoenixapp to Automatic?"

    view |> element("#mode-confirm") |> render_click()
    assert_receive {:set_mode, :automatic, ""}
  end

  @tag :capture_log
  test "the history shows one instance's versions from its own path", %{conn: conn} do
    stub_status(config())

    {:ok, view, _html} = live(conn, ~p"/applications/#{@name}/#{@sname}/versions")
    assert has_element?(view, ~s(a[aria-pressed="true"]), "abc123")

    render_patch(view, ~p"/applications/#{@name}/versions")
    assert has_element?(view, ~s(a[aria-pressed="true"]), "All instances")
    refute has_element?(view, ~s(a[aria-pressed="true"]), "abc123")

    # Another node's update changes nothing, this node's reloads the page
    send(view.pid, {:monitoring_app_updated, :other@host, []})
    send(view.pid, {:monitoring_app_updated, Node.self(), []})
    assert render(view) =~ "1.4.1"
  end

  @tag :capture_log
  test "an app with no history says so", %{conn: conn} do
    Deployer.StatusMock
    |> stub(:monitoring, fn -> {:ok, [FixtureStatus.deployex()]} end)
    |> stub(:subscribe, fn -> :ok end)
    |> stub(:history_version_list, fn _name, [] -> [] end)

    {:ok, _view, html} = live(conn, ~p"/applications/unknown/versions")
    assert html =~ "No version has run on this host yet."
    assert html =~ "current none"
  end
end
