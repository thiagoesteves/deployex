defmodule Foundation.ConfigProvider.Env.ConfigTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mock

  alias Foundation.ConfigProvider.Env.Config

  @yaml_aws_path "./test/support/files/deployex-aws.yaml"
  @yaml_aws_path_monitoring "./test/support/files/deployex-aws-monitoring.yaml"
  @yaml_aws_path_optional "./test/support/files/deployex-aws-optional.yaml"
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
               {:ex_aws, [region: "sa-east-1"]},
               {:deployex_web,
                [
                  {DeployexWeb.Endpoint,
                   [
                     url: [port: 443, scheme: "https", host: "deployex.example.com"],
                     http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: 5001]
                   ]}
                ]},
               {:observer_web,
                [
                  {ObserverWeb.Telemetry,
                   [
                     mode: :observer,
                     data_retention_period: 3_600_000
                   ]}
                ]},
               {:sentinel,
                [
                  {Sentinel.Logs, [data_retention_period: 3_600_000]}
                ]},
               {:deployer,
                [
                  {Deployer.Engine,
                   [
                     delay_between_deploys_ms: 60_000,
                     timeout_rollback: 600_000,
                     schedule_interval: 5000
                   ]},
                  {Deployer.Release,
                   [adapter: Deployer.Release.S3, bucket: "myapp-prod-distribution"]}
                ]},
               {:foundation,
                [
                  {:env, "prod"},
                  {:applications,
                   [
                     %{
                       env: ["MYPHOENIXAPP_PHX_SERVER=true", "MYPHOENIXAPP_PHX_SERVER2=true"],
                       name: "myphoenixapp",
                       monitoring: [],
                       replicas: 3,
                       language: "elixir",
                       initial_port: 4000
                     },
                     %{
                       env: ["MYUMBRELLA_PHX_SERVER=true", "MYUMBRELLA_PHX_SERVER2=true"],
                       name: "myumbrella",
                       monitoring: [],
                       replicas: 2,
                       language: "erlang",
                       initial_port: 4050
                     }
                   ]},
                  {Foundation.ConfigProvider.Secrets.Manager,
                   [
                     adapter: Foundation.ConfigProvider.Secrets.Aws,
                     path: "deployex-myapp-prod-secrets"
                   ]}
                ]}
             ] =
               Config.load(
                 [
                   foundation: [
                     {Foundation.ConfigProvider.Secrets.Manager,
                      adapter: Foundation.ConfigProvider.Secrets.Gcp, path: "any-env-path"},
                     {:env, "not-set"},
                     {:applications,
                      [
                        %{
                          env: [],
                          name: "myphoenixapp",
                          monitoring: [],
                          replicas: 3,
                          language: "not-set",
                          initial_port: 1000
                        }
                      ]}
                   ],
                   deployer: [
                     {Deployer.Engine, [delay_between_deploys_ms: 60_000]}
                   ],
                   deployex_web: [
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

  test "load/3 with success for AWS - Monitoring" do
    with_mocks([
      {System, [], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_path_monitoring end]}
    ]) do
      assert [
               {:ex_aws, [region: "sa-east-1"]},
               {:deployex_web,
                [
                  {DeployexWeb.Endpoint,
                   [
                     url: [host: "deployex.example.com"],
                     http: [port: 5001]
                   ]}
                ]},
               {:observer_web,
                [
                  {ObserverWeb.Telemetry,
                   [
                     data_retention_period: 3_600_000
                   ]}
                ]},
               {:sentinel,
                [
                  {
                    Sentinel.Watchdog,
                    [
                      {:system_config,
                       [
                         memory: %{
                           enable_restart: true,
                           warning_threshold_percent: 75,
                           restart_threshold_percent: 85
                         }
                       ]},
                      {:applications_config,
                       [
                         default: %{
                           enable_restart: true,
                           warning_threshold_percent: 50,
                           restart_threshold_percent: 70
                         },
                         myphoenixapp: [
                           atom: %{
                             enable_restart: true,
                             warning_threshold_percent: 75,
                             restart_threshold_percent: 90
                           },
                           process: %{
                             enable_restart: true,
                             warning_threshold_percent: 75,
                             restart_threshold_percent: 90
                           },
                           port: %{
                             enable_restart: true,
                             warning_threshold_percent: 75,
                             restart_threshold_percent: 90
                           }
                         ]
                       ]}
                    ]
                  },
                  {Sentinel.Logs, [data_retention_period: 3_600_000]}
                ]},
               {:deployer,
                [
                  {Deployer.Engine,
                   [
                     timeout_rollback: 600_000,
                     schedule_interval: 5000
                   ]},
                  {Deployer.Release,
                   [adapter: Deployer.Release.S3, bucket: "myapp-prod-distribution"]}
                ]},
               {:foundation,
                [
                  {:env, "prod"},
                  {:applications,
                   [
                     %{
                       env: ["MYPHOENIXAPP_PHX_SERVER=true", "MYPHOENIXAPP_PHX_SERVER2=true"],
                       name: "myphoenixapp",
                       monitoring: [
                         atom: %{
                           enable_restart: true,
                           warning_threshold_percent: 75,
                           restart_threshold_percent: 90
                         },
                         process: %{
                           enable_restart: true,
                           warning_threshold_percent: 75,
                           restart_threshold_percent: 90
                         },
                         port: %{
                           enable_restart: true,
                           warning_threshold_percent: 75,
                           restart_threshold_percent: 90
                         }
                       ],
                       replicas: 3,
                       language: "elixir",
                       initial_port: 4000
                     },
                     %{
                       env: ["MYUMBRELLA_PHX_SERVER=true", "MYUMBRELLA_PHX_SERVER2=true"],
                       name: "myumbrella",
                       monitoring: [],
                       replicas: 2,
                       language: "erlang",
                       initial_port: 4050
                     }
                   ]},
                  {Foundation.ConfigProvider.Secrets.Manager,
                   [
                     adapter: Foundation.ConfigProvider.Secrets.Aws,
                     path: "deployex-myapp-prod-secrets"
                   ]}
                ]}
             ] =
               Config.load(
                 [
                   sentinel: [
                     {Sentinel.Watchdog,
                      [
                        applications_config: [
                          default: %{
                            enable_restart: true,
                            warning_threshold_percent: 50,
                            restart_threshold_percent: 70
                          },
                          myphoenixapp: [
                            atom: %{
                              enable_restart: false,
                              warning_threshold_percent: 22,
                              restart_threshold_percent: 33
                            },
                            port: %{
                              enable_restart: false,
                              warning_threshold_percent: 60,
                              restart_threshold_percent: 98
                            }
                          ]
                        ],
                        system_config: [
                          memory: %{
                            enable_restart: false,
                            warning_threshold_percent: 10,
                            restart_threshold_percent: 20
                          }
                        ]
                      ]}
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
               {:ex_aws, [region: "not-set"]},
               {:deployex_web,
                [
                  {DeployexWeb.Endpoint,
                   [
                     url: [port: 443, scheme: "https", host: "deployex.example.com"],
                     http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: 5001]
                   ]}
                ]},
               {:observer_web,
                [{ObserverWeb.Telemetry, [mode: :observer, data_retention_period: 3_600_000]}]},
               {:sentinel,
                [
                  {Sentinel.Logs, [data_retention_period: 3_600_000]}
                ]},
               {:goth, [file_credentials: "/home/ubuntu/gcp-config.json"]},
               {:deployer,
                [
                  {Deployer.Engine,
                   [
                     delay_between_deploys_ms: 60_000,
                     timeout_rollback: 600_000,
                     schedule_interval: 5000
                   ]},
                  {Deployer.Release,
                   [adapter: Deployer.Release.GcpStorage, bucket: "myapp-prod-distribution"]}
                ]},
               {:foundation,
                [
                  {:env, "prod"},
                  {:applications,
                   [
                     %{
                       env: ["MYPHOENIXAPP_PHX_SERVER=false", "MYPHOENIXAPP_PHX_SERVER2=false"],
                       name: "myphoenixapp",
                       monitoring: [],
                       replicas: 3,
                       language: "elixir",
                       initial_port: 4000
                     },
                     %{
                       env: ["MYUMBRELLA_PHX_SERVER=false", "MYUMBRELLA_PHX_SERVER2=false"],
                       name: "myumbrella",
                       monitoring: [],
                       replicas: 2,
                       language: "erlang",
                       initial_port: 4050
                     }
                   ]},
                  {Foundation.ConfigProvider.Secrets.Manager,
                   [
                     adapter: Foundation.ConfigProvider.Secrets.Gcp,
                     path: "deployex-myapp-prod-secrets"
                   ]}
                ]}
             ] =
               Config.load(
                 [
                   foundation: [
                     {Foundation.ConfigProvider.Secrets.Manager,
                      adapter: Foundation.ConfigProvider.Secrets.Aws, path: "any-env-path"},
                     {:env, "not-set"}
                   ],
                   deployer: [
                     {Deployer.Engine, [delay_between_deploys_ms: 60_000]}
                   ],
                   deployex_web: [
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
        foundation: [
          {Foundation.ConfigProvider.Secrets.Manager,
           adapter: Foundation.ConfigProvider.Secrets.Aws, path: "any-env-path"},
          {:env, "not-set"}
          # {:monitored_app_name, "not-set"},
          # {:replicas, 99},
          # {:monitored_app_lang, "not-set"},
          # {:monitored_app_start_port, 99_999},
          # {:monitored_app_env, []}
        ],
        deployer: [
          {Deployer.Engine, [delay_between_deploys_ms: 60_000]}
        ],
        deployex_web: [
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

  test "load/3 - Optional fields don't change if not passed in the YAML" do
    with_mocks([
      {System, [], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_path_optional end]}
    ]) do
      assert [
               {:sentinel,
                [
                  {Sentinel.Logs, [data_retention_period: 3_600_000]}
                ]},
               {:observer_web,
                [{ObserverWeb.Telemetry, [mode: :observer, data_retention_period: 1000]}]},
               {:ex_aws, [region: "sa-east-1"]},
               {:deployex_web,
                [
                  {DeployexWeb.Endpoint,
                   [
                     url: [host: "deployex.example.com"],
                     http: [port: 5001]
                   ]}
                ]},
               {:deployer,
                [
                  {Deployer.Engine,
                   [
                     timeout_rollback: 700_000,
                     schedule_interval: 10_000
                   ]},
                  {Deployer.Release,
                   [adapter: Deployer.Release.S3, bucket: "myapp-prod-distribution"]}
                ]},
               {:foundation,
                [
                  {:env, "prod"},
                  {:applications,
                   [
                     %{
                       env: [],
                       name: "myphoenixapp",
                       monitoring: [],
                       replicas: 3,
                       language: "elixir",
                       initial_port: 4000
                     }
                   ]},
                  {Foundation.ConfigProvider.Secrets.Manager,
                   [
                     adapter: Foundation.ConfigProvider.Secrets.Aws,
                     path: "deployex-myapp-prod-secrets"
                   ]}
                ]}
             ] =
               Config.load(
                 [
                   sentinel: [
                     {Sentinel.Logs, [data_retention_period: 3_600_000]}
                   ],
                   observer_web: [
                     {ObserverWeb.Telemetry, [mode: :observer, data_retention_period: 1000]}
                   ],
                   deployer: [
                     {Deployer.Engine,
                      [
                        timeout_rollback: 700_000,
                        schedule_interval: 10_000
                      ]}
                   ]
                 ],
                 []
               )
    end
  end

  test "load/3 with error for invalid secrets" do
    with_mocks([
      {System, [], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_gcp_secrets_error_path end]}
    ]) do
      config = [
        foundation: [
          {Foundation.ConfigProvider.Secrets.Manager,
           adapter: Foundation.ConfigProvider.Secrets.Aws, path: "any-env-path"},
          {:env, "not-set"}
        ],
        deployer: [
          {Deployer.Engine, [delay_between_deploys_ms: 60_000]}
        ],
        deployex_web: [
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
        {:foundation,
         [
           {Foundation.ConfigProvider.Secrets.Manager,
            adapter: Foundation.ConfigProvider.Secrets.Gcp, path: "any-env-path"},
           {:env, "not-set"}
         ]},
        {:deployer,
         [
           {Deployer.Engine, [delay_between_deploys_ms: 60_000]}
         ]},
        {:deployex_web,
         [
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
