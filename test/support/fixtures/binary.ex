defmodule Deployex.Fixture.Binary do
  @moduledoc """
  This module will handle the monitored app binary files
  """

  alias Deployex.Storage

  def create_bin_files(language \\ "elixir", instance)

  def create_bin_files(language, instance) when language in ["elixir", "erlang"] do
    current = "#{Storage.current_path(instance)}/bin/"
    File.mkdir_p(current)
    File.touch!("#{current}/#{Storage.monitored_app_name()}")

    new = "#{Storage.new_path(instance)}/bin/"
    File.mkdir_p(new)
    File.touch!("#{new}/#{Storage.monitored_app_name()}")
  end

  def create_bin_files("gleam", instance) do
    current = "#{Storage.current_path(instance)}/erlang-shipment"
    File.mkdir_p(current)

    new = "#{Storage.new_path(instance)}/erlang-shipment"
    File.mkdir_p(new)
  end

  def remove_bin_files(instance) do
    File.rm_rf("#{Storage.current_path(instance)}/bin/#{Storage.monitored_app_name()}")
    File.rm_rf("#{Storage.new_path(instance)}/bin/#{Storage.monitored_app_name()}")
  end
end
