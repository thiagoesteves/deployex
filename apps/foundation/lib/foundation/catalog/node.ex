defmodule Foundation.Catalog.Node do
  @moduledoc """
  Structure to handle the Node information
  """
  @type t :: %__MODULE__{
          node: node() | nil,
          sname: String.t(),
          name: String.t(),
          hostname: String.t(),
          suffix: String.t(),
          language: String.t()
        }

  @derive Jason.Encoder

  defstruct node: nil,
            sname: "",
            name: "",
            hostname: "",
            suffix: "",
            language: "elixir"
end
