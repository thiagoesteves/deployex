defmodule Deployex.Fixture.Storage do
  @moduledoc """
  This module will handle the storage functions for testing purpose
  """

  alias Deployex.AppConfig

  def cleanup do
    Application.get_env(:deployex, :base_path) |> File.rm_rf()

    # Remove any current.json file
    monitored_app = AppConfig.monitored_app()
    current_json_dir = "/tmp/#{monitored_app}/versions/#{monitored_app}/local"
    File.rm_rf(current_json_dir)

    AppConfig.init()
  end

  def create_current_json(map \\ %{version: "1.0.0", hash: "local"}) do
    monitored_app = AppConfig.monitored_app()
    current_json_dir = "/tmp/#{monitored_app}/versions/#{monitored_app}/local"
    file = Jason.encode!(map)
    File.mkdir_p(current_json_dir)
    File.write("#{current_json_dir}/current.json", file)
  end
end
