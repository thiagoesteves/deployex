defmodule Foundation.Fixture.Catalog do
  @moduledoc """
  This module will handle the catalog functions for testing purpose
  """

  alias Foundation.Catalog

  def cleanup do
    Application.get_env(:foundation, :base_path) |> File.rm_rf()

    # Remove any current.json file
    # monitored_app = Catalog.monitored_app_name()
    # current_json_dir = "/tmp/#{monitored_app}/versions/#{monitored_app}/local"
    # File.rm_rf(current_json_dir)

    Catalog.setup()
  end

  def create_current_json(name, map \\ %{version: "1.0.0", hash: "local"}) do
    bucket = Application.fetch_env!(:deployer, Deployer.Release)[:bucket]
    current_json_dir = "#{bucket}/versions/#{name}/local"
    file = Jason.encode!(map)
    File.mkdir_p(current_json_dir)
    File.write("#{current_json_dir}/current.json", file)
  end
end
