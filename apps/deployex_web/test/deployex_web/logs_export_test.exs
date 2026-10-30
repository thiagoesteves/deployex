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
      {from, to} = options[:between]
      send(test_pid, {:read, asked, type, from, to})

      case {asked, type} do
        {^sname, "stdout"} -> [message("first", 40), message("second\nthird", 20)]
        {"deployex", "stderr"} -> [message("[error] boom", 30)]
        _other -> []
      end
      |> Enum.filter(&(&1.timestamp >= from and &1.timestamp < to))
    end)

    %{sname: sname}
  end

  defp message(log, seconds_ago),
    do: %Message{timestamp: System.os_time(:millisecond) - seconds_ago * 1_000, log: log}

  defp lines(params), do: params |> LogsExport.chunks() |> Enum.concat()

  # The time windows read for a source and stream, oldest first
  defp windows(sname, type, acc \\ []) do
    receive do
      {:read, ^sname, ^type, from, to} -> windows(sname, type, [{from, to} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "params keeps what is set, for an export link" do
    assert LogsExport.params(%{sources: ["a", "b"], types: ["stdout"], minutes: 60, filter: ""}) ==
             [source: "a,b", stream: "stdout", minutes: 60]

    assert LogsExport.params(%{sources: ["a"], types: [], since: 1_700_000_000, filter: "boom"}) ==
             [source: "a", since: 1_700_000_000, filter: "boom"]
  end

  test "lines reads every source and stream asked, oldest first, split on new lines", %{
    sname: sname
  } do
    lines = lines(%{"source" => "#{sname},deployex", "minutes" => "15"})

    assert Enum.map(lines, &{&1.source, &1.stream, &1.text}) == [
             {sname, "stdout", "first"},
             {"deployex", "stderr", "[error] boom"},
             {sname, "stdout", "second"},
             {sname, "stdout", "third"}
           ]

    # One read a minute, from 15 minutes ago until now
    windows = windows(sname, "stdout")
    assert length(windows) in 15..16
    assert_in_delta elem(hd(windows), 0), System.os_time(:millisecond) - 15 * 60_000, 1_000

    assert Enum.all?(Enum.zip(windows, tl(windows)), fn {{_from, to}, {next, _to}} ->
             to == next
           end)
  end

  test "lines keeps the streams and the filter asked", %{sname: sname} do
    assert [%{text: "[error] boom"}] =
             lines(%{"source" => "#{sname},deployex", "stream" => "stderr"})

    assert [%{text: "third"}] =
             lines(%{"source" => "#{sname},deployex", "filter" => "THIRD"})

    # The filter also matches the source
    assert [%{source: "deployex"}] =
             lines(%{"source" => "#{sname},deployex", "filter" => "deployex"})
  end

  test "lines reads no source this host does not have" do
    assert lines(%{"source" => "other-abc123,../etc"}) == []
    refute_received {:read, _sname, _type, _from, _to}
  end

  test "lines reads the minutes since a time, within a week", %{sname: sname} do
    read = fn params ->
      lines(Map.merge(%{"source" => sname, "stream" => "stdout"}, params))
      length(windows(sname, "stdout"))
    end

    since = System.os_time(:second) - 10 * 60
    assert read.(%{"since" => to_string(since)}) in 11..12
    assert read.(%{"since" => "0"}) in 10_080..10_081
    assert read.(%{"minutes" => "99999"}) in 10_080..10_081
    assert read.(%{"minutes" => "soon"}) in 60..61
    assert read.(%{"since" => "soon"}) in 60..61
  end

  test "lines holds this host's events when the events source is asked" do
    Foundation.Notifications.notify("crash_restart", %{
      sname: "export-test-abc",
      crash_restart_count: 2
    })

    Process.sleep(50)

    lines = lines(%{"source" => "events", "filter" => "export-test-abc"})

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
