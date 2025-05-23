defmodule Deployer.Upgrade.Adapter do
  @moduledoc """
  Behaviour that defines the upgrade adapter callback
  """

  @callback connect(node()) :: {:error, :not_connecting} | {:ok, node()}
  @callback prepare_new_path(String.t(), String.t(), String.t(), String.t()) :: :ok
  @callback check(Deployer.Upgrade.Check.t()) ::
              {:ok, :full_deployment | :hot_upgrade} | {:error, any()}
  @callback execute(Deployer.Upgrade.Execute.t()) :: :ok | {:error, any()}
end
