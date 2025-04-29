defmodule Host.MemoryTest do
  use ExUnit.Case, async: false

  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  alias Host.Memory.Server, as: MemoryServer

  test "start_link/1 for Windows (Not Implemented yet)" do
    name = "#{__MODULE__}-001" |> String.to_atom()

    assert {:ok, _pid} = MemoryServer.start_link(name: name, update_info_interval: 100)
  end

  test "System Info Notification for Linux" do
    name = "#{__MODULE__}-002" |> String.to_atom()
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

    assert {:ok, _pid} = MemoryServer.start_link(name: name, update_info_interval: 100)

    MemoryServer.subscribe()

    assert_receive {:update_system_info,
                    %Host.Memory{
                      host: "Linux",
                      description: ^os_description,
                      memory_free: 1_263_837_184,
                      memory_total: 2_055_806_976,
                      cpu: 31.4,
                      cpus: 2
                    }},
                   1_000
  end

  test "System Info Notification for MacOs" do
    name = "#{__MODULE__}-002" |> String.to_atom()
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

    assert {:ok, _pid} = MemoryServer.start_link(name: name, update_info_interval: 100)

    MemoryServer.subscribe()

    assert_receive {:update_system_info,
                    %Host.Memory{
                      host: "macOS",
                      description: ^os_description,
                      memory_free: 17_201_512_448,
                      memory_total: 68_719_476_736,
                      cpu: 211.4,
                      cpus: 5
                    }},
                   1_000
  end
end
