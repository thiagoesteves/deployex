defmodule Deployex.Common do
  @moduledoc """
  This module contains functions to be shared among other modules
  """

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  Return the short ref
  """
  @spec short_ref(reference()) :: String.t()
  def short_ref(reference) do
    String.slice(inspect(reference), -6..-2)
  end

  @doc """
  This function calls gen_server with try catch

  NOTE: This function needs to use try/catch because rescue (suggested by credo)
        doesn't handle :exit
  """
  @spec call_gen_server(pid() | map(), any()) :: {:ok, any()} | {:error, :rescued}
  def call_gen_server(pid_or_global_name, message) when is_pid(pid_or_global_name) do
    try do
      GenServer.call(pid_or_global_name, message)
    catch
      _, _ ->
        {:error, :rescued}
    end
  end

  def call_gen_server(pid_or_global_name, message) do
    try do
      GenServer.call({:global, pid_or_global_name}, message)
    catch
      _, _ ->
        {:error, :rescued}
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
