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
  @web_app :myelixir_web
  @priv_dir ~c"/opt/myelixir/lib/myelixir-1.0.0/priv"
  @web_priv_dir ~c"/opt/myelixir/lib/myelixir_web-1.0.0/priv"
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
    |> expect(:call, fn @node, :application, :loaded_applications, [], _timeout ->
      [{@app, "myelixir", "1.0.0"}]
    end)

    assert {:ok, nil} = Logo.image(@node, @name)
  end

  test "image/2 returns nil when the application is not loaded on the node" do
    Foundation.RpcMock
    |> expect(:call, fn @node, :code, :priv_dir, [@app], _timeout -> {:error, :bad_name} end)
    |> expect(:call, fn @node, :application, :loaded_applications, [], _timeout -> [] end)

    assert {:ok, nil} = Logo.image(@node, @name)
  end

  test "image/2 returns nil when the node is unreachable" do
    Foundation.RpcMock
    |> expect(:call, fn @node, :code, :priv_dir, [@app], _timeout -> {:badrpc, :nodedown} end)
    |> expect(:call, fn @node, :application, :loaded_applications, [], _timeout ->
      {:badrpc, :nodedown}
    end)

    assert {:ok, nil} = Logo.image(@node, @name)
  end

  test "image/2 returns nil for an unknown application name without calling the node" do
    # verify_on_exit! fails the test if the unknown name reaches the node
    assert {:ok, nil} = Logo.image(@node, "unknown_#{System.unique_integer([:positive])}")
  end

  test "image/2 always answers so the caller can cache the absence of a logo" do
    # every failure mode is an ok tuple, never an error the caller has to retry
    Foundation.RpcMock
    |> expect(:call, fn @node, :code, :priv_dir, [@app], _timeout -> @priv_dir end)
    |> expect(:call, fn @node, :file, :read_file, [_path], _timeout -> {:error, :enoent} end)
    |> expect(:call, fn @node, :application, :loaded_applications, [], _timeout ->
      [{@app, "myelixir", "1.0.0"}]
    end)
    |> expect(:call, fn @node, :code, :priv_dir, [@app], _timeout -> @priv_dir end)
    |> expect(:call, fn @node, :file, :read_file, [_path], _timeout -> {:error, :enoent} end)
    |> expect(:call, fn @node, :application, :loaded_applications, [], _timeout ->
      [{@app, "myelixir", "1.0.0"}]
    end)

    assert {:ok, nil} = Logo.image(@node, @name)
    assert {:ok, nil} = Logo.image(@node, @name)
  end

  test "image/2 falls back to the umbrella child for the logo" do
    # the main app has no logo, so the umbrella path is taken
    Foundation.RpcMock
    |> expect(:call, fn @node, :code, :priv_dir, [@app], _timeout -> @priv_dir end)
    |> expect(:call, fn @node, :file, :read_file, [_path], _timeout -> {:error, :enoent} end)
    |> expect(:call, fn @node, :application, :loaded_applications, [], _timeout ->
      [{@app, "myelixir", "1.0.0"}, {@web_app, "myelixir_web", "1.0.0"}]
    end)
    # the web app is probed and has the logo
    |> expect(:call, fn @node, :code, :priv_dir, [@web_app], _timeout -> @web_priv_dir end)
    |> expect(:call, fn @node, :file, :read_file, [path], _timeout ->
      assert path == "/opt/myelixir/lib/myelixir_web-1.0.0/priv/static/images/logo.svg"
      {:ok, @svg}
    end)

    assert {:ok, "data:image/svg+xml;base64," <> encoded} = Logo.image(@node, @name)
    assert {:ok, @svg} = Base.decode64(encoded)
  end

  test "image/2 ignores an unrelated app from another project" do
    Foundation.RpcMock
    |> expect(:call, fn @node, :code, :priv_dir, [@app], _timeout -> @priv_dir end)
    |> expect(:call, fn @node, :file, :read_file, [_path], _timeout -> {:error, :enoent} end)
    |> expect(:call, fn @node, :application, :loaded_applications, [], _timeout ->
      [{@app, "myelixir", "1.0.0"}, {:observer_web, "observer_web", "0.1.0"}]
    end)

    # observer_web is not myelixir_web, so no probe and a nil logo
    assert {:ok, nil} = Logo.image(@node, @name)
  end

  test "image/2 returns nil when the umbrella child has no logo.svg" do
    Foundation.RpcMock
    |> expect(:call, fn @node, :code, :priv_dir, [@app], _timeout -> @priv_dir end)
    |> expect(:call, fn @node, :file, :read_file, [_path], _timeout -> {:error, :enoent} end)
    |> expect(:call, fn @node, :application, :loaded_applications, [], _timeout ->
      [{@app, "myelixir", "1.0.0"}, {@web_app, "myelixir_web", "1.0.0"}]
    end)
    |> expect(:call, fn @node, :code, :priv_dir, [@web_app], _timeout -> @web_priv_dir end)
    |> expect(:call, fn @node, :file, :read_file, [_path], _timeout -> {:error, :enoent} end)

    assert {:ok, nil} = Logo.image(@node, @name)
  end

  test "image/2 returns nil when loaded_applications is unreachable" do
    Foundation.RpcMock
    |> expect(:call, fn @node, :code, :priv_dir, [@app], _timeout -> @priv_dir end)
    |> expect(:call, fn @node, :file, :read_file, [_path], _timeout -> {:error, :enoent} end)
    |> expect(:call, fn @node, :application, :loaded_applications, [], _timeout ->
      {:badrpc, :nodedown}
    end)

    assert {:ok, nil} = Logo.image(@node, @name)
  end
end
