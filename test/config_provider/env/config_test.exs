defmodule Deployex.ConfigProvider.Env.ConfigTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mock

  alias Deployex.ConfigProvider.Env.Config

  @yaml_aws_path "./test/support/files/deployex-aws.yaml"
  @yaml_gcp_path "./test/support/files/deployex-gcp.yaml"
  @yaml_gcp_release_error_path "./test/support/files/deployex-gcp-release-error.yaml"
  @yaml_gcp_secrets_error_path "./test/support/files/deployex-gcp-secrets-error.yaml"

  test "init/1 with success" do
    assert Config.init(:any) == []
  end

  test "load/3 with success for AWS" do
    with_mocks([
      {System, [], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_path end]}
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

  test "load/3 with success for GCP" do
    with_mocks([
      {System, [], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_gcp_path end]}
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
                   ["MYPHOENIXAPP_PHX_SERVER=false", "MYPHOENIXAPP_PHX_SERVER2=false"]},
                  {Deployex.Release,
                   [adapter: Deployex.Release.GcpStorage, bucket: "myapp-prod-distribution"]},
                  {Deployex.ConfigProvider.Secrets.Manager,
                   [
                     adapter: Deployex.ConfigProvider.Secrets.Gcp,
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
                      adapter: Deployex.ConfigProvider.Secrets.Aws, path: "any-env-path"},
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

  test "load/3 with error for invalid release" do
    with_mocks([
      {System, [], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_gcp_release_error_path end]}
    ]) do
      config = [
        deployex: [
          {Deployex.ConfigProvider.Secrets.Manager,
           adapter: Deployex.ConfigProvider.Secrets.Aws, path: "any-env-path"},
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
      ]

      assert_raise RuntimeError, fn ->
        Config.load(config, [])
      end
    end
  end

  test "load/3 with error for invalid secrets" do
    with_mocks([
      {System, [], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_gcp_secrets_error_path end]}
    ]) do
      config = [
        deployex: [
          {Deployex.ConfigProvider.Secrets.Manager,
           adapter: Deployex.ConfigProvider.Secrets.Aws, path: "any-env-path"},
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
      ]

      assert_raise RuntimeError, fn ->
        Config.load(config, [])
      end
    end
  end

  test "load/3 with error with no valid yaml file" do
    with_mocks([
      {System, [], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> "." end]}
    ]) do
      config = [
        {:deployex,
         [
           {Deployex.ConfigProvider.Secrets.Manager,
            adapter: Deployex.ConfigProvider.Secrets.Gcp, path: "any-env-path"},
           {:env, "not-set"},
           {:name, "not-set"},
           {:replicas, 99},
           {:monitored_app_lang, "not-set"},
           {:monitored_app_start_port, 99_999},
           {:monitored_app_env, []},
           {Deployex.Deployment,
            [
              delay_between_deploys_ms: 60_000
            ]},
           {DeployexWeb.Endpoint,
            [
              url: [host: "not-set", port: 443, scheme: "https"],
              http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: 999]
            ]}
         ]},
        {:ex_aws, [region: "not-set"]},
        {:observer_web, [{ObserverWeb.Telemetry, [mode: :observer, data_retention_period: 0]}]}
      ]

      assert capture_log(fn ->
               assert config == Config.load(config, [])
             end) =~ "No file found or decoded at ., default configuration will be applied"
    end
  end
end
