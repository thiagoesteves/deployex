defmodule DeployexWeb.HostInfo do
  @moduledoc """
  `on_mount` hook that keeps this host's latest reading in the `:host_info` assign, so the top bar shows
  the host CPU and memory on every page.

  It handles the `Host.Info` broadcasts itself, so a LiveView does not subscribe to them.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  @one_gigabyte 1_073_741_824

  def on_mount(:default, _params, _session, socket) do
    socket = assign(socket, :host_info, Host.Info.latest())

    if connected?(socket) do
      Host.Info.subscribe()
      {:cont, attach_hook(socket, :host_info, :handle_info, &__MODULE__.handle_host_info/2)}
    else
      {:cont, socket}
    end
  end

  # An external capture, so a hot upgrade of this module does not break the hook in a running LiveView.
  # Connected DeployEx peers share the PubSub, so a reading from another host is dropped.
  @doc false
  def handle_host_info(
        {:update_system_info, %Host.Info{source_node: source_node} = host_info},
        socket
      ) do
    if source_node == Node.self() do
      {:halt, assign(socket, :host_info, host_info)}
    else
      {:halt, socket}
    end
  end

  def handle_host_info(_message, socket), do: {:cont, socket}

  @doc """
  Returns the host CPU use as a percentage of all cores, or nil without a reading.
  """
  @spec cpu_percent(Host.Info.t() | nil) :: non_neg_integer() | nil
  def cpu_percent(%Host.Info{cpu: cpu, cpus: cpus})
      when is_number(cpu) and is_integer(cpus) and cpus > 0,
      do: trunc(cpu / (cpus * 100) * 100)

  def cpu_percent(_host_info), do: nil

  @doc """
  Returns the host memory in use as a percentage, or nil without a reading.
  """
  @spec memory_percent(Host.Info.t() | nil) :: non_neg_integer() | nil
  def memory_percent(%Host.Info{memory_total: total, memory_free: free})
      when is_integer(total) and total > 0 and is_integer(free),
      do: trunc((total - free) / total * 100)

  def memory_percent(_host_info), do: nil

  @doc """
  Returns the number of cores, like "2 cores", or nil without a reading.
  """
  @spec cores(Host.Info.t() | nil) :: String.t() | nil
  def cores(%Host.Info{cpus: 1}), do: "1 core"
  def cores(%Host.Info{cpus: cpus}) when is_integer(cpus) and cpus > 1, do: "#{cpus} cores"
  def cores(_host_info), do: nil

  @doc """
  Returns the total memory, like "7.6 GB", or nil without a reading.
  """
  @spec memory_total(Host.Info.t() | nil) :: String.t() | nil
  def memory_total(%Host.Info{memory_total: total}) when is_integer(total) and total > 0,
    do: "#{:erlang.float_to_binary(total / @one_gigabyte, decimals: 1)} GB"

  def memory_total(_host_info), do: nil
end
