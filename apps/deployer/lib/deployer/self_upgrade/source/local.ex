defmodule Deployer.SelfUpgrade.Source.Local do
  @moduledoc """
  Reads the desired DeployEx version from application config.

  For dev and test. Returns `:none` when no version is configured.
  """

  @behaviour Deployer.SelfUpgrade.Source.Adapter

  @impl true
  @spec desired_version() :: {:ok, String.t()} | :none
  def desired_version do
    case Application.get_env(:deployer, __MODULE__)[:version] do
      nil -> :none
      "" -> :none
      version -> {:ok, to_string(version)}
    end
  end
end
