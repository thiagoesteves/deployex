defmodule Deployex.Fixture.Terminal do
  @moduledoc """
  This module will handle the terminal functions for testing purpose
  """

  alias Deployex.Terminal

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
