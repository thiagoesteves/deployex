defmodule Foundation.Catalog.Sname do
  @moduledoc """
  Structure to handle the sname information
  """
  @type t :: %__MODULE__{
          name: String.t() | nil,
          sname: String.t() | nil,
          suffix: String.t(),
          language: String.t(),
          node: node() | nil
        }

  @derive Jason.Encoder

  defstruct name: nil,
            sname: nil,
            suffix: "",
            language: "",
            node: nil
end
