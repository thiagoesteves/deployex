defmodule Sentinel.Logs.ServerTest do
  use ExUnit.Case, async: false

  import Mock
  import Mox

  alias Foundation.Catalog
  alias Host.Terminal
  alias Sentinel.Logs.Message
  alias Sentinel.Logs.Server

  setup [
    :set_mox_from_context,
    :verify_on_exit!,
    :create_consumer
  ]

  test "[un]subscribe_for_new_logs/0", %{sname: sname, pid: pid} do
    log_type = "new-log-type"
    message = "[info] simple log"
    Server.subscribe_for_new_logs(sname, log_type)

    send(
      pid,
      {:terminal_update,
       %{
         metadata: %{context: :terminal_logs, sname: sname, type: log_type},
         source_pid: self(),
         message: message
       }}
    )

    assert_receive {:logs_new_data, ^sname, ^log_type, %Message{timestamp: _, log: ^message}},
                   1_000

    # Validate by inspection
    Server.unsubscribe_for_new_logs(sname, log_type)
  end

  test "get_types_by_sname/1 valid sname", %{sname: sname, pid: pid} do
    log_type = "new-log-type"
    message = "[info] simple log"
    Server.subscribe_for_new_logs(sname, log_type)

    send(
      pid,
      {:terminal_update,
       %{
         metadata: %{context: :terminal_logs, sname: sname, type: log_type},
         source_pid: self(),
         message: message
       }}
    )

    assert_receive {:logs_new_data, ^sname, ^log_type, %Message{timestamp: _, log: _message}},
                   1_000

    log_types = Server.get_types_by_sname(sname)
    assert log_type in log_types
  end

  test "get_types_by_sname/1 invalid sname" do
    assert [] == Server.get_types_by_sname(nil)
  end

  test "list_active_snames/0", %{sname: sname} do
    snames = Server.list_active_snames()
    assert sname in snames
  end

  test "list_data_by_sname_key/3", %{sname: sname, pid: pid} do
    log_type = "new-log-type"
    Server.subscribe_for_new_logs(sname, log_type)

    Enum.each(1..5, fn index ->
      send(
        pid,
        {:terminal_update,
         %{
           metadata: %{context: :terminal_logs, sname: sname, type: log_type},
           source_pid: self(),
           message: "[info] log #{index}"
         }}
      )
    end)

    assert_receive {:logs_new_data, ^sname, ^log_type,
                    %Message{timestamp: _, log: "[info] log 5"}},
                   1_000

    assert [
             %Message{timestamp: _, log: "[info] log 1"},
             %Message{timestamp: _, log: "[info] log 2"},
             %Message{timestamp: _, log: "[info] log 3"},
             %Message{timestamp: _, log: "[info] log 4"},
             %Message{timestamp: _, log: "[info] log 5"}
           ] = Server.list_data_by_sname_log_type(sname, log_type, order: :asc)

    assert [
             %Message{timestamp: _, log: "[info] log 5"},
             %Message{timestamp: _, log: "[info] log 4"},
             %Message{timestamp: _, log: "[info] log 3"},
             %Message{timestamp: _, log: "[info] log 2"},
             %Message{timestamp: _, log: "[info] log 1"}
           ] = Server.list_data_by_sname_log_type(sname, log_type, order: :desc)

    assert [
             %Message{timestamp: _, log: "[info] log 1"},
             %Message{timestamp: _, log: "[info] log 2"},
             %Message{timestamp: _, log: "[info] log 3"},
             %Message{timestamp: _, log: "[info] log 4"},
             %Message{timestamp: _, log: "[info] log 5"}
           ] = Server.list_data_by_sname_log_type(sname, log_type)
  end

  test "Pruning expiring entries", %{sname: sname, pid: pid} do
    log_type = "new-log-type"
    Server.subscribe_for_new_logs(sname, log_type)

    now = System.os_time(:millisecond)

    with_mock System, os_time: fn _ -> now - 120_000 end do
      Enum.each(1..5, fn index ->
        send(
          pid,
          {:terminal_update,
           %{
             metadata: %{context: :terminal_logs, sname: sname, type: log_type},
             source_pid: self(),
             message: "[info] log #{index}"
           }}
        )
      end)

      assert_receive {:logs_new_data, ^sname, ^log_type,
                      %Message{timestamp: _, log: "[info] log 5"}},
                     1_000
    end

    assert [
             %Message{timestamp: _, log: "[info] log 1"},
             %Message{timestamp: _, log: "[info] log 2"},
             %Message{timestamp: _, log: "[info] log 3"},
             %Message{timestamp: _, log: "[info] log 4"},
             %Message{timestamp: _, log: "[info] log 5"}
           ] = Server.list_data_by_sname_log_type(sname, log_type)

    send(pid, :prune_expired_entries)
    :timer.sleep(100)

    assert [] = Server.list_data_by_sname_log_type(sname, log_type, order: :asc)
  end

  test "Pruning expiring entries when retention period is updated", %{sname: sname, pid: pid} do
    log_type = "new-log-type"
    Server.subscribe_for_new_logs(sname, log_type)

    now = System.os_time(:millisecond)

    with_mock System, os_time: fn _ -> now - 30_000 end do
      Enum.each(1..5, fn index ->
        send(
          pid,
          {:terminal_update,
           %{
             metadata: %{context: :terminal_logs, sname: sname, type: log_type},
             source_pid: self(),
             message: "[info] log #{index}"
           }}
        )
      end)

      assert_receive {:logs_new_data, ^sname, ^log_type,
                      %Message{timestamp: _, log: "[info] log 5"}},
                     1_000
    end

    assert [
             %Message{timestamp: _, log: "[info] log 1"},
             %Message{timestamp: _, log: "[info] log 2"},
             %Message{timestamp: _, log: "[info] log 3"},
             %Message{timestamp: _, log: "[info] log 4"},
             %Message{timestamp: _, log: "[info] log 5"}
           ] = Server.list_data_by_sname_log_type(sname, log_type)

    # Update retention period
    Server.update_data_retention_period(1_000)

    :timer.sleep(100)

    assert [] = Server.list_data_by_sname_log_type(sname, log_type, order: :asc)
  end

  test "Check Node up with expected node", %{sname: sname, node: node, pid: pid} do
    log_type = "new-log-type"
    message = "message"
    Server.subscribe_for_new_logs(sname, log_type)

    send(pid, {:nodeup, node})

    send(
      pid,
      {:terminal_update,
       %{
         metadata: %{context: :terminal_logs, sname: sname, type: log_type},
         source_pid: self(),
         message: message
       }}
    )

    assert_receive {:logs_new_data, ^sname, ^log_type, %Message{timestamp: _, log: ^message}},
                   1_000
  end

  test "Check Node down with expected node", %{sname: sname, node: node, pid: pid} do
    log_type = "stderr"
    message = "DeployEx detected node down for node: #{node}"
    Server.subscribe_for_new_logs(sname, log_type)

    send(pid, {:nodedown, node})

    assert_receive {:logs_new_data, ^sname, ^log_type, %Message{timestamp: _, log: ^message}},
                   1_000
  end

  test "Check Node down with unexpected node", %{sname: sname, pid: pid} do
    log_type = "stderr"
    node = :"non-valid-node@nohost"
    message = "DeployEx detected node down for node: #{node}"
    Server.subscribe_for_new_logs(sname, log_type)

    send(pid, {:nodedown, :"nonvalid-node@nohost"})

    refute_receive {:logs_new_data, ^sname, _log_type, %Message{timestamp: _, log: ^message}},
                   1_000
  end

  test "Check no Terminal is created if there is no log file", %{
    fake_sname: fake_sname,
    sname: sname,
    pid: pid
  } do
    log_type = "new-log-type"
    message = "[info] simple log"
    Server.subscribe_for_new_logs(sname, log_type)
    Server.subscribe_for_new_logs(fake_sname, log_type)

    send(
      pid,
      {:terminal_update,
       %{
         metadata: %{context: :terminal_logs, sname: fake_sname, type: log_type},
         source_pid: self(),
         message: message
       }}
    )

    # Send a valid date just to guarantee the previous message was processed
    send(
      pid,
      {:terminal_update,
       %{
         metadata: %{context: :terminal_logs, sname: sname, type: log_type},
         source_pid: self(),
         message: message
       }}
    )

    assert_receive {:logs_new_data, ^sname, ^log_type, %Message{timestamp: _, log: _message}},
                   1_000

    assert [] == Server.get_types_by_sname(fake_sname)
  end

  defp create_consumer(context) do
    sname = Catalog.create_sname("myelixir")
    %{node: node} = Catalog.node_info(sname)
    Catalog.setup_new_node(sname)

    node_self = Node.self()
    Catalog.setup_new_node("nonode")

    fake_sname = Catalog.create_sname("fake")

    Host.CommanderMock
    |> stub(:run, fn _command, _options -> {:ok, self(), "123456"} end)
    |> stub(:stop, fn _pid -> :ok end)

    Deployer.MonitorMock
    |> expect(:list, fn -> [sname] end)
    |> expect(:subscribe_new_deploy, fn -> :ok end)

    test_pid = self()

    with_mock Terminal, new: fn %Terminal{} -> :ok end do
      {:ok, pid} = Server.start_link(data_retention_period: :timer.minutes(1))
      send(test_pid, {:server_pid, pid})
      send(pid, {:new_deploy, node_self, sname})
      send(pid, {:new_deploy, node_self, fake_sname})
    end

    assert_receive {:server_pid, pid}, 1_000

    context
    |> Map.put(:fake_sname, fake_sname)
    |> Map.put(:sname, sname)
    |> Map.put(:node, node)
    |> Map.put(:pid, pid)
  end
end
