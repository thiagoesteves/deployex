defmodule Foundation.ConfigProvider.Env.ConfigTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mock

  alias Foundation.ConfigProvider.Env.Config

  @file_paths "./test/support/files"

  @yaml_aws_default "#{@file_paths}/deployex-aws.yaml"
  @yaml_local_env "#{@file_paths}/deployex-local-env.yaml"
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
      {System, [:passthrough], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_default end]}
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
                       deploy_rollback_timeout_ms: 600_000,
                       deploy_schedule_interval_ms: 5_000,
                       replica_ports: [%{base: 4050, key: "PORT"}]
                     }
                   ]},
                  {:config_checksum,
                   "5d6ee0b036f41e901aec5dd4d6a2af087d96040402a9ade329573795540bb8a1"},
                  {:monitoring, []},
                  {:logs_retention_time_ms, 3_600_000},
                  {:install_path, "/opt/deployex"},
                  {:var_path, "/var/lib/deployex"},
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
                     {:install_path, "any-path"},
                     {:var_path, "any-path"},
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

  test "load/3 with success for AWS for secrets from environment" do
    with_mock System, [:passthrough],
      get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_local_env end do
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
                   [adapter: Deployer.Release.Local, bucket: "myapp-prod-distribution"]}
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
                       deploy_rollback_timeout_ms: 600_000,
                       deploy_schedule_interval_ms: 5_000,
                       replica_ports: [%{base: 4050, key: "PORT"}]
                     }
                   ]},
                  {:config_checksum,
                   "80b62c3694c0311d2d9567fbf777b419bced562b5bd5196432d811faf128f845"},
                  {:monitoring, []},
                  {:logs_retention_time_ms, 3_600_000},
                  {:install_path, "/opt/deployex"},
                  {:var_path, "/var/lib/deployex"},
                  {Foundation.ConfigProvider.Secrets.Manager,
                   [
                     adapter: Foundation.ConfigProvider.Secrets.Env,
                     path: "deployex-myapp-prod-secrets"
                   ]}
                ]}
             ] =
               Config.load(
                 [
                   foundation: [
                     {Foundation.ConfigProvider.Secrets.Manager,
                      adapter: Foundation.ConfigProvider.Secrets.Env, path: "any-env-path"},
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
                     {:install_path, "any-path"},
                     {:var_path, "any-path"},
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
      {System, [:passthrough],
       [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_monitoring end]}
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
                       deploy_rollback_timeout_ms: 600_000,
                       deploy_schedule_interval_ms: 5_000,
                       replica_ports: [%{base: 4050, key: "PORT"}]
                     }
                   ]},
                  {:config_checksum,
                   "e07879b0aa766c6a8a7bf8b44ae65e1ed62ab0c5db3c9bedd83802d577a28513"},
                  {:monitoring,
                   [
                     memory: %Foundation.Yaml.Monitoring{
                       enable_restart: true,
                       warning_threshold_percent: 75,
                       restart_threshold_percent: 85
                     }
                   ]},
                  {:logs_retention_time_ms, 3_600_000},
                  {:install_path, "/opt/install/deployex"},
                  {:var_path, "/var/lib/install/deployex"},
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
      {System, [:passthrough],
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
                       deploy_rollback_timeout_ms: 600_000,
                       deploy_schedule_interval_ms: 5_000,
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
                       deploy_rollback_timeout_ms: 600_000,
                       deploy_schedule_interval_ms: 5_000,
                       replica_ports: [%{base: 4050, key: "PORT"}]
                     }
                   ]},
                  {:config_checksum,
                   "ba24931b10e4dea96ac3b978a0f3737ff740da082059df6401b2cb9ff44485e1"},
                  {:monitoring,
                   [
                     memory: %Foundation.Yaml.Monitoring{
                       enable_restart: true,
                       warning_threshold_percent: 75,
                       restart_threshold_percent: 85
                     }
                   ]},
                  {:logs_retention_time_ms, 3_600_000},
                  {:install_path, "/opt/deployex"},
                  {:var_path, "/var/lib/deployex"},
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
      {System, [:passthrough], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_gcp_path end]}
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
                       deploy_rollback_timeout_ms: 600_000,
                       deploy_schedule_interval_ms: 5_000,
                       replica_ports: [%{base: 4000, key: "PORT"}]
                     },
                     %{
                       env: ["MYUMBRELLA_PHX_SERVER=false", "MYUMBRELLA_PHX_SERVER2=false"],
                       name: "myumbrella",
                       monitoring: [],
                       replicas: 2,
                       language: "erlang",
                       deploy_rollback_timeout_ms: 600_000,
                       deploy_schedule_interval_ms: 5_000,
                       replica_ports: [%{base: 4050, key: "PORT"}]
                     }
                   ]},
                  {:config_checksum,
                   "fe80f57a7516d81ebb63012ef3714ec5b0a7046b49dc90a6cc84f42199174699"},
                  {:monitoring, []},
                  {:logs_retention_time_ms, 3_600_000},
                  {:install_path, "/opt/install/deployex"},
                  {:var_path, "/var/lib/install/deployex"},
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
      {System, [:passthrough],
       [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_gcp_release_error end]}
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

  test "load/3 - Optional fields are initialized with default values from YAML" do
    with_mocks([
      {System, [:passthrough],
       [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_optional end]}
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
               {:observer_web, [mode: :observer, data_retention_period: 3_600_000]},
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
                       env: [],
                       name: "myphoenixapp",
                       monitoring: [],
                       replicas: 3,
                       language: "elixir",
                       deploy_rollback_timeout_ms: 600_000,
                       deploy_schedule_interval_ms: 5000,
                       replica_ports: [%{base: 4000, key: "PORT"}]
                     }
                   ]},
                  {:config_checksum,
                   "5c1d8cb90a8661ac4fefad8d1ad2aa760d4d7257f61bd310e9aadf31c3b97968"},
                  {:monitoring, []},
                  {:logs_retention_time_ms, 3_600_000},
                  {:install_path, "/opt/deployex"},
                  {:var_path, "/var/lib/deployex"},
                  {Foundation.ConfigProvider.Secrets.Manager,
                   [
                     adapter: Foundation.ConfigProvider.Secrets.Aws,
                     path: "deployex-myapp-prod-secrets"
                   ]}
                ]}
             ] =
               Config.load(
                 [
                   observer_web: [mode: :observer, data_retention_period: 0],
                   foundation: [
                     logs_retention_time_ms: 0
                   ]
                 ],
                 []
               )
    end
  end

  test "load/3 with error for invalid secrets" do
    with_mocks([
      {System, [:passthrough],
       [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_gcp_secrets_error end]}
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
      {System, [:passthrough], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> "." end]}
    ]) do
      config = [
        {:foundation,
         [
           {Foundation.ConfigProvider.Secrets.Manager,
            adapter: Foundation.ConfigProvider.Secrets.Gcp, path: "any-env-path"},
           {:env, "not-set"},
           {:logs_retention_time_ms, 0},
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

  test "load/3 Yaml file not found, keep the configuration" do
    with_mocks([
      {System, [:passthrough], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> nil end]}
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
               "DEPLOYEX_CONFIG_YAML_PATH not defined, default configuration will be applied"
    end
  end
end
