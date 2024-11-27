defmodule Deployex.Observer.Port do
  @moduledoc """
  Retrieve Port information
  """

  @doc """
  Return port information

  ## Examples

    iex> alias Deployex.Observer.Port
    ...> [h | _] = :erlang.ports()
    ...> assert %{connected: _, id: _, name: _, os_pid: _} = Port.info(h)
    ...> assert :undefined = Port.info(nil)
  """
  @spec info(port()) :: :undefined | %{connected: any(), id: any(), name: any(), os_pid: any()}
  def info(port) do
    case :erlang.port_info(port) do
      :undefined ->
        :undefined

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
