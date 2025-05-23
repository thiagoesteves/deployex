defmodule Foundation.ConfigProvider.Secrets.AwsTest do
  use ExUnit.Case, async: false

  import Mock

  alias Foundation.ConfigProvider.Secrets.Aws
  alias Foundation.ConfigProvider.Secrets.Manager

  test "secrets/3 with success" do
    with_mocks([
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
               {:ex_aws, [region: "us-east-2"]},
               {:foundation,
                [
                  {Manager, [adapter: Aws, path: "any-env-path"]},
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
                     {Manager, adapter: Aws, path: "any-env-path"},
                     {:env, "prod"}
                   ],
                   ex_aws: [region: "us-east-2"]
                 ],
                 []
               )
    end
  end

  test "secrets/3 with request error" do
    with_mocks([
      {ExAws, [],
       [
         request: fn _data, _options -> {:ok, :invalid_data} end
       ]}
    ]) do
      assert_raise RuntimeError, fn ->
        [
          {:foundation,
           [
             {Manager, [adapter: Aws, path: "any-env-path"]},
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
                {Manager, adapter: Aws, path: "any-env-path"},
                {:env, "prod"}
              ],
              ex_aws: [region: "us-east-1"]
            ],
            []
          )
      end
    end
  end
end
