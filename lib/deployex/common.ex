defmodule Deployex.Common do
  @moduledoc """
  This module contains functions to be shared among other modules
  """

  @sec_in_minute 60
  @sec_in_hour 3_600
  @sec_in_day 86_400
  @sec_in_months 2_628_000

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  Return the short ref

  ## Examples

    iex> alias Deployex.Common
    ...> ref = make_ref()
    ...> assert String.length(Common.short_ref(ref)) == 5
  """
  @spec short_ref(reference()) :: String.t()
  def short_ref(reference) do
    String.slice(inspect(reference), -6..-2)
  end

  @doc """
  This function converts diff time to string

  ## Examples

    iex> alias Deployex.Common
    ...> start_time = System.monotonic_time() - (:timer.seconds(30) * 1000000)
    ...> assert Common.uptime_to_string(nil) == "-/-"
    ...> assert Common.uptime_to_string(start_time) == "<1m ago"
    ...> start_time = System.monotonic_time() - (:timer.seconds(60) * 1000000)
    ...> assert Common.uptime_to_string(start_time) == "1m ago"
    ...> start_time = System.monotonic_time() - (:timer.hours(1) * 1000000)
    ...> assert Common.uptime_to_string(start_time) == "1h ago"
    ...> start_time = System.monotonic_time() - (:timer.hours(24) * 1000000)
    ...> assert Common.uptime_to_string(start_time) == "1d ago"
    ...> start_time = System.monotonic_time() - (:timer.hours(24 * 35) * 1000000)
    ...> assert Common.uptime_to_string(start_time) == "1m ago"
  """
  def uptime_to_string(nil), do: "-/-"

  def uptime_to_string(start_time) do
    diff = System.convert_time_unit(System.monotonic_time() - start_time, :native, :second)

    case diff do
      uptime when uptime < 10 -> "now"
      uptime when uptime < @sec_in_minute -> "<1m ago"
      uptime when uptime < @sec_in_hour -> "#{trunc(uptime / @sec_in_minute)}m ago"
      uptime when uptime < @sec_in_day -> "#{trunc(uptime / @sec_in_hour)}h ago"
      uptime when uptime <= @sec_in_months -> "#{trunc(uptime / @sec_in_day)}d ago"
      uptime -> "#{trunc(uptime / @sec_in_months)}m ago"
    end
  end

  @doc """
  This function calls gen_server with try catch

  NOTE: This function needs to use try/catch because rescue (suggested by credo)
        doesn't handle :exit

  ## Examples

    iex> alias Deployex.Common
    ...> {:ok, valid_pid} = GenServer.start_link(Deployex.MyGenServer, [])
    ...> invalid_pid = spawn(fn -> :ok end)
    ...> assert Common.call_gen_server(valid_pid, "any-message") == :ok
    ...> assert Common.call_gen_server(invalid_pid, "any-message") == {:error, :rescued}
    ...> {:ok, pid} = GenServer.start_link(Deployex.MyGenServer, [])
    ...> valid_name = %{a: 1}
    ...> assert :yes == :global.register_name(valid_name, pid)
    ...> assert Common.call_gen_server(valid_name, "any-message") == :ok
    ...> assert Common.call_gen_server(%{}, "any-message") == {:error, :rescued}
  """
  @spec call_gen_server(pid() | map() | atom(), any()) :: {:ok, any()} | {:error, :rescued}
  def call_gen_server(key, message) when is_pid(key) or is_atom(key) do
    try do
      GenServer.call(key, message)
    catch
      _, _ ->
        {:error, :rescued}
    end
  end

  def call_gen_server(key, message) do
    try do
      GenServer.call({:global, key}, message)
    catch
      _, _ ->
        {:error, :rescued}
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
