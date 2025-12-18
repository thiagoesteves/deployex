defmodule Deployer.HotUpgrade.Adapter do
  @moduledoc """
  Behaviour that defines the upgrade adapter callback
  """

  @callback connect(node()) :: {:error, :not_connecting} | {:ok, node()}
  @callback prepare_new_path(String.t(), String.t(), String.t(), String.t()) :: :ok
  @callback check(Deployer.HotUpgrade.Check.t()) ::
              {:ok, Deployer.HotUpgrade.Check.t()} | {:error, any()}
  @callback execute(Deployer.HotUpgrade.Execute.t()) :: :ok | {:error, any()}
  @callback subscribe_events() :: :ok
end
