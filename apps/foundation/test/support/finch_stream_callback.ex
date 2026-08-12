defmodule FinchStreamCallback do
  @moduledoc """
  Stands in for the `Foundation.System.FinchStream` callbacks.

  Named functions on purpose. The callbacks are applied through their module so they
  resolve against the code loaded at the time, which is what lets a download survive the
  module that started it being replaced by a hot upgrade.
  """

  @spec notify(pid(), String.t(), any()) :: :ok
  def notify(pid, file_path, status) do
    send(pid, {:notify, file_path, status})
    :ok
  end

  @spec continue(pid(), boolean()) :: boolean()
  def continue(pid, answer) do
    send(pid, :keep_downloading_check)
    answer
  end
end
