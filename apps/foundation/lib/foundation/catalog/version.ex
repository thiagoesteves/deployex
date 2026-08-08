defmodule Foundation.Catalog.Version do
  @moduledoc """
  Structure to handle the application version

  A record is written when a deployment starts and updated once its outcome is known, so
  `id` identifies it across both writes. The two deployment types learn their outcome at
  different points: a hot upgrade knows it as soon as `install_release/2` returns, while a
  full deployment only knows it when the node reports running and the rollback timer is
  cancelled, so it is stored as `:started` until then.

  Records written by earlier versions do not carry the newer fields. They are normalised on
  read (see `Foundation.Catalog.Local`), which matters because DeployEx hot upgrades itself
  and immediately reads the history it wrote before the upgrade.
  """
  @type outcome :: :started | :ok | :rolled_back | :error

  @type t :: %__MODULE__{
          id: String.t() | nil,
          version: String.t() | nil,
          from_version: String.t() | nil,
          hash: String.t() | nil,
          pre_commands: list(),
          name: String.t(),
          sname: String.t(),
          deployment: :full_deployment | :hot_upgrade,
          outcome: outcome() | nil,
          duration_ms: non_neg_integer() | nil,
          inserted_at: NaiveDateTime.t() | nil
        }

  @derive Jason.Encoder

  defstruct id: nil,
            version: nil,
            from_version: nil,
            hash: nil,
            pre_commands: [],
            name: "",
            sname: "",
            deployment: :full_deployment,
            outcome: nil,
            duration_ms: nil,
            inserted_at: nil
end
