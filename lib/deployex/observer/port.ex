defmodule Deployex.Observer.Port do
  @moduledoc """
  Port handling.
  """

  @spec info(port()) :: :error | %{connected: any(), id: any(), name: any(), os_pid: any()}
  def info(port) do
    case :erlang.port_info(port) do
      :undefined ->
        :error

      data ->
        %{
          name: Keyword.get(data, :name, 0),
          id: Keyword.get(data, :id, 0),
          connected: Keyword.get(data, :connected, 0),
          os_pid: Keyword.get(data, :os_pid, 0)
        }
    end
  end
end
