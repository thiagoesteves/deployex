defmodule DeployexWeb.Applications.GhostedTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias DeployexWeb.Fixture.Status, as: FixtureStatus
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
    assert html =~ "2026-10-28 14:20"
    assert html =~ "Clear all"
  end

  @tag :capture_log
  test "a cleared version can be undone, and is cleared when the window ends", %{conn: conn} do
    stub_status([ghosted("0.8.2"), ghosted("0.8.1")])

    {:ok, view, _html} = live(conn, ~p"/applications/#{@name}/ghosted")

    html = view |> element("#ghosted-clear-0\\.8\\.2") |> render_click()
    assert html =~ "Cleared 0.8.2. It can deploy on this host again."
    refute has_element?(view, "#ghosted-0\\.8\\.2")

    html = view |> element("#ghosted-undo") |> render_click()
    assert has_element?(view, "#ghosted-0\\.8\\.2")
    refute html =~ "Cleared 0.8.2"
    refute_received {:removed, _}

    html = view |> element("#ghosted-clear-all") |> render_click()
    assert html =~ "Cleared 2 ghosted versions. They can deploy on this host again."
    assert html =~ "No ghosted versions. Any version can deploy on this host."

    send(view.pid, :commit_clear)
    assert_receive {:removed, "0.8.2"}
    assert_receive {:removed, "0.8.1"}
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
end
