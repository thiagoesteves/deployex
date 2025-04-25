defmodule Deployer.Aws.HttpClientTest do
  use ExUnit.Case, async: false

  import Mock

  alias Deployer.Aws.ExAwsHttpClient

  test "ExAwsHttpClient.request/5 with success" do
    with_mock Finch, [:passthrough],
      request: fn _attrs, _module ->
        {:ok, %{status: 200, body: "", headers: []}}
      end do
      assert {:ok, %{status_code: 200}} =
               ExAwsHttpClient.request(:get, "http://www.google.com", "", [], [])
    end
  end

  test "ExAwsHttpClient.request/5 with error" do
    with_mock Finch, [:passthrough],
      request: fn _attrs, _module ->
        {:error, "Timeout"}
      end do
      assert {:error, %{reason: "Timeout"}} =
               ExAwsHttpClient.request(:get, "http://www.google.com", "", [], [])
    end
  end
end
