defmodule Deployex.OpSys.Local do
  @moduledoc """
    This module implements the operational system adapter, linking system
    functions to their respective functions and/or libraries.
  """

  @behaviour Deployex.OpSys.Adapter

  ### ==========================================================================
  ### OpSys Callbacks
  ### ==========================================================================
  @impl true
  def run_link(command, options), do: :exec.run_link(command, options)

  @impl true
  def run(command, options), do: :exec.run(command, options)

  @impl true
  def stop(process_pid), do: :exec.stop(process_pid)

  @impl true
  def send(process_pid, message), do: :exec.send(process_pid, message)

  @impl true
  def os_type, do: :os.type()
end
