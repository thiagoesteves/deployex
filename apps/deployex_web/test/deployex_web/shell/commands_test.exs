defmodule DeployexWeb.Shell.CommandsTest do
  use ExUnit.Case, async: false

  alias DeployexWeb.Shell.Commands
  alias Foundation.Catalog

  # The command checks that the instance has a release on the host
  defp with_release(name) do
    sname = Catalog.create_sname(name)
    bin_path = Catalog.bin_path(sname, :current)
    File.mkdir_p!(Path.dirname(bin_path))
    File.touch!(bin_path)
    on_exit(fn -> File.rm(bin_path) end)
    sname
  end

  test "an Elixir instance gets an IEx shell through its release" do
    sname = with_release("myelixir")

    assert {:ok,
            %{kind: :iex, language: "elixir", command: "bin/myelixir remote", commands: commands}} =
             Commands.build(sname, "id")

    assert commands =~ "export RELEASE_NODE=#{sname}"
    assert commands =~ "remote\n"
  end

  test "an Erlang instance gets an Erlang shell through its release" do
    sname = with_release("myerlang")

    assert {:ok,
            %{
              kind: :erlang_shell,
              language: "erlang",
              command: "bin/myerlang remote_console",
              commands: commands
            }} =
             Commands.build(sname, "id")

    assert commands =~ "export RELX_REPLACE_OS_VARS=true"
  end

  test "a Gleam instance gets an Erlang shell with erl -remsh" do
    sname = with_release("mygleam")

    assert {:ok,
            %{
              kind: :erlang_shell,
              language: "gleam",
              command: "erl -remsh " <> _,
              commands: commands
            }} =
             Commands.build(sname, "id")

    assert commands =~ "erl -remsh #{sname}@"
  end

  test "DeployEx gets an IEx shell through its own release" do
    bin_path = Catalog.bin_path("deployex", :current)
    File.mkdir_p!(Path.dirname(bin_path))
    File.touch!(bin_path)

    assert {:ok, %{kind: :iex, language: "elixir", command: "bin/deployex remote"}} =
             Commands.build("deployex", "id")
  end

  test "the host shell runs tmux, and only it has something to clean up" do
    assert {:ok, %{kind: :host_shell, language: "linux", commands: commands}} =
             Commands.build("host", "abc")

    assert commands =~ "tmux new-session -s DeployEx-abc -d"
    assert Commands.cleanup(%DeployexWeb.Shell.Session{kind: :iex}) == :ok
  end
end
