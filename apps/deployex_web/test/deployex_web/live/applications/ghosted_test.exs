defmodule DeployexWeb.Applications.GhostedTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias DeployexWeb.Fixture.Status, as: FixtureStatus
  alias DeployexWeb.HostTime
  alias Foundation.Catalog

  setup [:set_mox_global, :verify_on_exit!, :log_in_default_user]

  @name "myerlangapp"

  defp ghosted(version) do
    %Catalog.Version{
      version: version,
      sname: "myerlangapp-abc123",
      name: @name,
      deployment: :full_deployment,
      inserted_at: ~N[2026-10-28 14:20:00]
    }
  end

  defp stub_status(list, test_pid \\ self()) do
    Deployer.StatusMock
    |> stub(:monitoring, fn ->
      {:ok,
       [
         FixtureStatus.deployex(),
         FixtureStatus.application(%{name: @name, language: "erlang", status: :idle})
       ]}
    end)
    |> stub(:subscribe_ghosted_versions, fn @name -> :ok end)
    |> stub(:ghosted_version_list, fn @name -> list end)
    |> stub(:remove_ghosted_version, fn @name, version ->
      send(test_pid, {:removed, version})
      {:ok, []}
    end)
  end

  @tag :capture_log
  test "lists the ghosted versions of an app", %{conn: conn} do
    stub_status([ghosted("0.8.2"), ghosted("0.8.1")])

    {:ok, _view, html} = live(conn, ~p"/applications/#{@name}/ghosted")

    assert html =~ "Ghosted versions · 1 instance · 0/1 running"
    assert html =~ "2 ghosted versions"
    assert html =~ "0.8.2"
    assert html =~ "0.8.1"
    assert html =~ HostTime.format(~U[2026-10-28 14:20:00Z], "%Y-%m-%d %H:%M")
    assert html =~ "Clear all"
  end

  @tag :capture_log
  test "Clear asks first, then clears at once", %{conn: conn} do
    stub_status([ghosted("0.8.2"), ghosted("0.8.1")])

    {:ok, view, _html} = live(conn, ~p"/applications/#{@name}/ghosted")

    html = view |> element("#ghosted-clear-0\\.8\\.2") |> render_click()
    assert html =~ "Clear ghosted 0.8.2?"
    view |> element("button", "Cancel") |> render_click()
    refute has_element?(view, "#ghosted-clear-confirm")
    refute_received {:removed, _}

    view |> element("#ghosted-clear-0\\.8\\.2") |> render_click()
    html = view |> element("#ghosted-clear-confirm") |> render_click()
    assert_received {:removed, "0.8.2"}
    refute_received {:removed, "0.8.1"}
    assert html =~ "Cleared 0.8.2. It can deploy on this host again."

    html = view |> element("#ghosted-clear-all") |> render_click()
    assert html =~ "Clear all 2 ghosted versions?"
    html = view |> element("#ghosted-clear-confirm") |> render_click()
    assert_received {:removed, "0.8.2"}
    assert_received {:removed, "0.8.1"}
    assert html =~ "Cleared 2 ghosted versions. They can deploy on this host again."
  end

  @tag :capture_log
  test "follows the changes of the ghosted list", %{conn: conn} do
    stub_status([])

    {:ok, view, html} = live(conn, ~p"/applications/#{@name}/ghosted")
    assert html =~ "No ghosted versions."

    stub(Deployer.StatusMock, :ghosted_version_list, fn @name -> [ghosted("0.9.0")] end)
    send(view.pid, {:ghosted_versions_updated, Node.self(), @name, []})
    assert render(view) =~ "0.9.0"
  end

  @tag :capture_log
  test "an app this host does not run has no ghosted versions, and its catalog is not read", %{
    conn: conn
  } do
    Deployer.StatusMock
    |> stub(:monitoring, fn -> {:ok, [FixtureStatus.deployex()]} end)
    |> stub(:subscribe_ghosted_versions, fn "unknown" -> :ok end)
    |> expect(:ghosted_version_list, 0, fn _name -> [] end)

    {:ok, _view, html} = live(conn, ~p"/applications/unknown/ghosted")
    assert html =~ "No ghosted versions."
  end
end
