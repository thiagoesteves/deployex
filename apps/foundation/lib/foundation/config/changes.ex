defmodule Foundation.Config.Changes do
  @moduledoc false

  @type t :: %__MODULE__{
          summary: map() | nil,
          timestamp: DateTime.t(),
          changes_count: non_neg_integer()
        }

  defstruct summary: %{},
            timestamp: DateTime.utc_now(),
            changes_count: 0
end
