defmodule Deployer.Fixture.Files do
  @moduledoc """
  This module will handle the creation of files to allow proper testing
  """

  alias Foundation.Catalog

  def create_bin_files(language \\ "elixir", sname)

  def create_bin_files(language, sname) when language in ["elixir", "erlang"] do
    %{name: name} = Catalog.sname_info(sname)

    current = "#{Catalog.current_path(sname)}/bin/"
    File.mkdir_p(current)
    File.touch!("#{current}/#{name}")

    new = "#{Catalog.new_path(sname)}/bin/"
    File.mkdir_p(new)
    File.touch!("#{new}/#{name}")
  end

  def create_bin_files("gleam", sname) do
    current = "#{Catalog.current_path(sname)}/erlang-shipment"
    File.mkdir_p(current)

    new = "#{Catalog.new_path(sname)}/erlang-shipment"
    File.mkdir_p(new)
  end

  def create_log_files(sname) do
    sname |> Catalog.stdout_path() |> Path.dirname() |> String.trim() |> File.mkdir_p()

    sname |> Catalog.stdout_path() |> File.touch!()
    sname |> Catalog.stderr_path() |> File.touch!()
  end

  def remove_bin_files(sname) do
    %{name: name} = Catalog.sname_info(sname)

    File.rm_rf("#{Catalog.current_path(sname)}/bin/#{name}")
    File.rm_rf("#{Catalog.new_path(sname)}/bin/#{name}")
  end
end
