defmodule Host.Info.MemoryTest do
  use ExUnit.Case, async: false

  import Mox

  alias Host.Info.Memory

  setup :set_mox_global
  setup :verify_on_exit!

  # vm_stat from a 16 GB Mac where Activity Monitor shows about 12.8 GB of memory used
  @vm_stat """
  Mach Virtual Memory Statistics: (page size of 16384 bytes)
  Pages free:                                4426.
  Pages active:                            257344.
  Pages inactive:                          256394.
  Pages speculative:                          193.
  Pages throttled:                              0.
  Pages wired down:                        155479.
  Pages purgeable:                           1693.
  "Translation faults":               24477642413.
  Pages copy-on-write:                 1436612402.
  File-backed pages:                       161163.
  Anonymous pages:                         352768.
  Pages stored in compressor:             1096803.
  Pages occupied by compressor:            334904.
  """

  defp stub_macos(vm_stat, memsize \\ "17179869184\n") do
    stub(Host.CommanderMock, :run, fn
      "vm_stat", [:stdout, :sync] -> {:ok, [{:stdout, [vm_stat]}]}
      "sysctl -n hw.memsize", [:stdout, :sync] -> {:ok, [{:stdout, [memsize]}]}
    end)
  end

  test "macOS counts app memory, wired and compressed pages as used, like Activity Monitor" do
    stub_macos(@vm_stat)

    # (352,768 - 1,693 + 155,479 + 334,904) pages of 16 KB are in use, 80% of 16 GB
    assert %Memory{memory_total: 17_179_869_184, memory_free: 3_393_421_312} = Memory.get_macos()
  end

  test "macOS has no free memory below zero" do
    stub_macos(@vm_stat, "1000\n")
    assert %Memory{memory_free: 0} = Memory.get_macos()
  end

  test "macOS reads nothing from output it does not know" do
    stub_macos("no header\nPages free: 10.\n")
    assert %Memory{memory_total: nil, memory_free: nil} = Memory.get_macos()

    stub_macos(@vm_stat, "not a number")
    assert %Memory{memory_total: nil} = Memory.get_macos()
  end
end
