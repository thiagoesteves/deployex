defmodule DeployexWeb.Observer.TracingTest do
  use DeployexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Deployex.Fixture.Monitoring
  alias Deployex.Fixture.Status, as: FixtureStatus
  alias Deployex.Tracer, as: DeployexT

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
           |> element("a", "Live Tracing")
           |> render_click()
  end

  test "GET /tracing", %{conn: conn} do
    Deployex.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)
    |> stub(:pinfo, fn pid, information -> :rpc.pinfo(pid, information) end)

    {:ok, _index_live, html} = live(conn, ~p"/tracing")

    assert html =~ "Live Tracing"
  end

  test "Add/Remove Local Service + Module + Function + MatchSpec", %{conn: conn} do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    Deployex.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    {:ok, index_live, _html} = live(conn, ~p"/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-Enum-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-functions-map-2-add-item")
    |> render_click()

    html =
      index_live
      |> element("#tracing-multi-select-match_spec-caller-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "modules:Elixir.Enum"
    assert html =~ "functions:map/2"
    assert html =~ "match_spec:caller"

    html =
      index_live
      |> element("#tracing-multi-select-services-#{service}-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    assert html =~ "modules:Elixir.Enum"
    assert html =~ "functions:map/2"
    assert html =~ "match_spec:caller"

    html =
      index_live
      |> element("#tracing-multi-select-modules-Elixir-Enum-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    refute html =~ "modules:Elixir.Enum"
    assert html =~ "functions:map/2"
    assert html =~ "match_spec:caller"

    html =
      index_live
      |> element("#tracing-multi-select-functions-map-2-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    refute html =~ "modules:Elixir.Enum"
    refute html =~ "functions:map/2"
    assert html =~ "match_spec:caller"

    html =
      index_live
      |> element("#tracing-multi-select-match_spec-caller-remove-item")
      |> render_click()

    refute html =~ "services:#{node}"
    refute html =~ "modules:Elixir.Enum"
    refute html =~ "functions:map/2"
    refute html =~ "match_spec:caller"
  end

  test "Run Trace for module Deployex.Common", %{conn: conn} do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    Deployex.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    {:ok, index_live, _html} = live(conn, ~p"/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-Deployex-Common-add-item")
    |> render_click()

    index_live
    |> element("#tracing-update-form")
    |> render_change(%{max_messages: 1_000, session_timeout_seconds: 30})

    html =
      index_live
      |> element("#tracing-multi-select-run", "RUN")
      |> render_click()

    refute html =~ "RUN"
    assert html =~ "STOP"

    Deployex.Common.uuid4()

    html =
      index_live
      |> element("#tracing-multi-select-stop", "STOP")
      |> render_click()

    assert render(index_live) =~ "Deployex.Common.uuid4"

    assert html =~ "RUN"
    refute html =~ "STOP"
  end

  test "Run Trace for function Deployex.Common.uptime_to_string/1", %{conn: conn} do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    Deployex.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    {:ok, index_live, _html} = live(conn, ~p"/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-Deployex-Common-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-functions-uptime_to_string-1-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-match_spec-caller-add-item")
    |> render_click()

    html =
      index_live
      |> element("#tracing-multi-select-run", "RUN")
      |> render_click()

    refute html =~ "RUN"
    assert html =~ "STOP"

    start_time = System.monotonic_time()

    assert "now" == Deployex.Common.uptime_to_string(start_time)

    :timer.sleep(50)

    assert render(index_live) =~ "Deployex.Common.uptime_to_string"
    assert render(index_live) =~ "caller: {DeployexWeb.Observer.TracingTest"

    index_live
    |> element("#tracing-multi-select-stop", "STOP")
    |> render_click()
  end

  test "Run Trace for mix Elixir.Enum and function Deployex.Common.uptime_to_string/1", %{
    conn: conn
  } do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    Deployex.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    {:ok, index_live, _html} = live(conn, ~p"/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-Deployex-Common-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-Enum-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-functions-uptime_to_string-1-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-match_spec-caller-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-run", "RUN")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-stop", "STOP")
    |> render_click()

    assert render(index_live) =~ "Enum."
  end

  test "Tracing timing out", %{conn: conn} do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    Deployex.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    {:ok, index_live, _html} = live(conn, ~p"/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-Deployex-Common-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-functions-uptime_to_string-1-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-match_spec-caller-add-item")
    |> render_click()

    index_live
    |> element("#tracing-update-form")
    |> render_change(%{max_messages: 5, session_timeout_seconds: 0})

    index_live
    |> element("#tracing-multi-select-run", "RUN")
    |> render_click()

    :timer.sleep(50)

    assert html = render(index_live)
    assert html =~ "RUN"
    refute html =~ "STOP"
  end

  test "Try to RUN tracing when it is already running", %{conn: conn} do
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")

    Deployex.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    {:ok, index_live, _html} = live(conn, ~p"/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-modules-Elixir-Deployex-Common-add-item")
    |> render_click()

    functions = [
      %{
        arity: 2,
        function: :testing_adding_fun,
        match_spec: [],
        module: Deployex.TracerFixtures,
        node: Node.self()
      }
    ]

    assert {:ok, %{session_id: session_id}} =
             DeployexT.start_trace(functions, %{max_messages: 1})

    index_live
    |> element("#tracing-multi-select-run", "RUN")
    |> render_click()

    html =
      index_live
      |> element("#tracing-multi-select-toggle-options")
      |> render_click()

    assert html =~ "IN USE"
    refute html =~ "START"

    DeployexT.stop_trace(session_id)
  end

  test "Testing NodeUp/NodeDown", %{conn: conn} do
    fake_node = :myapp@nohost
    node = Node.self() |> to_string
    service = String.replace(node, "@", "-")
    test_pid_process = self()

    Deployex.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      send(test_pid_process, {:tracing_index_pid, self()})
      :rpc.call(node, module, function, args, timeout)
    end)

    {:ok, index_live, _html} = live(conn, ~p"/tracing")

    index_live
    |> element("#tracing-multi-select-toggle-options")
    |> render_click()

    index_live
    |> element("#tracing-multi-select-services-#{service}-add-item")
    |> render_click()

    assert_receive {:tracing_index_pid, tracing_index_pid}, 1_000

    html =
      index_live
      |> element("#tracing-multi-select-modules-Elixir-Deployex-Common-add-item")
      |> render_click()

    assert html =~ "services:#{node}"
    assert html =~ "modules:Elixir.Deployex.Common"

    send(tracing_index_pid, {:nodeup, fake_node})
    send(tracing_index_pid, {:nodedown, fake_node})

    # Check node up/down doesn't change the selected items
    assert html = render(index_live)
    assert html =~ "services:#{node}"
    assert html =~ "modules:Elixir.Deployex.Common"
  end
end
