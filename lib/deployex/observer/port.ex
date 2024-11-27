defmodule Deployex.Observer.Port do
  @moduledoc """
  Retrieve Port information
  """

  alias Deployex.Rpc

  @doc """
  Return port information

  ## Examples

    iex> alias Deployex.Observer.Port
    ...> [h | _] = :erlang.ports()
    ...> assert %{connected: _, id: _, name: _, os_pid: _} = Port.info(h)
    ...> assert :undefined = Port.info(nil)
  """
  @spec info(atom(), port()) ::
          :undefined | %{connected: any(), id: any(), name: any(), os_pid: any()}
  def info(node \\ Node.self(), port)

  def info(node, port) when is_port(port) do
    case Rpc.call(node, :erlang, :port_info, [port], :infinity) do
      data when is_list(data) ->
        %{
          name: Keyword.get(data, :name, 0),
          id: Keyword.get(data, :id, 0),
          connected: Keyword.get(data, :connected, 0),
          os_pid: Keyword.get(data, :os_pid, 0)
        }

      _ ->
        :undefined
    end
  end

  def info(_node, _port), do: :undefined
end
