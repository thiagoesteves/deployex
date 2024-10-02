defmodule DeployexWeb.Applications.ModeTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  alias Deployex.Fixture.Monitoring
  alias Deployex.Fixture.Status, as: FixtureStatus

  test "Check all versions are available", %{conn: conn} do
    topic = "topic-mode-000"

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn ->
      Enum.map(1..40, fn index -> FixtureStatus.version(%{version: "1.0.#{index}"}) end)
    end)

    {:ok, _index_live, html} = live(conn, ~p"/applications")

    assert html =~ "1.0.1"
    assert html =~ "1.0.2"
    assert html =~ "1.0.3"
    assert html =~ "1.0.4"
    assert html =~ "1.0.5"
    assert html =~ "1.0.6"
    assert html =~ "1.0.7"
    assert html =~ "1.0.8"
    assert html =~ "1.0.9"
    assert html =~ "1.0.10"
    refute html =~ "1.0.11"
    refute html =~ "1.0.12"
    refute html =~ "1.0.39"
    refute html =~ "1.0.40"

    assert html =~ "<option selected=\"selected\" value=\"automatic\">automatic</option>"
  end

  test "Set manual mode - cancel operation", %{conn: conn} do
    topic = "topic-mode-001"

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn ->
      Enum.map(1..3, fn index -> FixtureStatus.version(%{version: "1.0.#{index}"}) end)
    end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert render_change(index_live, "app-mode-select", %{"select-mode" => "1.0.1"}) =~
             "Are you sure you want to set to 1.0.1?"

    assert index_live |> element("#cancel-button-mode", "Cancel") |> render_click()

    refute has_element?(index_live, "#cancel-button-mode")

    assert render(index_live) =~
             "<option selected=\"selected\" value=\"automatic\">automatic</option>"
  end

  test "Set manual mode - confirm operation", %{conn: conn} do
    topic = "topic-mode-001"

    ref = make_ref()
    pid = self()
    expected_manual_version = "1.0.1"

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> expect(:set_mode, fn :manual, ^expected_manual_version ->
      Process.send_after(pid, {:handle_ref_event, ref}, 100)

      {:ok,
       %Deployex.Storage.Config{
         mode: :manual,
         manual_version: FixtureStatus.version(%{version: expected_manual_version})
       }}
    end)
    |> stub(:history_version_list, fn ->
      Enum.map(1..3, fn index -> FixtureStatus.version(%{version: "1.0.#{index}"}) end)
    end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert render_change(index_live, "app-mode-select", %{
             "select-mode" => expected_manual_version
           }) =~ "Are you sure you want to set to 1.0.1?"

    assert index_live |> element("#confirm-button-mode", "Confirm") |> render_click()

    assert_receive {:handle_ref_event, ^ref}, 1_000

    refute has_element?(index_live, "#confirm-button-mode")
  end

  test "Set automatic mode - confirm operation", %{conn: conn} do
    topic = "topic-mode-002"

    ref = make_ref()
    pid = self()

    Deployex.StatusMock
    |> expect(:monitoring, fn ->
      {:ok,
       [
         Monitoring.deployex(%{
           mode: :manual,
           manual_version: FixtureStatus.version(%{version: "1.0.2"})
         }),
         Monitoring.application()
       ]}
    end)
    |> expect(:listener_topic, fn -> topic end)
    |> expect(:set_mode, fn :automatic, _version ->
      Process.send_after(pid, {:handle_ref_event, ref}, 100)

      {:ok,
       %Deployex.Storage.Config{
         mode: :automatic,
         manual_version: FixtureStatus.version(%{version: "1.0.1"})
       }}
    end)
    |> stub(:history_version_list, fn ->
      Enum.map(1..3, fn index -> FixtureStatus.version(%{version: "1.0.#{index}"}) end)
    end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert render_change(index_live, "app-mode-select", %{
             "select-mode" => "automatic"
           }) =~ "Are you sure you want to set to automatic?"

    assert index_live |> element("#confirm-button-mode", "Confirm") |> render_click()

    assert_receive {:handle_ref_event, ^ref}, 1_000

    refute has_element?(index_live, "#confirm-button-mode")
  end

  test "Check manual mode is set", %{conn: conn} do
    topic = "topic-mode-003"

    Deployex.StatusMock
    |> expect(:monitoring, fn ->
      {:ok,
       [
         Monitoring.deployex(%{
           mode: :manual,
           manual_version: FixtureStatus.version(%{version: "1.0.2"})
         }),
         Monitoring.application()
       ]}
    end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn ->
      Enum.map(1..3, fn index ->
        FixtureStatus.version(%{version: "1.0.#{index}", mode: :manual})
      end)
    end)

    {:ok, _index_live, html} = live(conn, ~p"/applications")

    assert html =~ "<option selected=\"selected\" value=\"1.0.2\">1.0.2</option>"
  end

  test "Check setting the same version is not possible", %{conn: conn} do
    topic = "topic-mode-004"

    Deployex.StatusMock
    |> expect(:monitoring, fn ->
      {:ok,
       [
         Monitoring.deployex(%{
           mode: :manual,
           manual_version: FixtureStatus.version(%{version: "1.0.2"})
         }),
         Monitoring.application()
       ]}
    end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn ->
      Enum.map(1..3, fn index ->
        FixtureStatus.version(%{version: "1.0.#{index}", mode: :manual})
      end)
    end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    refute render_change(index_live, "app-mode-select", %{
             "select-mode" => "1.0.2"
           }) =~ "Are you sure you want to set"
  end

  test "Check setting the same mode is not possible", %{conn: conn} do
    topic = "topic-mode-004"

    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:listener_topic, fn -> topic end)
    |> stub(:history_version_list, fn ->
      Enum.map(1..3, fn index ->
        FixtureStatus.version(%{version: "1.0.#{index}", mode: :manual})
      end)
    end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    refute render_change(index_live, "app-mode-select", %{
             "select-mode" => "automatic"
           }) =~ "Are you sure you want to set"
  end
end
