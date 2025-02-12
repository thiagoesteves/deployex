defmodule Deployex.ConfigProvider.AwsTest do
  use ExUnit.Case, async: false

  import Mock

  alias Deployex.ConfigProvider.Secrets.Manager

  test "secrets/3 with success" do
    with_mocks([
      {System, [], [fetch_env!: fn "AWS_REGION" -> "region" end, get_env: fn _env -> nil end]},
      {ExAws, [],
       [
         request: fn _data, _options ->
           {:ok,
            %{
              "SecretString" =>
                "{\"DEPLOYEX_ADMIN_HASHED_PASSWORD\":\"$2b$12$nqB622nfq7KOWYS97xDrP.8DNToPxf4zHZFXeVOPc7GnlJbZ7.Dyq\",\"DEPLOYEX_ERLANG_COOKIE\":\"my-cookie\",\"DEPLOYEX_SECRET_KEY_BASE\":\"RsE6okQAKEfugxTRy5AGrQSZxnywA95AR/PRKGQNoemjg7w+Zgb8wp+UexIkgwsM\"}"
            }}
         end
       ]}
    ]) do
      assert [
               {:deployex,
                [
                  {Deployex.ConfigProvider.Secrets.Manager,
                   [adapter: Deployex.ConfigProvider.Secrets.Aws, path: "any-env-path"]},
                  {:env, "prod"},
                  {DeployexWeb.Endpoint,
                   [
                     secret_key_base:
                       "RsE6okQAKEfugxTRy5AGrQSZxnywA95AR/PRKGQNoemjg7w+Zgb8wp+UexIkgwsM"
                   ]},
                  {Deployex.Accounts,
                   [
                     admin_hashed_password:
                       "$2b$12$nqB622nfq7KOWYS97xDrP.8DNToPxf4zHZFXeVOPc7GnlJbZ7.Dyq"
                   ]}
                ]}
             ] =
               Manager.load(
                 [
                   deployex: [
                     {Deployex.ConfigProvider.Secrets.Manager,
                      adapter: Deployex.ConfigProvider.Secrets.Aws, path: "any-env-path"},
                     {:env, "prod"}
                   ]
                 ],
                 []
               )
    end
  end

  test "secrets/3 with request error" do
    with_mocks([
      {System, [], [fetch_env!: fn "AWS_REGION" -> "region" end, get_env: fn _env -> nil end]},
      {ExAws, [],
       [
         request: fn _data, _options -> {:ok, :invalid_data} end
       ]}
    ]) do
      assert_raise RuntimeError, fn ->
        [
          {:deployex,
           [
             {Deployex.ConfigProvider.Secrets.Manager,
              [adapter: Deployex.ConfigProvider.Secrets.Aws, path: "any-env-path"]},
             {:env, "prod"},
             {DeployexWeb.Endpoint,
              [
                secret_key_base:
                  "RsE6okQAKEfugxTRy5AGrQSZxnywA95AR/PRKGQNoemjg7w+Zgb8wp+UexIkgwsM"
              ]},
             {Deployex.Accounts,
              [
                admin_hashed_password:
                  "$2b$12$nqB622nfq7KOWYS97xDrP.8DNToPxf4zHZFXeVOPc7GnlJbZ7.Dyq"
              ]}
           ]}
        ] =
          Manager.load(
            [
              deployex: [
                {Deployex.ConfigProvider.Secrets.Manager,
                 adapter: Deployex.ConfigProvider.Secrets.Aws, path: "any-env-path"},
                {:env, "prod"}
              ]
            ],
            []
          )
      end
    end
  end
end
