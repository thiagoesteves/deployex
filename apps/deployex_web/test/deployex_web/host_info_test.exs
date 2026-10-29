defmodule DeployexWeb.HostInfoTest do
  use ExUnit.Case, async: true

  alias DeployexWeb.HostInfo
  alias Phoenix.LiveView.Socket

  @gigabyte 1_073_741_824

  describe "on_mount/4" do
    test "assigns the latest reading on the static render" do
      assert {:cont, socket} = HostInfo.on_mount(:default, %{}, %{}, %Socket{})
      assert Map.has_key?(socket.assigns, :host_info)
    end
  end

  describe "cpu_percent/1" do
    test "returns the use of all cores" do
      assert HostInfo.cpu_percent(%Host.Info{cpu: 100, cpus: 4}) == 25
      assert HostInfo.cpu_percent(%Host.Info{cpu: 211.4, cpus: 5}) == 42
    end

    test "returns nil without a reading" do
      assert HostInfo.cpu_percent(nil) == nil
      assert HostInfo.cpu_percent(%Host.Info{cpu: nil, cpus: 4}) == nil
      assert HostInfo.cpu_percent(%Host.Info{cpu: 10, cpus: 0}) == nil
    end
  end

  describe "memory_percent/1" do
    test "returns the memory in use" do
      assert HostInfo.memory_percent(%Host.Info{memory_total: 100, memory_free: 59}) == 41
    end

    test "returns nil without a reading" do
      assert HostInfo.memory_percent(nil) == nil
      assert HostInfo.memory_percent(%Host.Info{memory_total: nil, memory_free: nil}) == nil
      assert HostInfo.memory_percent(%Host.Info{memory_total: 0, memory_free: 0}) == nil
    end
  end

  describe "cores/1 and memory_total/1" do
    test "describe the capacity" do
      assert HostInfo.cores(%Host.Info{cpus: 1}) == "1 core"
      assert HostInfo.cores(%Host.Info{cpus: 8}) == "8 cores"
      assert HostInfo.memory_total(%Host.Info{memory_total: 8 * @gigabyte}) == "8 GB"
      assert HostInfo.memory_total(%Host.Info{memory_total: 68_719_476_736}) == "64 GB"
      # A host with 7.6 GB reads 8 GB
      assert HostInfo.memory_total(%Host.Info{memory_total: round(7.6 * @gigabyte)}) == "8 GB"
    end

    test "return nil without a reading" do
      assert HostInfo.cores(nil) == nil
      assert HostInfo.cores(%Host.Info{cpus: nil}) == nil
      assert HostInfo.memory_total(nil) == nil
      assert HostInfo.memory_total(%Host.Info{memory_total: 0}) == nil
    end
  end
end
