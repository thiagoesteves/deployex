defmodule Deployex.Observer.Port do
  @moduledoc """
  Port handling.
  """

  @port_meta [
    :name,
    :id,
    :connected,
    :os_pid
  ]

  def meta(port) do
    port |> port_info(@port_meta, &structure_meta/2)
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp port_info(nil, _, _), do: :error

  defp port_info(port, _information, structurer) do
    case :erlang.port_info(port) do
      :undefined -> :error
      data -> structurer.(data, port)
    end
  end

  # Structurers

  defp structure_meta(data, _port) do
    %{
      name: Keyword.get(data, :name, 0),
      id: Keyword.get(data, :id, 0),
      connected: Keyword.get(data, :connected, 0),
      os_pid: Keyword.get(data, :os_pid, 0)
    }
  end
end
