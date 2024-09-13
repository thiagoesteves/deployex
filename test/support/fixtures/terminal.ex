defmodule Deployex.Fixture.Terminal do
  @moduledoc """
  This module will handle the terminal functions for testing purpose
  """

  alias Deployex.Terminal.Server
  alias Deployex.Terminal.Supervisor, as: TerminalSup

  def terminate_all do
    Supervisor.which_children(TerminalSup)
    |> Enum.each(fn {_id, child, _type, _modules} ->
      Server.async_terminate(child)
    end)
  end

  def list_children do
    Supervisor.which_children(TerminalSup)
    |> Enum.map(fn {_id, child_pid, _type, _modules} -> child_pid end)
  end
end
