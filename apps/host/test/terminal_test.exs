defmodule Host.TerminalTest do
  use ExUnit.Case, async: false

  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  alias Host.Fixture.Terminal, as: FixtureTerminal
  alias Host.Terminal

  describe "Initialisation tests" do
    test "Check initializatioon with passed options" do
      ref = make_ref()
      test_pid_process = self()
      node = Node.self()
      os_pid = 123_456
      commands = "command_1"
      options = [:monitor]

      Host.CommanderMock
      |> expect(:run, fn ^commands, ^options ->
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:stop, fn ^os_pid ->
        send(test_pid_process, {:handle_ref_event, ref})
        :ok
      end)

      state = %Terminal{
        node: node,
        commands: commands,
        options: options,
        target: test_pid_process,
        metadata: "test"
      }

      assert {:ok, _pid} = Terminal.new(state)

      assert_receive {:terminal_update, _state}, 1_000

      FixtureTerminal.terminate_all()

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end

    test "Check initializatioon with empty options" do
      ref = make_ref()
      test_pid_process = self()
      node = Node.self()
      os_pid = 123_456
      commands = "command_1"
      options = [:monitor]

      Host.CommanderMock
      |> expect(:run, fn ^commands, ^options ->
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:stop, fn ^os_pid ->
        send(test_pid_process, {:handle_ref_event, ref})
        :ok
      end)

      state = %Terminal{
        node: node,
        commands: commands,
        options: [],
        target: test_pid_process,
        metadata: "test"
      }

      assert {:ok, _pid} = Terminal.new(state)

      assert_receive {:terminal_update, _state}, 1_000

      FixtureTerminal.terminate_all()

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end
  end

  describe "Running application" do
    test "Timeout" do
      ref = make_ref()
      test_pid_process = self()
      node = Node.self()
      os_pid = 123_456
      commands = "command_1"
      options = [:monitor]

      Host.CommanderMock
      |> expect(:run, fn ^commands, ^options ->
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:stop, fn ^os_pid ->
        send(test_pid_process, {:handle_ref_event, ref})
        :ok
      end)

      state = %Terminal{
        node: node,
        commands: commands,
        options: options,
        target: test_pid_process,
        metadata: "test",
        timeout_session: 1
      }

      assert {:ok, _pid} = Terminal.new(state)

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end

    test "Receiving a text from the OS process" do
      ref = make_ref()
      test_pid_process = self()
      node = Node.self()
      os_pid = 123_456
      commands = "command_1"
      options = [:monitor]

      received_msg1 = "received_msg1"
      received_msg2 = "received_msg2"

      Host.CommanderMock
      |> expect(:run, fn ^commands, ^options ->
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:stop, fn ^os_pid ->
        send(test_pid_process, {:handle_ref_event, ref})
        :ok
      end)

      state = %Terminal{
        node: node,
        commands: commands,
        options: [],
        target: test_pid_process,
        metadata: "test"
      }

      assert {:ok, pid} = Terminal.new(state)

      assert_receive {:terminal_update, _state}, 1_000

      send(pid, {:stdout, os_pid, received_msg1})

      assert_receive {:terminal_update, state}, 1_000
      assert state.message == received_msg1
      assert state.msg_sequence == 1

      send(pid, {:stdout, os_pid, received_msg2})

      assert_receive {:terminal_update, state}, 1_000
      assert state.message == received_msg2
      assert state.msg_sequence == 2

      FixtureTerminal.terminate_all()

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end

    @tag :capture_log
    test "Receive a DOWN message from the caller" do
      ref = make_ref()
      test_pid_process = self()
      node = Node.self()
      os_pid = 123_456
      commands = "command_1"
      options = [:monitor]

      Host.CommanderMock
      |> expect(:run, fn ^commands, ^options ->
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:stop, fn ^os_pid ->
        send(test_pid_process, {:handle_ref_event, ref})

        :ok
      end)

      state = %Terminal{
        node: node,
        commands: commands,
        options: [],
        target: test_pid_process,
        metadata: "test"
      }

      assert {:ok, pid} = Terminal.new(state)

      assert_receive {:terminal_update, _state}, 1_000

      send(pid, {:DOWN, :invalid_data, :process, test_pid_process, :any})

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end

    @tag :capture_log
    test "Error while trying to run the commands" do
      ref = make_ref()
      test_pid_process = self()
      node = Node.self()
      commands = "command_1"

      Host.CommanderMock
      |> expect(:run, fn _commands, _options ->
        Process.send_after(test_pid_process, {:handle_ref_event, ref}, 100)
        {:error, :any}
      end)

      state = %Terminal{
        node: node,
        commands: commands,
        options: [],
        target: test_pid_process,
        metadata: "test"
      }

      assert {:ok, _pid} = Terminal.new(state)

      assert_receive {:handle_ref_event, ^ref}, 1_000
    end

    @tag :capture_log
    test "Receive a DOWN message from the OS system process" do
      test_pid_process = self()
      node = Node.self()
      os_pid = 123_456
      commands = "command_1"
      options = [:monitor]

      Host.CommanderMock
      |> expect(:run, fn ^commands, ^options ->
        {:ok, test_pid_process, os_pid}
      end)
      |> expect(:stop, 0, fn ^os_pid -> :ok end)

      state = %Terminal{
        node: node,
        commands: commands,
        options: [],
        target: test_pid_process,
        metadata: "test"
      }

      assert {:ok, pid} = Terminal.new(state)

      assert_receive {:terminal_update, _state}, 1_000

      send(pid, {:DOWN, os_pid, :process, :invalid_data, :any})

      assert_receive {:terminal_update, _state}, 1_000
    end
  end
end
