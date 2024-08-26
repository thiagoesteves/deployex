defmodule Deployex.Fixture.Binary do
  @moduledoc """
  This module will handle the monitored app binary files
  """

  alias Deployex.Storage

  def create_bin_files(instance) do
    current = "#{Storage.current_path(instance)}/bin/"
    File.mkdir_p(current)
    File.touch!("#{current}/#{Storage.monitored_app()}")

    new = "#{Storage.new_path(instance)}/bin/"
    File.mkdir_p(new)
    File.touch!("#{new}/#{Storage.monitored_app()}")
  end

  def remove_bin_files(instance) do
    File.rm_rf("#{Storage.current_path(instance)}/bin/#{Storage.monitored_app()}")
    File.rm_rf("#{Storage.new_path(instance)}/bin/#{Storage.monitored_app()}")
  end
end
