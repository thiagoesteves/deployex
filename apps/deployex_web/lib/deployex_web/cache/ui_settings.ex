defmodule DeployexWeb.Cache.UiSettings do
  @moduledoc false

  alias DeployexWeb.Cache

  @key :ui_settings

  @type t :: %__MODULE__{
          nav_menu_collapsed: boolean()
        }

  defstruct nav_menu_collapsed: true

  def get, do: Cache.get(@key) || %__MODULE__{}

  def set(%__MODULE__{} = data), do: Cache.set(@key, data)
end
