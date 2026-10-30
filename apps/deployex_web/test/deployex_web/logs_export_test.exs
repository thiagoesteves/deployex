defmodule DeployexWeb.LogsExportTest do
  use ExUnit.Case, async: false

  import Mox

  alias DeployexWeb.LogsExport
  alias Foundation.Catalog
  alias Sentinel.Logs.Message

  setup [:set_mox_global, :verify_on_exit!]

  setup do
    test_pid = self()
    sname = Catalog.create_sname("myelixir")

    stub(Deployer.MonitorMock, :list, fn -> [sname] end)

    Sentinel.LogsMock
    |> stub(:list_active_snames, fn -> [] end)
    |> stub(:get_types_by_sname, fn _sname -> [:stdout, :stderr] end)
    |> stub(:list_data_by_sname_log_type, fn asked, type, options ->
      send(test_pid, {:read, asked, type, options[:from]})

      case {asked, type} do
        {^sname, "stdout"} -> [message("second\nthird", 20), message("first", 40)]
        {"deployex", "stderr"} -> [message("[error] boom", 30)]
        _other -> []
      end
    end)

    %{sname: sname}
  end

  defp message(log, seconds_ago),
    do: %Message{timestamp: System.os_time(:millisecond) - seconds_ago * 1_000, log: log}

  test "params keeps what is set, for an export link" do
    assert LogsExport.params(%{sources: ["a", "b"], types: ["stdout"], minutes: 60, filter: ""}) ==
             [source: "a,b", stream: "stdout", minutes: 60]

    assert LogsExport.params(%{sources: ["a"], types: [], since: 1_700_000_000, filter: "boom"}) ==
             [source: "a", since: 1_700_000_000, filter: "boom"]
  end

  test "lines reads every source and stream asked, oldest first, split on new lines", %{
    sname: sname
  } do
    lines = LogsExport.lines(%{"source" => "#{sname},deployex", "minutes" => "15"})

    assert Enum.map(lines, &{&1.source, &1.stream, &1.text}) == [
             {sname, "stdout", "first"},
             {"deployex", "stderr", "[error] boom"},
             {sname, "stdout", "second"},
             {sname, "stdout", "third"}
           ]

    assert_received {:read, ^sname, "stdout", 15}
    assert_received {:read, "deployex", "stderr", 15}
  end

  test "lines keeps the streams and the filter asked", %{sname: sname} do
    assert [%{text: "[error] boom"}] =
             LogsExport.lines(%{"source" => "#{sname},deployex", "stream" => "stderr"})

    assert [%{text: "third"}] =
             LogsExport.lines(%{"source" => "#{sname},deployex", "filter" => "THIRD"})

    # The filter also matches the source
    assert [%{source: "deployex"}] =
             LogsExport.lines(%{"source" => "#{sname},deployex", "filter" => "deployex"})
  end

  test "lines reads no source this host does not have" do
    assert LogsExport.lines(%{"source" => "other-abc123,../etc"}) == []
    refute_received {:read, _sname, _type, _minutes}
  end

  test "lines reads the minutes since a time, within a week", %{sname: sname} do
    since = System.os_time(:second) - 10 * 60
    LogsExport.lines(%{"source" => sname, "since" => to_string(since), "stream" => "stdout"})
    assert_received {:read, ^sname, "stdout", 11}

    LogsExport.lines(%{"source" => sname, "since" => "0", "stream" => "stdout"})
    assert_received {:read, ^sname, "stdout", 10_080}

    LogsExport.lines(%{"source" => sname, "minutes" => "99999", "stream" => "stdout"})
    assert_received {:read, ^sname, "stdout", 10_080}

    LogsExport.lines(%{"source" => sname, "minutes" => "soon", "stream" => "stdout"})
    assert_received {:read, ^sname, "stdout", 60}

    LogsExport.lines(%{"source" => sname, "since" => "soon", "stream" => "stdout"})
    assert_received {:read, ^sname, "stdout", 60}
  end

  test "lines holds this host's events when the events source is asked" do
    Foundation.Notifications.notify("crash_restart", %{
      sname: "export-test-abc",
      crash_restart_count: 2
    })

    Process.sleep(50)

    lines = LogsExport.lines(%{"source" => "events", "filter" => "export-test-abc"})

    assert [%{source: "events", stream: "event", text: "export-test-abc crash restart" <> _}] =
             lines
  end

  test "render writes a .log line or a .jsonl object for each line" do
    lines = [
      %{
        at: ~U[2026-10-29 14:18:19.123Z],
        source: "myapp-abc",
        stream: "stderr",
        text: "[error] \"boom\""
      }
    ]

    assert IO.iodata_to_binary(LogsExport.render(lines, "log")) ==
             ~s(2026-10-29T14:18:19.123Z myapp-abc stderr [error] "boom"\n)

    assert IO.iodata_to_binary(LogsExport.render(lines, "jsonl")) ==
             ~s({"at":"2026-10-29T14:18:19.123Z","source":"myapp-abc","stream":"stderr","message":"[error] \\"boom\\""}\n)
  end

  test "filename names the host, the time and the format" do
    assert LogsExport.filename("my host", "jsonl") =~
             ~r/^deployex-logs-my-host-\d{8}-\d{6}\.jsonl$/

    assert LogsExport.filename("myhost", "anything") =~
             ~r/^deployex-logs-myhost-\d{8}-\d{6}\.log$/
  end
end
