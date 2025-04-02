defmodule Deployex.Fixture.Binary do
  @moduledoc """
  This module will handle the monitored app binary files
  """

  alias Deployex.Catalog

  def create_bin_files(language \\ "elixir", instance)

  def create_bin_files(language, instance) when language in ["elixir", "erlang"] do
    current = "#{Catalog.current_path(instance)}/bin/"
    File.mkdir_p(current)
    File.touch!("#{current}/#{Catalog.monitored_app_name()}")

    new = "#{Catalog.new_path(instance)}/bin/"
    File.mkdir_p(new)
    File.touch!("#{new}/#{Catalog.monitored_app_name()}")
  end

  def create_bin_files("gleam", instance) do
    current = "#{Catalog.current_path(instance)}/erlang-shipment"
    File.mkdir_p(current)

    new = "#{Catalog.new_path(instance)}/erlang-shipment"
    File.mkdir_p(new)
  end

  def remove_bin_files(instance) do
    File.rm_rf("#{Catalog.current_path(instance)}/bin/#{Catalog.monitored_app_name()}")
    File.rm_rf("#{Catalog.new_path(instance)}/bin/#{Catalog.monitored_app_name()}")
  end
end
