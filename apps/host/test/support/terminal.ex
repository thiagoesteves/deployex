defmodule Host.Fixture.Terminal do
  @moduledoc """
  This module will handle the terminal functions for testing purpose
  """

  alias Host.Terminal

  def terminate_all do
    Supervisor.which_children(Terminal.Supervisor)
    |> Enum.each(fn {_id, child, _type, _modules} ->
      Terminal.async_terminate(child)
    end)
  end
end
