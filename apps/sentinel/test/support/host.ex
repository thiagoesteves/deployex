defmodule Sentinel.Fixture.Host do
  @moduledoc """
  This module will provide Host Memory Fixtures
  """

  alias Host.Memory

  def send_update_sys_info_message(pid, source_node, memory_free, memory_total) do
    message = %Memory{
      source_node: source_node,
      memory_free: memory_free,
      memory_total: memory_total
    }

    send(pid, {:update_system_info, message})
  end
end
