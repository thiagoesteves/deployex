defmodule Deployex.Fixture.Storage do
  @moduledoc """
  This module will handle the storage functions for testing purpose
  """

  def cleanup do
    Application.get_env(:deployex, :base_path) |> File.rm_rf()
    Deployex.AppConfig.init()
  end
end
