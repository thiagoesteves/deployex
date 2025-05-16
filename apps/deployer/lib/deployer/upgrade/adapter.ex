defmodule Deployer.Upgrade.Adapter do
  @moduledoc """
  Behaviour that defines the upgrade adapter callback
  """

  @callback connect(node()) :: {:error, :not_connecting} | {:ok, node()}
  @callback check(
              node(),
              String.t(),
              String.t(),
              binary(),
              binary() | charlist() | nil,
              binary() | charlist()
            ) ::
              {:ok, :full_deployment | :hot_upgrade} | {:error, any()}
  @callback execute(
              node(),
              String.t(),
              String.t(),
              binary() | charlist() | nil,
              binary() | charlist() | nil
            ) ::
              :ok | {:error, any()}
end
