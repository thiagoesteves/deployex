defmodule Deployer.Status.LogoTest do
  use ExUnit.Case, async: false

  import Mox

  alias Deployer.Status.Logo

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  @node :"myelixir-abc123@nohost"
  @name "myelixir"
  @app :myelixir
  @priv_dir ~c"/opt/myelixir/lib/myelixir-1.0.0/priv"
  @svg ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"></svg>)

  test "image/2 returns the logo as a base64 svg data uri" do
    Foundation.RpcMock
    |> expect(:call, fn @node, :code, :priv_dir, [@app], _timeout -> @priv_dir end)
    |> expect(:call, fn @node, :file, :read_file, [_path], _timeout -> {:ok, @svg} end)

    assert {:ok, "data:image/svg+xml;base64," <> encoded} = Logo.image(@node, @name)
    assert {:ok, @svg} = Base.decode64(encoded)
  end

  test "image/2 reads logo.svg from the application's own priv directory" do
    Foundation.RpcMock
    |> expect(:call, fn @node, :code, :priv_dir, [@app], _timeout -> @priv_dir end)
    |> expect(:call, fn @node, :file, :read_file, [path], _timeout ->
      assert path == "/opt/myelixir/lib/myelixir-1.0.0/priv/static/images/logo.svg"
      {:ok, @svg}
    end)

    assert {:ok, _data_uri} = Logo.image(@node, @name)
  end

  test "image/2 returns nil when the application has no logo.svg" do
    Foundation.RpcMock
    |> expect(:call, fn @node, :code, :priv_dir, [@app], _timeout -> @priv_dir end)
    |> expect(:call, fn @node, :file, :read_file, [_path], _timeout -> {:error, :enoent} end)

    assert {:ok, nil} = Logo.image(@node, @name)
  end

  test "image/2 returns nil when the application is not loaded on the node" do
    Foundation.RpcMock
    |> expect(:call, fn @node, :code, :priv_dir, [@app], _timeout -> {:error, :bad_name} end)

    assert {:ok, nil} = Logo.image(@node, @name)
  end

  test "image/2 returns nil when the node is unreachable" do
    Foundation.RpcMock
    |> expect(:call, fn @node, :code, :priv_dir, [@app], _timeout -> {:badrpc, :nodedown} end)

    assert {:ok, nil} = Logo.image(@node, @name)
  end

  test "image/2 returns nil for an unknown application name without calling the node" do
    # verify_on_exit! fails the test if the unknown name reaches the node
    assert {:ok, nil} = Logo.image(@node, "unknown_#{System.unique_integer([:positive])}")
  end
end
