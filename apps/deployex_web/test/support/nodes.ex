defmodule DeployexWeb.Fixture.Nodes do
  @moduledoc """
  This module will handle the nodes
  """

  def test_node(app_name, suffix) do
    {:ok, hostname} = :inet.gethostname()

    :"#{app_name}-#{suffix}@#{hostname}"
  end
end
