defmodule Deployex.Fixture.Binary do
  @moduledoc """
  This module will handle the monitored app binary files
  """

  alias Deployex.AppConfig

  def create_bin_files(instance) do
    current = "#{AppConfig.current_path(instance)}/bin/"
    File.mkdir_p(current)
    File.touch!("#{current}/#{AppConfig.monitored_app()}")

    new = "#{AppConfig.new_path(instance)}/bin/"
    File.mkdir_p(new)
    File.touch!("#{new}/#{AppConfig.monitored_app()}")
  end

  def remove_bin_files(instance) do
    File.rm_rf("#{AppConfig.current_path(instance)}/bin/#{AppConfig.monitored_app()}")
    File.rm_rf("#{AppConfig.new_path(instance)}/bin/#{AppConfig.monitored_app()}")
  end
end
