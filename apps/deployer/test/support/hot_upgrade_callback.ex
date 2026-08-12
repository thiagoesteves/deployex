defmodule Deployer.HotUpgrade.TestCallback do
  @moduledoc """
  Stands in for the after make permanent callback.

  It is a named module on purpose. The callback is applied after `install_release` has
  swapped the release in, and a function captured by the previous version of the code does
  not survive that, which is the failure this module keeps the tests honest about.
  """

  @spec notify(pid(), reference()) :: :ok
  def notify(pid, ref) do
    send(pid, {:handle_ref_event, ref})
    :ok
  end

  @spec raise_error(String.t()) :: no_return()
  def raise_error(message), do: raise(message)
end
