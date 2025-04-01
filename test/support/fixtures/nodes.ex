defmodule Deployex.Fixture.Nodes do
  @moduledoc """
  This module will handle the nodes
  """

  def test_node(instance, app_name \\ "testapp") do
    {:ok, hostname} = :inet.gethostname()

    "#{app_name}-#{instance}@#{hostname}"
  end
end
