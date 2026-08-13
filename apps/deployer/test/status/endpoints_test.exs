defmodule Deployer.Status.EndpointsTest do
  use ExUnit.Case, async: false

  import Mox

  alias Deployer.Status.Endpoints

  setup [
    :set_mox_global,
    :verify_on_exit!
  ]

  @node :"myelixir-abc123@nohost"

  test "urls/1 returns the url of every registered endpoint module" do
    registered = [
      :init,
      :kernel_sup,
      :"Elixir.MyAppWeb.Endpoint",
      :"Elixir.MyAppWeb.Endpoint.Config",
      :"Elixir.MyApp.Repo"
    ]

    Foundation.RpcMock
    |> expect(:call, fn @node, :erlang, :registered, [], _timeout -> registered end)
    |> expect(:call, fn @node, :"Elixir.MyAppWeb.Endpoint", :url, [], _timeout ->
      "http://localhost:4000"
    end)

    assert {:ok, ["http://localhost:4000"]} = Endpoints.urls(@node)
  end

  test "urls/1 returns every endpoint when the application serves more than one" do
    registered = [:"Elixir.MyAppWeb.Endpoint", :"Elixir.MyAppWeb.AdminEndpoint"]

    Foundation.RpcMock
    |> expect(:call, fn @node, :erlang, :registered, [], _timeout -> registered end)
    |> stub(:call, fn
      @node, :"Elixir.MyAppWeb.Endpoint", :url, [], _timeout -> "https://example.com"
      @node, :"Elixir.MyAppWeb.AdminEndpoint", :url, [], _timeout -> "http://localhost:4001"
    end)

    assert {:ok, ["http://localhost:4001", "https://example.com"]} = Endpoints.urls(@node)
  end

  test "urls/1 does not ask a name outside the endpoint convention for a url" do
    Foundation.RpcMock
    |> expect(:call, fn @node, :erlang, :registered, [], _timeout ->
      [:init, :kernel_sup, :"Elixir.MyApp.Repo", :"Elixir.MyAppWeb.Telemetry"]
    end)

    # verify_on_exit! fails the test if any of the names above is asked for a url
    assert {:ok, []} = Endpoints.urls(@node)
  end

  test "urls/1 discards a registered endpoint that does not export url/0" do
    Foundation.RpcMock
    |> expect(:call, fn @node, :erlang, :registered, [], _timeout ->
      [:"Elixir.MyApp.Endpoint"]
    end)
    |> expect(:call, fn @node, :"Elixir.MyApp.Endpoint", :url, [], _timeout ->
      {:badrpc, {:EXIT, {:undef, []}}}
    end)

    assert {:ok, []} = Endpoints.urls(@node)
  end

  test "urls/1 returns an error when the node is unreachable" do
    Foundation.RpcMock
    |> expect(:call, fn @node, :erlang, :registered, [], _timeout -> {:badrpc, :nodedown} end)

    assert :error = Endpoints.urls(@node)
  end

  test "urls/1 reports the same url once when two endpoints resolve to it" do
    registered = [:"Elixir.MyAppWeb.Endpoint", :"Elixir.MyAppWeb.OtherEndpoint"]

    Foundation.RpcMock
    |> expect(:call, fn @node, :erlang, :registered, [], _timeout -> registered end)
    |> stub(:call, fn @node, _module, :url, [], _timeout -> "http://localhost:4000" end)

    assert {:ok, ["http://localhost:4000"]} = Endpoints.urls(@node)
  end
end
