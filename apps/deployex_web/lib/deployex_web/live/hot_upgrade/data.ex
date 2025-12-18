defmodule DeployexWeb.HotUpgrade.Data do
  @moduledoc """
  Structure to handle the hotupgrade data
  """
  @type t :: %__MODULE__{
          name: String.t() | nil,
          download_path: String.t() | nil,
          filename: String.t() | nil,
          size: non_neg_integer(),
          from_version: binary() | charlist() | nil,
          to_version: binary() | charlist() | nil,
          sha256: String.t(),
          jellyfish_info: map() | nil,
          error: String.t() | nil
        }

  @derive Jason.Encoder

  defstruct name: "deployex",
            download_path: nil,
            filename: nil,
            size: 0,
            from_version: nil,
            to_version: nil,
            sha256: nil,
            jellyfish_info: nil,
            error: nil
end
