defmodule Deployex.Fixture.Status do
  @moduledoc """
  This module will handle the status functions for testing purpose
  """

  def version(attrs \\ %{}) do
    %Deployex.Status.Version{
      version: "1.0.0",
      hash: "local",
      pre_commands: [],
      instance: 1,
      deployment: :full_deployment,
      deploy_ref: make_ref(),
      inserted_at: NaiveDateTime.utc_now()
    }
    |> Map.merge(attrs)
  end

  def versions(elements \\ 3, attrs \\ %{}) do
    Enum.map(1..elements, fn index -> version(%{version: "1.0.#{index}"}) end)
    |> Enum.map(&Map.merge(&1, attrs))
  end
end
