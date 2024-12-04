defmodule Deployex.TracerTest do
  use ExUnit.Case, async: true

  import Mox
  import ExUnit.CaptureLog

  alias Deployex.Tracer, as: DeployexT
  alias Deployex.TracerFixtures

  setup :verify_on_exit!

  test "get_modules/1" do
    Deployex.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    assert list = DeployexT.get_modules(Node.self())
    assert Enum.member?(list, :kernel)
  end

  test "get_module_functions_info/2" do
    Deployex.RpcMock
    |> stub(:call, fn node, module, function, args, timeout ->
      :rpc.call(node, module, function, args, timeout)
    end)

    assert %{
             functions: %{"config_change/3" => %{arity: 3, name: :config_change}},
             module: :kernel,
             node: :nonode@nohost
           } = DeployexT.get_module_functions_info(Node.self(), :kernel)

    assert %{
             functions: _,
             module: :erlang,
             node: :nonode@nohost
           } = DeployexT.get_module_functions_info(Node.self(), :erlang)
  end

  test "get_default_functions_matchspecs/0" do
    assert %{
             return_trace: %{pattern: [{:_, [], [{:return_trace}]}]},
             exception_trace: %{pattern: [{:_, [], [{:exception_trace}]}]},
             caller: %{pattern: [{:_, [], [{:message, {:caller}}]}]},
             process_dump: %{pattern: [{:_, [], [{:message, {:process_dump}}]}]}
           } = DeployexT.get_default_functions_matchspecs()
  end

  describe "start_trace/2" do
    test "Only one session is allowed for Tracer" do
      functions = [
        %{
          arity: :_,
          function: :_,
          match_spec: [],
          module: TracerFixtures,
          node: Node.self()
        }
      ]

      assert {:ok, %{session_id: session_id}} =
               DeployexT.start_trace(functions, %{max_messages: 1})

      assert {:error, :already_started} =
               DeployexT.start_trace(functions, %{max_messages: 1})

      terminate_tracing(session_id)
    end

    test "Success requesting only module" do
      node = Node.self()

      functions = [
        %{
          arity: :_,
          function: :_,
          match_spec: [],
          module: TracerFixtures,
          node: node
        }
      ]

      assert {:ok, %{session_id: session_id} = state} =
               DeployexT.start_trace(functions, %{max_messages: 1})

      assert state == DeployexT.state()

      TracerFixtures.testing_fun([true, true, true])

      assert_receive {:new_trace_message, ^session_id, ^node, _index, :call, msg}, 1_000

      assert msg =~ "TracerFixtures"

      terminate_tracing(session_id)
    end

    test "Success requesting module/function" do
      node = Node.self()

      functions = [
        %{
          arity: 2,
          function: :testing_adding_fun,
          match_spec: [],
          module: TracerFixtures,
          node: node
        }
      ]

      assert {:ok, %{session_id: session_id}} =
               DeployexT.start_trace(functions, %{max_messages: 1})

      TracerFixtures.testing_adding_fun(50, 50)

      assert_receive {:new_trace_message, ^session_id, ^node, _index, :call, msg}, 1_000

      assert msg =~ "TracerFixtures"
      assert msg =~ "testing_adding_fun"

      terminate_tracing(session_id)
    end

    test "Success requesting module/function with match_spec [return_trace]" do
      node = Node.self()

      functions = [
        %{
          arity: 2,
          function: :testing_adding_fun,
          match_spec: ["return_trace"],
          module: TracerFixtures,
          node: node
        }
      ]

      assert {:ok, %{session_id: session_id}} =
               DeployexT.start_trace(functions, %{max_messages: 2})

      TracerFixtures.testing_adding_fun(253, 200)

      assert_receive {:new_trace_message, ^session_id, ^node, _index, :return_from, msg}, 1_000

      assert msg =~ "TracerFixtures"
      assert msg =~ "testing_adding_fun"
      assert msg =~ "453"

      terminate_tracing(session_id)
    end

    test "Success requesting module/function with match_spec [caller]" do
      node = Node.self()

      functions = [
        %{
          arity: 2,
          function: :testing_adding_fun,
          match_spec: ["caller"],
          module: TracerFixtures,
          node: node
        }
      ]

      assert {:ok, %{session_id: session_id}} =
               DeployexT.start_trace(functions, %{max_messages: 2})

      TracerFixtures.testing_adding_fun(255, 200)

      assert_receive {:new_trace_message, ^session_id, ^node, _index, :call, msg}, 1_000

      assert msg =~ "TracerFixtures"
      assert msg =~ "testing_adding_fun"
      assert msg =~ "caller: {Deployex.TracerTest"

      terminate_tracing(session_id)
    end

    @tag :capture_log
    test "Success requesting module/function with match_spec [exception_trace]" do
      node = Node.self()

      functions = [
        %{
          arity: 1,
          function: :testing_exception_fun,
          match_spec: ["exception_trace"],
          module: TracerFixtures,
          node: node
        }
      ]

      assert {:ok, %{session_id: session_id}} =
               DeployexT.start_trace(functions, %{max_messages: 2})

      spawn(fn ->
        TracerFixtures.testing_exception_fun(0)
      end)

      assert_receive {:new_trace_message, ^session_id, ^node, _index, :exception_from, msg}, 1_000

      assert msg =~ "TracerFixtures"
      assert msg =~ "testing_exception_fun"
      assert msg =~ "exception_value: {:error, :badarith}"

      terminate_tracing(session_id)
    end
  end

  describe "stop_trace/2" do
    test "Ignore stop_trace with invalid session_id [handle_call]" do
      functions = [
        %{
          arity: :_,
          function: :_,
          match_spec: [],
          module: TracerFixtures,
          node: Node.self()
        }
      ]

      assert {:ok, %{session_id: session_id}} =
               DeployexT.start_trace(functions, %{max_messages: 30})

      assert %DeployexT{status: :running} = DeployexT.state()

      assert :ok == DeployexT.stop_trace("123456789")

      assert %DeployexT{status: :running} = DeployexT.state()

      terminate_tracing(session_id)
    end

    test "Ignore stop_trace with invalid session_id [handle_info]" do
      functions = [
        %{
          arity: :_,
          function: :_,
          match_spec: [],
          module: TracerFixtures,
          node: Node.self()
        }
      ]

      assert {:ok, %{session_id: session_id}} =
               DeployexT.start_trace(functions, %{max_messages: 30})

      assert %DeployexT{status: :running} = DeployexT.state()

      send(Deployex.Tracer.Server, {:stop_tracing, "123456789"})

      assert %DeployexT{status: :running} = DeployexT.state()

      terminate_tracing(session_id)
    end
  end

  describe "Timeouts" do
    test "Session Timed out" do
      functions = [
        %{
          arity: :_,
          function: :_,
          match_spec: [],
          module: TracerFixtures,
          node: Node.self()
        }
      ]

      assert {:ok, %{session_id: _session_id}} =
               DeployexT.start_trace(functions, %{max_messages: 30, session_timeout_ms: 50})

      assert_receive {:trace_session_timeout, _session_id}, 1_000
    end

    test "Ignore Timeout messages with invalid ID" do
      functions = [
        %{
          arity: :_,
          function: :_,
          match_spec: [],
          module: TracerFixtures,
          node: Node.self()
        }
      ]

      assert {:ok, %{session_id: session_id}} =
               DeployexT.start_trace(functions, %{max_messages: 20})

      assert %DeployexT{status: :running} = DeployexT.state()

      send(Deployex.Tracer.Server, {:trace_session_timeout, "invalid-session"})

      assert %DeployexT{status: :running} = DeployexT.state()

      terminate_tracing(session_id)
    end
  end

  test "Request Function terminate" do
    functions = [
      %{
        arity: :_,
        function: :_,
        match_spec: [],
        module: TracerFixtures,
        node: Node.self()
      }
    ]

    assert capture_log(fn ->
             spawn(fn ->
               {:ok, %{session_id: _session_id}} =
                 DeployexT.start_trace(functions, %{max_messages: 20})
             end)

             :timer.sleep(50)

             assert %DeployexT{status: :idle} = DeployexT.state()
           end) =~ "target process was terminated"
  end

  defp terminate_tracing(session_id) do
    :ok = DeployexT.stop_trace(session_id)
    :timer.sleep(50)
  end
end
