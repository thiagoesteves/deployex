defmodule Host.Fixture.Terminal do
  @moduledoc """
  This module will handle the terminal functions for testing purpose
  """

  alias Host.Terminal

  @doc """
  Waits until every terminal server has opened its connection and notified its target.

  The connection is opened in a continue, after `Host.Terminal.new/1` has returned, so a test
  that acts on the terminal right after it is created may reach it before it is connected.
  """
  def wait_for_connection do
    Supervisor.which_children(Terminal.Supervisor)
    |> Enum.each(fn {_id, child, _type, _modules} -> :sys.get_state(child) end)
  end

  def terminate_all do
    Supervisor.which_children(Terminal.Supervisor)
    |> Enum.each(fn {_id, child, _type, _modules} ->
      Terminal.async_terminate(child)
    end)
  end

  def list_children do
    Supervisor.which_children(Terminal.Supervisor)
    |> Enum.map(fn {_id, child_pid, _type, _modules} -> child_pid end)
  end
end
