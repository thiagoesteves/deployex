defmodule Deployer.Upgrade.Adapter do
  @moduledoc """
  Behaviour that defines the upgrade adapter callback
  """

  @callback connect(node()) :: {:error, :not_connecting} | {:ok, node()}
  @callback check(Deployer.Upgrade.Check.t()) ::
              {:ok, :full_deployment | :hot_upgrade} | {:error, any()}
  @callback execute(Deployer.Upgrade.Data.t()) :: :ok | {:error, any()}
end
