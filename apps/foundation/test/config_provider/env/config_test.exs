defmodule Foundation.ConfigProvider.Env.ConfigTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mock

  alias Foundation.ConfigProvider.Env.Config

  @file_paths "./test/support/files"

  @yaml_aws_default "#{@file_paths}/deployex-aws.yaml"
  @yaml_aws_monitoring "#{@file_paths}/deployex-aws-monitoring.yaml"
  @yaml_aws_monitoring_multiple_apps "#{@file_paths}/deployex-aws-monitoring-multiple-apps.yaml"
  @yaml_aws_optional "#{@file_paths}/deployex-aws-optional.yaml"
  @yaml_gcp_path "#{@file_paths}/deployex-gcp.yaml"
  @yaml_gcp_release_error "#{@file_paths}/deployex-gcp-release-error.yaml"
  @yaml_gcp_secrets_error "#{@file_paths}/deployex-gcp-secrets-error.yaml"

  test "init/1 with success" do
    assert Config.init(:any) == []
  end

  test "load/3 with success for AWS" do
    with_mocks([
      {System, [], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_default end]}
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
                  mode: :observer,
                  data_retention_period: 3_600_000
                ]},
               {:deployer,
                [
                  {Deployer.Release,
                   [adapter: Deployer.Release.S3, bucket: "myapp-prod-distribution"]}
                ]},
               {:foundation,
                [
                  {:env, "prod"},
                  {:applications,
                   [
                     %{
                       env: [
                         "STRING_VALUE=string",
                         "BOOLEAN_TRUE=true",
                         "BOOLEAN_FALSE=false",
                         "NUMBER_VALUE=123"
                       ],
                       name: "myphoenixapp",
                       monitoring: [],
                       replicas: 3,
                       language: "elixir",
                       replica_ports: [%{base: 4000, key: "PORT"}]
                     },
                     %{
                       env: ["MYUMBRELLA_PHX_SERVER=true", "MYUMBRELLA_PHX_SERVER2=true"],
                       name: "myumbrella",
                       monitoring: [],
                       replicas: 2,
                       language: "erlang",
                       replica_ports: [%{base: 4050, key: "PORT"}]
                     }
                   ]},
                  {:config_checksum,
                   "d165d4ff6518ef4f06f8d0fe69f940b1c3156c8260dedff28b16792789c63a8b"},
                  {:monitoring, []},
                  {:logs_retention_time_ms, 3_600_000},
                  {:deploy_rollback_timeout_ms, 600_000},
                  {:deploy_schedule_interval_ms, 5_000},
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
                          replica_ports: [%{base: 1000, key: "PORT"}]
                        }
                      ]},
                     {:config_checksum, nil}
                   ],
                   deployex_web: [
                     {DeployexWeb.Endpoint,
                      [
                        url: [host: "not-set", port: 443, scheme: "https"],
                        http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: 999]
                      ]}
                   ],
                   ex_aws: [region: "not-set"],
                   observer_web: [mode: :observer, data_retention_period: 0]
                 ],
                 []
               )
    end
  end

  test "load/3 with success for AWS - Monitoring for a single app" do
    with_mocks([
      {System, [], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_monitoring end]}
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
               {:observer_web, [data_retention_period: 3_600_000]},
               {:deployer,
                [
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
                       replica_ports: [%{base: 4000, key: "PORT"}]
                     },
                     %{
                       env: ["MYUMBRELLA_PHX_SERVER=true", "MYUMBRELLA_PHX_SERVER2=true"],
                       name: "myumbrella",
                       monitoring: [],
                       replicas: 2,
                       language: "erlang",
                       replica_ports: [%{base: 4050, key: "PORT"}]
                     }
                   ]},
                  {:config_checksum,
                   "a67eddebd4a9e00269cbe4d322e994289bb4e039210e6f61d759f918541f6b85"},
                  {:monitoring,
                   [
                     memory: %Foundation.Yaml.Monitoring{
                       enable_restart: true,
                       warning_threshold_percent: 75,
                       restart_threshold_percent: 85
                     }
                   ]},
                  {:logs_retention_time_ms, 3_600_000},
                  {:deploy_rollback_timeout_ms, 600_000},
                  {:deploy_schedule_interval_ms, 5_000},
                  {Foundation.ConfigProvider.Secrets.Manager,
                   [
                     adapter: Foundation.ConfigProvider.Secrets.Aws,
                     path: "deployex-myapp-prod-secrets"
                   ]}
                ]}
             ] = Config.load([], [])
    end
  end

  test "load/3 with success for AWS - Monitoring for a multiple applications" do
    with_mocks([
      {System, [],
       [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_monitoring_multiple_apps end]}
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
               {:observer_web, [data_retention_period: 3_600_000]},
               {:deployer,
                [
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
                       replica_ports: [%{base: 4000, key: "PORT"}]
                     },
                     %{
                       env: ["MYUMBRELLA_PHX_SERVER=true", "MYUMBRELLA_PHX_SERVER2=true"],
                       name: "myumbrella",
                       monitoring: [
                         atom: %{
                           enable_restart: true,
                           warning_threshold_percent: 40,
                           restart_threshold_percent: 50
                         },
                         process: %{
                           enable_restart: true,
                           warning_threshold_percent: 60,
                           restart_threshold_percent: 70
                         },
                         port: %{
                           enable_restart: true,
                           warning_threshold_percent: 80,
                           restart_threshold_percent: 90
                         }
                       ],
                       replicas: 2,
                       language: "erlang",
                       replica_ports: [%{base: 4050, key: "PORT"}]
                     }
                   ]},
                  {:config_checksum,
                   "e24863bf980b40262095c0b2a7c7500663f0702434072f8e4e5f5a111407e809"},
                  {:monitoring,
                   [
                     memory: %Foundation.Yaml.Monitoring{
                       enable_restart: true,
                       warning_threshold_percent: 75,
                       restart_threshold_percent: 85
                     }
                   ]},
                  {:logs_retention_time_ms, 3_600_000},
                  {:deploy_rollback_timeout_ms, 600_000},
                  {:deploy_schedule_interval_ms, 5_000},
                  {Foundation.ConfigProvider.Secrets.Manager,
                   [
                     adapter: Foundation.ConfigProvider.Secrets.Aws,
                     path: "deployex-myapp-prod-secrets"
                   ]}
                ]}
             ] = Config.load([], [])
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
               {:observer_web, [mode: :observer, data_retention_period: 3_600_000]},
               {:goth, [file_credentials: "/home/ubuntu/gcp-config.json"]},
               {:deployer,
                [
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
                       replica_ports: [%{base: 4000, key: "PORT"}]
                     },
                     %{
                       env: ["MYUMBRELLA_PHX_SERVER=false", "MYUMBRELLA_PHX_SERVER2=false"],
                       name: "myumbrella",
                       monitoring: [],
                       replicas: 2,
                       language: "erlang",
                       replica_ports: [%{base: 4050, key: "PORT"}]
                     }
                   ]},
                  {:config_checksum,
                   "a8424a9c39a86772229fb235c10fe2e11a154de521bbb483d46a641cccc0f716"},
                  {:monitoring, []},
                  {:logs_retention_time_ms, 3_600_000},
                  {:deploy_rollback_timeout_ms, 600_000},
                  {:deploy_schedule_interval_ms, 5_000},
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
                     {:env, "not-set"},
                     {:config_checksum, nil}
                   ],
                   deployex_web: [
                     {DeployexWeb.Endpoint,
                      [
                        url: [host: "not-set", port: 443, scheme: "https"],
                        http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: 999]
                      ]}
                   ],
                   ex_aws: [region: "not-set"],
                   observer_web: [mode: :observer, data_retention_period: 0]
                 ],
                 []
               )
    end
  end

  test "load/3 with error for invalid release" do
    with_mocks([
      {System, [], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_gcp_release_error end]}
    ]) do
      config = [
        foundation: [
          {Foundation.ConfigProvider.Secrets.Manager,
           adapter: Foundation.ConfigProvider.Secrets.Aws, path: "any-env-path"},
          {:env, "not-set"},
          {:config_checksum, nil}
        ],
        deployex_web: [
          {DeployexWeb.Endpoint,
           [
             url: [host: "not-set", port: 443, scheme: "https"],
             http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: 999]
           ]}
        ],
        ex_aws: [region: "not-set"],
        observer_web: [mode: :observer, data_retention_period: 0]
      ]

      assert_raise RuntimeError, fn ->
        Config.load(config, [])
      end
    end
  end

  test "load/3 - Optional fields don't change if not passed in the YAML" do
    with_mocks([
      {System, [], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_optional end]}
    ]) do
      assert [
               {:observer_web, [mode: :observer, data_retention_period: 1000]},
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
                  {Deployer.Release,
                   [adapter: Deployer.Release.S3, bucket: "myapp-prod-distribution"]}
                ]},
               {:foundation,
                [
                  {:logs_retention_time_ms, 0},
                  {:deploy_rollback_timeout_ms, 0},
                  {:deploy_schedule_interval_ms, 0},
                  {:env, "prod"},
                  {:applications,
                   [
                     %{
                       env: [],
                       name: "myphoenixapp",
                       monitoring: [],
                       replicas: 3,
                       language: "elixir",
                       replica_ports: [%{base: 4000, key: "PORT"}]
                     }
                   ]},
                  {:config_checksum,
                   "f1d04d2f94b52f4564a7e93b926be090313799a0f8ae753d8e123a1f8f201de3"},
                  {:monitoring, []},
                  {Foundation.ConfigProvider.Secrets.Manager,
                   [
                     adapter: Foundation.ConfigProvider.Secrets.Aws,
                     path: "deployex-myapp-prod-secrets"
                   ]}
                ]}
             ] =
               Config.load(
                 [
                   observer_web: [mode: :observer, data_retention_period: 1000],
                   foundation: [
                     logs_retention_time_ms: 0,
                     deploy_rollback_timeout_ms: 0,
                     deploy_schedule_interval_ms: 0
                   ]
                 ],
                 []
               )
    end
  end

  test "load/3 with error for invalid secrets" do
    with_mocks([
      {System, [], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_gcp_secrets_error end]}
    ]) do
      config = [
        foundation: [
          {Foundation.ConfigProvider.Secrets.Manager,
           adapter: Foundation.ConfigProvider.Secrets.Aws, path: "any-env-path"},
          {:env, "not-set"},
          {:config_checksum, nil}
        ],
        deployex_web: [
          {DeployexWeb.Endpoint,
           [
             url: [host: "not-set", port: 443, scheme: "https"],
             http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: 999]
           ]}
        ],
        ex_aws: [region: "not-set"],
        observer_web: [mode: :observer, data_retention_period: 0]
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
           {:env, "not-set"},
           {:config_checksum, nil}
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
        {:observer_web, [mode: :observer, data_retention_period: 0]}
      ]

      assert capture_log(fn ->
               assert config == Config.load(config, [])
             end) =~
               "Error loading the YAML file, default configuration will be applied"
    end
  end
end
