defmodule Deployer.HotUpgrade.Check do
  @moduledoc """
  Structure to handle the upgrade check data
  """

  alias Deployer.HotUpgrade.Jellyfish

  @type t :: %__MODULE__{
          sname: String.t() | nil,
          name: String.t() | nil,
          language: String.t() | nil,
          download_path: String.t() | nil,
          current_path: String.t() | nil,
          new_path: String.t() | nil,
          from_version: binary() | charlist() | nil,
          to_version: binary() | charlist() | nil,
          deploy: :hot_upgrade | :full_deployment,
          jellyfish_info: list(Jellyfish.t())
        }

  @derive Jason.Encoder

  defstruct sname: nil,
            name: nil,
            language: nil,
            download_path: nil,
            current_path: nil,
            new_path: nil,
            from_version: nil,
            to_version: nil,
            deploy: :full_deployment,
            jellyfish_info: []
end
