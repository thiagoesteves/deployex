defmodule Foundation.Catalog.Config do
  @moduledoc """
  Structure to handle the deployex configuration
  """
  @type t :: %__MODULE__{mode: :manual | :automatic, manual_version: map() | nil}

  @derive Jason.Encoder

  defstruct mode: :automatic,
            manual_version: nil
end
