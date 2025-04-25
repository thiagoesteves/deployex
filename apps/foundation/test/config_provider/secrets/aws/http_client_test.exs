defmodule Foundation.ConfigProvider.Secrets.Aws.HttpClientTest do
  use ExUnit.Case, async: false

  import Mock

  alias Foundation.ConfigProvider.Secrets.Aws

  test "Deployer.ConfigProvider.Secrets.Aws.request/5 with success" do
    with_mock Finch, [:passthrough],
      request: fn _attrs, _module ->
        {:ok, %{status: 200, body: "", headers: []}}
      end do
      assert {:ok, %{status_code: 200}} =
               Aws.request(:get, "http://www.google.com", "", [], [])
    end
  end

  test "Deployer.ConfigProvider.Secrets.Aws.request/5 with error" do
    with_mock Finch, [:passthrough],
      request: fn _attrs, _module ->
        {:error, "Timeout"}
      end do
      assert {:error, %{reason: "Timeout"}} =
               Aws.request(:get, "http://www.google.com", "", [], [])
    end
  end
end
