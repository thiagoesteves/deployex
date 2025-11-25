defmodule Deployer.HotUpgrade.Execute do
  @moduledoc """
  Structure to handle the upgrade execute data
  """
  @type t :: %__MODULE__{
          node: atom(),
          sname: String.t() | nil,
          name: String.t() | nil,
          language: String.t() | nil,
          current_path: String.t() | nil,
          new_path: String.t() | nil,
          from_version: binary() | charlist() | nil,
          to_version: binary() | charlist() | nil,
          make_permanent_async: boolean(),
          sync_execution: boolean(),
          after_asyn_make_permanent: mfa() | nil
        }

  @derive Jason.Encoder

  defstruct node: nil,
            sname: nil,
            name: nil,
            language: nil,
            current_path: nil,
            new_path: nil,
            from_version: nil,
            to_version: nil,
            make_permanent_async: false,
            sync_execution: true,
            after_asyn_make_permanent: nil
end
