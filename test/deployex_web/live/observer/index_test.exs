defmodule DeployexWeb.Observer.IndexTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Deployex.Fixture.Monitoring
  alias Deployex.Fixture.Status, as: FixtureStatus
  alias Deployex.Fixture.Terminal, as: FixtureTerminal
  alias Deployex.Terminal

  setup [
    :set_mox_global,
    :verify_on_exit!,
    :log_in_default_user
  ]

  test "GET /applications check buttom", %{conn: conn} do
    Deployex.StatusMock
    |> expect(:monitoring, fn -> {:ok, Monitoring.list()} end)
    |> expect(:subscribe, fn -> :ok end)
    |> stub(:monitored_app_name, fn -> "testapp" end)
    |> stub(:monitored_app_lang, fn -> "elixir" end)
    |> stub(:history_version_list, fn -> FixtureStatus.versions() end)

    {:ok, index_live, _html} = live(conn, ~p"/applications")

    assert index_live
           |> element("a", "Observer")
           |> render_click()
  end

  test "GET /observer", %{conn: conn} do
    {:ok, _index_live, html} = live(conn, ~p"/observer")

    assert html =~ "Live Observer"
  end

  test "Add/Remove Local Service + Kernel App", %{conn: conn} do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    {:ok, index_live, _html} = live(conn, ~p"/observer")

    index_live
    |> element("#observer-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#observer-multi-select-services-#{service}-add-item")
    |> render_click()

    html =
      index_live
      |> element("#observer-multi-select-apps-kernel-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "apps:kernel"

    html =
      index_live
      |> element("#observer-multi-select-apps-kernel-remove-item")
      |> render_click()

    assert html =~ "services:#{node}"
    refute html =~ "apps:kernel"

    html =
      index_live
      |> element("#observer-multi-select-services-#{service}-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    refute html =~ "apps:kernel"
  end

  test "Add/Remove Kernel App + Local Service", %{conn: conn} do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    {:ok, index_live, _html} = live(conn, ~p"/observer")

    index_live
    |> element("#observer-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#observer-multi-select-apps-kernel-add-item")
    |> render_click()

    html =
      index_live
      |> element("#observer-multi-select-services-#{service}-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "apps:kernel"

    html =
      index_live
      |> element("#observer-multi-select-services-#{service}-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    assert html =~ "apps:kernel"

    html =
      index_live
      |> element("#observer-multi-select-apps-kernel-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    refute html =~ "apps:kernel"
  end

  test "Select Service+Apps and select a process to request information", %{conn: conn} do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    {:ok, index_live, _html} = live(conn, ~p"/observer")

    index_live
    |> element("#observer-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#observer-multi-select-apps-kernel-add-item")
    |> render_click()

    index_live
    |> element("#observer-multi-select-services-#{service}-add-item")
    |> render_click()

    pid = Enum.random(:erlang.processes())

    # Send the request 2 times to validate the path where the request
    # was already executed.
    index_live
    |> element("#observer-tree")
    |> render_hook("request-process", %{"id" => "#{inspect(pid)}"})

    html =
      index_live
      |> element("#observer-tree")
      |> render_hook("request-process", %{"id" => "#{inspect(pid)}"})

    # Check the Process information is being shown
    assert html =~ "Group Leader"
    assert html =~ "Heap Size"
  end

  test "Select Service+Apps and select a port to request information", %{conn: conn} do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    {:ok, index_live, _html} = live(conn, ~p"/observer")

    index_live
    |> element("#observer-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#observer-multi-select-apps-kernel-add-item")
    |> render_click()

    index_live
    |> element("#observer-multi-select-services-#{service}-add-item")
    |> render_click()

    port = Enum.random(:erlang.ports())

    html =
      index_live
      |> element("#observer-tree")
      |> render_hook("request-process", %{"pid" => "#{inspect(port)}"})

    # Check the Port information is NOT being shown
    refute html =~ "Group Leader"
    refute html =~ "Heap Size"
  end

  @tag :capture_log
  test "Update buttom with Deployex App + Local Service", %{conn: conn} do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    {:ok, index_live, _html} = live(conn, ~p"/observer")

    index_live
    |> element("#observer-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#observer-multi-select-apps-deployex-add-item")
    |> render_click()

    html =
      index_live
      |> element("#observer-multi-select-services-#{service}-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "apps:deployex"

    ref = make_ref()
    test_pid_process = self()
    instance = 1000
    os_pid = 123_456
    commands = "command_1"
    options = [:monitor]

    Deployex.OpSysMock
    |> stub(:run, fn _commands, _options -> {:ok, test_pid_process, os_pid} end)
    |> stub(:stop, fn _os_pid ->
      send(test_pid_process, {:handle_ref_event, ref})
      :ok
    end)

    state = %Terminal{
      instance: instance,
      commands: commands,
      options: options,
      target: test_pid_process,
      metadata: "test"
    }

    assert {:ok, pid} = Terminal.new(state)

    pid_string = String.slice("#{inspect(pid)}", 5..-2//1)

    refute html =~ pid_string

    html =
      index_live
      |> element("#observer-multi-select-update", "UPDATE")
      |> render_click()

    assert html =~ pid_string

    FixtureTerminal.terminate_all()

    assert_receive {:handle_ref_event, ^ref}, 1_000
  end
end
