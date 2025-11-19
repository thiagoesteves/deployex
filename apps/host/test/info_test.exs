defmodule Host.InfoTest do
  use ExUnit.Case, async: false

  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  alias Foundation.Common
  alias Host.Info.Server, as: InfoServer
  alias Host.Info.Uptime

  test "start_link/1 for Windows (Not Implemented yet)" do
    name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

    assert {:ok, _pid} = InfoServer.start_link(name: name, update_info_interval: 100)
  end

  test "System Info Notification for Linux" do
    name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()
    os_description = "20.04.6 LTS (Focal Fossa)"

    Host.CommanderMock
    |> stub(:os_type, fn -> {:unix, :linux} end)
    |> stub(:run, fn
      "free -b", [:stdout, :sync] ->
        {:ok,
         [
           {:stdout,
            [
              """
                            total        used        free      shared  buff/cache   available
              Mem:     2055806976   503697408   189964288    79347712  1362145280  1263837184
              Swap:             0           0           0
              """
            ]}
         ]}

      "nproc", [:stdout, :sync] ->
        {:ok, [{:stdout, ["2"]}]}

      "cat /proc/uptime", [:stdout, :sync] ->
        {:ok, [{:stdout, ["1297530.82 2541802.52"]}]}

      "ps -eo pcpu", [:stdout, :sync] ->
        {:ok,
         [
           {:stdout,
            [
              """
              %CPU
               0.0
               0.2
               0.3
               0.4
               0.5
               0.0
               20.0
               10.0
              """
            ]}
         ]}

      "cat /etc/os-release | grep VERSION= | sed 's/VERSION=//; s/\"//g'", [:stdout, :sync] ->
        {:ok, [{:stdout, [os_description]}]}
    end)

    assert {:ok, _pid} = InfoServer.start_link(name: name, update_info_interval: 100)

    InfoServer.subscribe()

    assert_receive {:update_system_info,
                    %Host.Info{
                      host: "Linux",
                      description: ^os_description,
                      memory_free: 1_263_837_184,
                      memory_total: 2_055_806_976,
                      uptime: "15 days",
                      cpu: 31.4,
                      cpus: 2
                    }},
                   1_000
  end

  test "System Info Notification for Linux when commands fail" do
    name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

    Host.CommanderMock
    |> stub(:os_type, fn -> {:unix, :linux} end)
    |> stub(:run, fn _, [:stdout, :sync] -> {:error, "any"} end)

    assert {:ok, _pid} = InfoServer.start_link(name: name, update_info_interval: 100)

    InfoServer.subscribe()

    assert_receive {:update_system_info,
                    %Host.Info{
                      host: "Linux",
                      description: nil,
                      memory_free: nil,
                      memory_total: nil,
                      uptime: nil,
                      cpu: nil,
                      cpus: nil
                    }},
                   1_000
  end

  test "System Info Notification for Linux with invalid value in the cpu_sum text" do
    name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()
    os_description = "20.04.6 LTS (Focal Fossa)"

    Host.CommanderMock
    |> stub(:os_type, fn -> {:unix, :linux} end)
    |> stub(:run, fn
      "free -b", [:stdout, :sync] ->
        {:ok,
         [
           {:stdout,
            [
              """
                            total        used        free      shared  buff/cache   available
              Mem:     2055806976   503697408   189964288    79347712  1362145280  1263837184
              Swap:             0           0           0
              """
            ]}
         ]}

      "nproc", [:stdout, :sync] ->
        {:ok, [{:stdout, ["2"]}]}

      "cat /proc/uptime", [:stdout, :sync] ->
        {:ok, [{:stdout, ["1297530.82 2541802.52"]}]}

      "ps -eo pcpu", [:stdout, :sync] ->
        {:ok,
         [
           {:stdout,
            [
              """
              %CPU
               aa
               20.0
               10.0
              """
            ]}
         ]}

      "cat /etc/os-release | grep VERSION= | sed 's/VERSION=//; s/\"//g'", [:stdout, :sync] ->
        {:ok, [{:stdout, [os_description]}]}
    end)

    assert {:ok, _pid} = InfoServer.start_link(name: name, update_info_interval: 100)

    InfoServer.subscribe()

    assert_receive {:update_system_info,
                    %Host.Info{
                      host: "Linux",
                      description: ^os_description,
                      memory_free: 1_263_837_184,
                      memory_total: 2_055_806_976,
                      uptime: "15 days",
                      cpu: 30.0,
                      cpus: 2
                    }},
                   1_000
  end

  test "System Info Notification for MacOs" do
    name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()
    os_description = "15.1.1"

    Host.CommanderMock
    |> stub(:os_type, fn -> {:unix, :darwin} end)
    |> stub(:run, fn
      "vm_stat", [:stdout, :sync] ->
        {:ok,
         [
           {:stdout,
            [
              """
              Mach Virtual Memory Statistics: (page size of 16384 bytes)
              Pages free:                             1049897.
              Pages active:                           1471448.
              Pages inactive:                         1128758.
              Pages speculative:                       341829.
              Pages throttled:                              0.
              Pages wired down:                        145772.
              Pages purgeable:                          62998.
              "Translation faults":                 691609135.
              """
            ]}
         ]}

      "sysctl -n hw.memsize", [:stdout, :sync] ->
        {:ok, [{:stdout, ["68719476736"]}]}

      "sysctl -n hw.ncpu", [:stdout, :sync] ->
        {:ok, [{:stdout, ["5"]}]}

      "sysctl -n kern.boottime", [:stdout, :sync] ->
        {:ok, [{:stdout, ["{ sec = 1763120949, usec = 862073 } ", "Fri Nov 14 08:49:09 2025\n"]}]}

      "ps -A -o %cpu", [:stdout, :sync] ->
        {:ok,
         [
           {:stdout,
            [
              """
              %CPU
               0.0
               0.2
               0.3
               0.4
               0.5
               0.0
               200.0
               10.0
              """
            ]}
         ]}

      "sw_vers -productVersion", [:stdout, :sync] ->
        {:ok, [{:stdout, [os_description]}]}
    end)

    assert {:ok, _pid} = InfoServer.start_link(name: name, update_info_interval: 100)

    InfoServer.subscribe()

    assert_receive {:update_system_info,
                    %Host.Info{
                      host: "macOS",
                      description: ^os_description,
                      memory_free: 17_201_512_448,
                      memory_total: 68_719_476_736,
                      uptime: _,
                      cpu: 211.4,
                      cpus: 5
                    }},
                   1_000
  end

  test "System Info Notification for MacOs when commands fail" do
    name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

    Host.CommanderMock
    |> stub(:os_type, fn -> {:unix, :darwin} end)
    |> stub(:run, fn _, [:stdout, :sync] -> {:error, "any"} end)

    assert {:ok, _pid} = InfoServer.start_link(name: name, update_info_interval: 100)

    InfoServer.subscribe()

    assert_receive {:update_system_info,
                    %Host.Info{
                      host: "macOS",
                      description: nil,
                      memory_free: nil,
                      memory_total: nil,
                      uptime: nil,
                      cpu: nil,
                      cpus: nil
                    }},
                   1_000
  end

  test "System Info Notification for Windows" do
    name = "#{__MODULE__}-#{Common.random_small_alphanum()}" |> String.to_atom()

    Host.CommanderMock
    |> stub(:os_type, fn -> {:win32, :any} end)

    assert {:ok, _pid} = InfoServer.start_link(name: name, update_info_interval: 100)

    InfoServer.subscribe()

    assert_receive {:update_system_info, %Host.Info{host: "Windows"}}, 1_000
  end

  test "Host Uptime variations" do
    Host.CommanderMock
    |> stub(:run, fn "cat /proc/uptime", [:stdout, :sync] ->
      called = Process.get("run", 0)
      Process.put("run", called + 1)

      case called do
        0 ->
          {:ok, [{:stdout, ["1.0 2.0"]}]}

        1 ->
          {:ok, [{:stdout, ["3.0 6.0"]}]}

        2 ->
          {:ok, [{:stdout, ["60.0 120.0"]}]}

        3 ->
          {:ok, [{:stdout, ["180.0 360.0"]}]}

        4 ->
          {:ok, [{:stdout, ["3600.0 7200.0"]}]}

        5 ->
          {:ok, [{:stdout, ["10800.0 21600.0"]}]}

        6 ->
          {:ok, [{:stdout, ["86400.0 172800.0"]}]}

        7 ->
          {:ok, [{:stdout, ["1296000.0 2592000.0"]}]}
      end
    end)

    assert %{uptime: "1 second"} = Uptime.get_linux()
    assert %{uptime: "3 seconds"} = Uptime.get_linux()
    assert %{uptime: "1 minute"} = Uptime.get_linux()
    assert %{uptime: "3 minutes"} = Uptime.get_linux()
    assert %{uptime: "1 hour"} = Uptime.get_linux()
    assert %{uptime: "3 hours"} = Uptime.get_linux()
    assert %{uptime: "1 day"} = Uptime.get_linux()
    assert %{uptime: "15 days"} = Uptime.get_linux()
  end
end
