defmodule Deployer.SelfUpgrade.Source.Adapter do
  @moduledoc "Behaviour for reading the desired DeployEx version published by IaC."

  @callback desired_version() :: {:ok, String.t()} | :none | {:error, any()}
end
