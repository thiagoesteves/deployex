defmodule Deployex.ConfigProvider.Env.ConfigTest do
  use ExUnit.Case, async: false

  import Mock

  alias Deployex.ConfigProvider.Env.Config

  @yaml_path "./test/support/files/deployex.yaml"

  test "init/1 with success" do
    assert Config.init(:any) == []
  end

  test "load/3 with success" do
    with_mocks([
      {System, [], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_path end]}
    ]) do
      assert [
               {:deployex,
                [
                  {:env, "prod"},
                  {:name, "myphoenixapp"},
                  {:replicas, 3},
                  {:monitored_app_lang, "elixir"},
                  {:monitored_app_start_port, 4000},
                  {:monitored_app_env,
                   ["MYPHOENIXAPP_PHX_SERVER=true", "MYPHOENIXAPP_PHX_SERVER2=true"]},
                  {Deployex.Release,
                   [adapter: Deployex.Release.S3, bucket: "myapp-prod-distribution"]},
                  {Deployex.ConfigProvider.Secrets.Manager,
                   [
                     adapter: Deployex.ConfigProvider.Secrets.Aws,
                     path: "deployex-myapp-prod-secrets"
                   ]},
                  {Deployex.Deployment,
                   [
                     delay_between_deploys_ms: 60_000,
                     timeout_rollback: 600_000,
                     schedule_interval: 5000
                   ]},
                  {DeployexWeb.Endpoint,
                   [
                     url: [port: 443, scheme: "https", host: "deployex.example.com"],
                     http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: 5001]
                   ]},
                  {Deployex.Logs, [data_retention_period: 3_600_000]}
                ]},
               {:ex_aws, [region: "sa-east-1"]},
               {:goth, [file_credentials: "/home/ubuntu/gcp-config.json"]},
               {:observer_web,
                [{ObserverWeb.Telemetry, [mode: :observer, data_retention_period: 3_600_000]}]}
             ] =
               Config.load(
                 [
                   deployex: [
                     {Deployex.ConfigProvider.Secrets.Manager,
                      adapter: Deployex.ConfigProvider.Secrets.Gcp, path: "any-env-path"},
                     {:env, "not-set"},
                     {:name, "not-set"},
                     {:replicas, 99},
                     {:monitored_app_lang, "not-set"},
                     {:monitored_app_start_port, 99_999},
                     {:monitored_app_env, []},
                     {Deployex.Deployment, [delay_between_deploys_ms: 60_000]},
                     {DeployexWeb.Endpoint,
                      [
                        url: [host: "not-set", port: 443, scheme: "https"],
                        http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: 999]
                      ]}
                   ],
                   ex_aws: [region: "not-set"],
                   observer_web: [
                     {ObserverWeb.Telemetry, [mode: :observer, data_retention_period: 0]}
                   ]
                 ],
                 []
               )
    end
  end

  # test "load/2 with non-local config and non setting cookie" do
  #   SecretsMock
  #   |> stub(:secrets, fn _config, _path, _options ->
  #     %{
  #       "DEPLOYEX_ADMIN_HASHED_PASSWORD" =>
  #         "$2b$12$nqB622nfq7KOWYS97xDrP.8DNToPxf4zHZFXeVOPc7GnlJbZ7.Dyq",
  #       "DEPLOYEX_ERLANG_COOKIE" => "my-cookie",
  #       "DEPLOYEX_SECRET_KEY_BASE" =>
  #         "RsE6okQAKEfugxTRy5AGrQSZxnywA95AR/PRKGQNoemjg7w+Zgb8wp+UexIkgwsM"
  #     }
  #   end)

  #   assert [
  #            {:deployex,
  #             [
  #               {Deployex.ConfigProvider.Secrets.Manager,
  #                [adapter: SecretsMock, path: "any-env-path"]},
  #               {:env, "prod"},
  #               {DeployexWeb.Endpoint,
  #                [
  #                  secret_key_base:
  #                    "RsE6okQAKEfugxTRy5AGrQSZxnywA95AR/PRKGQNoemjg7w+Zgb8wp+UexIkgwsM"
  #                ]},
  #               {Deployex.Accounts,
  #                [
  #                  admin_hashed_password:
  #                    "$2b$12$nqB622nfq7KOWYS97xDrP.8DNToPxf4zHZFXeVOPc7GnlJbZ7.Dyq"
  #                ]}
  #             ]}
  #          ] =
  #            Manager.load(
  #              [
  #                deployex: [
  #                  {Deployex.ConfigProvider.Secrets.Manager,
  #                   adapter: SecretsMock, path: "any-env-path"},
  #                  {:env, "prod"}
  #                ]
  #              ],
  #              []
  #            )
  # end

  # test "load/2 with non-local config and set cookie" do
  #   SecretsMock
  #   |> stub(:secrets, fn _config, _path, _options ->
  #     %{
  #       "DEPLOYEX_ADMIN_HASHED_PASSWORD" =>
  #         "$2b$12$nqB622nfq7KOWYS97xDrP.8DNToPxf4zHZFXeVOPc7GnlJbZ7.Dyq",
  #       "DEPLOYEX_ERLANG_COOKIE" => "my-cookie",
  #       "DEPLOYEX_SECRET_KEY_BASE" =>
  #         "RsE6okQAKEfugxTRy5AGrQSZxnywA95AR/PRKGQNoemjg7w+Zgb8wp+UexIkgwsM"
  #     }
  #   end)

  #   with_mock Node,
  #     self: fn -> :app@hostname end,
  #     set_cookie: fn _node, :"my-cookie" -> :ok end do
  #     assert [
  #              {:deployex,
  #               [
  #                 {Deployex.ConfigProvider.Secrets.Manager,
  #                  [adapter: SecretsMock, path: "any-env-path"]},
  #                 {:env, "prod"},
  #                 {DeployexWeb.Endpoint,
  #                  [
  #                    secret_key_base:
  #                      "RsE6okQAKEfugxTRy5AGrQSZxnywA95AR/PRKGQNoemjg7w+Zgb8wp+UexIkgwsM"
  #                  ]},
  #                 {Deployex.Accounts,
  #                  [
  #                    admin_hashed_password:
  #                      "$2b$12$nqB622nfq7KOWYS97xDrP.8DNToPxf4zHZFXeVOPc7GnlJbZ7.Dyq"
  #                  ]}
  #               ]}
  #            ] =
  #              Manager.load(
  #                [
  #                  deployex: [
  #                    {Deployex.ConfigProvider.Secrets.Manager,
  #                     adapter: SecretsMock, path: "any-env-path"},
  #                    {:env, "prod"}
  #                  ]
  #                ],
  #                []
  #              )
  #   end
  # end

  # test "load/2 with local config" do
  #   assert [
  #            {:deployex,
  #             [
  #               {Deployex.ConfigProvider.Secrets.Manager,
  #                [adapter: Deployex.ConfigProvider.SecretsMock, path: "any-env-path"]},
  #               {:env, "local"}
  #             ]}
  #          ] =
  #            Manager.load(
  #              [
  #                deployex: [
  #                  {Deployex.ConfigProvider.Secrets.Manager,
  #                   adapter: SecretsMock, path: "any-env-path"},
  #                  {:env, "local"}
  #                ]
  #              ],
  #              []
  #            )
  # end
end
