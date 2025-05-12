defmodule DeployexWeb.Fixture.Binary do
  @moduledoc """
  This module will handle the monitored app binary files
  """

  alias Foundation.Catalog

  def create_bin_files(language \\ "elixir", node)

  def create_bin_files(language, node) when language in ["elixir", "erlang"] do
    %Catalog.Node{name_string: name} = Catalog.node_info(node)

    current = "#{Catalog.current_path(node)}/bin/"
    File.mkdir_p(current)
    File.touch!("#{current}/#{name}")

    new = "#{Catalog.new_path(node)}/bin/"
    File.mkdir_p(new)
    File.touch!("#{new}/#{name}")
  end

  def create_bin_files("gleam", node) do
    current = "#{Catalog.current_path(node)}/erlang-shipment"
    File.mkdir_p(current)

    new = "#{Catalog.new_path(node)}/erlang-shipment"
    File.mkdir_p(new)
  end

  def remove_bin_files(node) do
    %Catalog.Node{name_string: name} = Catalog.node_info(node)

    File.rm_rf("#{Catalog.current_path(node)}/bin/#{name}")
    File.rm_rf("#{Catalog.new_path(node)}/bin/#{name}")
  end
end
