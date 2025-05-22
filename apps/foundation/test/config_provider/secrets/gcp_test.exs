defmodule Foundation.ConfigProvider.Secrets.GcpTest do
  use ExUnit.Case, async: false

  import Mock

  alias Foundation.ConfigProvider.Secrets.Gcp
  alias Foundation.ConfigProvider.Secrets.Manager

  test "secrets/3 with success" do
    pid = self()

    with_mocks([
      {Goth.Config, [], [get: fn :project_id -> {:ok, "my-project-id"} end]},
      {Goth, [], [fetch!: fn _name, _timeout -> %{token: "gcp-token"} end]},
      {Finch, [],
       [
         build: fn :get, _path, _headers, _options -> %{} end,
         request: fn _data, _module ->
           {:ok,
            %Finch.Response{
              body:
                "{\"name\":\"projects/546581980218/secrets/deployex-myappname-prod-secrets/versions/1\",\"payload\":{\"data\":\"eyJERVBMT1lFWF9BRE1JTl9IQVNIRURfUEFTU1dPUkQiOiIkMmIkMTIkbnFCNjIybmZxN0tPV1lTOTd4RHJQLjhETlRvUHhmNHpIWkZYZVZPUGM3R25sSmJaNy5EeXEiLCJERVBMT1lFWF9FUkxBTkdfQ09PS0lFIjoibXktY29va2llIiwiREVQTE9ZRVhfU0VDUkVUX0tFWV9CQVNFIjoiUnNFNm9rUUFLRWZ1Z3hUUnk1QUdyUVNaeG55d0E5NUFSL1BSS0dRTm9lbWpnN3crWmdiOHdwK1VleElrZ3dzTSJ9\",\"dataCrc32c\":\"1094623097\"}}"
            }}
         end
       ]},
      {Supervisor, [],
       [start_link: fn _children, _options -> {:ok, pid} end, stop: fn _pid, :normal -> :ok end]}
    ]) do
      assert [
               {:goth, [file_credentials: "{}"]},
               {:foundation,
                [
                  {Manager, [adapter: Gcp, path: "any-env-path"]},
                  {:env, "prod"},
                  {Foundation.Accounts,
                   [
                     admin_hashed_password:
                       "$2b$12$nqB622nfq7KOWYS97xDrP.8DNToPxf4zHZFXeVOPc7GnlJbZ7.Dyq"
                   ]}
                ]},
               {:deployex_web,
                [
                  {DeployexWeb.Endpoint,
                   [
                     secret_key_base:
                       "RsE6okQAKEfugxTRy5AGrQSZxnywA95AR/PRKGQNoemjg7w+Zgb8wp+UexIkgwsM"
                   ]}
                ]}
             ] =
               Manager.load(
                 [
                   foundation: [
                     {Manager, adapter: Gcp, path: "any-env-path"},
                     {:env, "prod"}
                   ],
                   goth: [{:file_credentials, "{}"}]
                 ],
                 []
               )
    end
  end

  test "secrets/3 with Finch error" do
    pid = self()

    with_mocks([
      {Goth.Config, [], [get: fn :project_id -> {:ok, "my-project-id"} end]},
      {Goth, [], [fetch!: fn _name, _timeout -> %{token: "gcp-token"} end]},
      {Finch, [],
       [
         build: fn :get, _path, _headers, _options -> %{} end,
         request: fn _data, _module -> {:error, :invalid_data} end
       ]},
      {Supervisor, [], [start_link: fn _children, _options -> {:ok, pid} end]}
    ]) do
      assert_raise RuntimeError, fn ->
        [
          {:goth, [file_credentials: "{}"]},
          {:foundation,
           [
             {Manager, [adapter: Gcp, path: "any-env-path"]},
             {:env, "prod"},
             {Foundation.Accounts,
              [
                admin_hashed_password:
                  "$2b$12$nqB622nfq7KOWYS97xDrP.8DNToPxf4zHZFXeVOPc7GnlJbZ7.Dyq"
              ]}
           ]},
          {:deployex_web,
           [
             {DeployexWeb.Endpoint,
              [
                secret_key_base:
                  "RsE6okQAKEfugxTRy5AGrQSZxnywA95AR/PRKGQNoemjg7w+Zgb8wp+UexIkgwsM"
              ]}
           ]}
        ] =
          Manager.load(
            [
              foundation: [
                {Manager, adapter: Gcp, path: "any-env-path"},
                {:env, "prod"}
              ],
              goth: [{:file_credentials, "{}"}]
            ],
            []
          )
      end
    end
  end
end
