defmodule Foundation.YamlTest do
  use ExUnit.Case, async: true

  import Mock

  alias Foundation.Yaml
  alias Foundation.Yaml.Application
  alias Foundation.Yaml.Monitoring
  alias Foundation.Yaml.Ports

  @file_paths "./test/support/files"
  @yaml_aws_default "#{@file_paths}/deployex-aws.yaml"
  @yaml_gcp_path "#{@file_paths}/deployex-gcp.yaml"
  @yaml_aws_monitoring "#{@file_paths}/deployex-aws-monitoring.yaml"
  @yaml_aws_monitoring_multiple_apps "#{@file_paths}/deployex-aws-monitoring-multiple-apps.yaml"
  @yaml_aws_optional "#{@file_paths}/deployex-aws-optional.yaml"
  @yaml_deployex_aws_no_replica_ports "#{@file_paths}/deployex-aws-no-replica-ports.yaml"

  describe "load/0" do
    test "successfully loads and parses YAML configuration" do
      with_mocks([
        {System, [:passthrough], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_gcp_path end]}
      ]) do
        {:ok, config} = Yaml.load()

        assert %Yaml{} = config
        assert config.account_name == "prod"
        assert config.hostname == "deployex.example.com"
        assert config.port == 5001
        assert config.release_adapter == Deployer.Release.GcpStorage
        assert config.release_bucket == "myapp-prod-distribution"
        assert config.secrets_adapter == Foundation.ConfigProvider.Secrets.Gcp
        assert config.secrets_path == "deployex-myapp-prod-secrets"
        assert config.google_credentials == "/home/ubuntu/gcp-config.json"
        assert config.version == "0.4.0"
        assert config.otp_version == 26
        assert config.otp_tls_certificates == nil
        assert config.os_target == "ubuntu-20.04"
        assert config.deploy_rollback_timeout_ms == 600_000
        assert config.deploy_schedule_interval_ms == 5000
        assert config.metrics_retention_time_ms == 3_600_000
        assert config.logs_retention_time_ms == 3_600_000
      end
    end

    test "successfully loads if the checksum is different or nil" do
      with_mocks([
        {System, [:passthrough], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_gcp_path end]}
      ]) do
        {:ok, config} = Yaml.load()
        {:error, :unchanged} = Yaml.load(config)
        {:ok, ^config} = Yaml.load(%{config | config_checksum: "fsdfsdf"})
      end
    end

    test "parses global monitoring configuration" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_monitoring end]}
      ]) do
        {:ok, config} = Yaml.load()

        assert length(config.monitoring) == 1

        [{:memory, monitoring}] = config.monitoring
        assert %Monitoring{} = monitoring
        assert monitoring.enable_restart == true
        assert monitoring.warning_threshold_percent == 75
        assert monitoring.restart_threshold_percent == 85
      end
    end

    test "parses applications configuration" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_monitoring end]}
      ]) do
        {:ok, config} = Yaml.load()

        assert length(config.applications) == 2

        [app | _rest] = config.applications
        assert %Application{} = app
        assert app.name == "myphoenixapp"
        assert app.language == "elixir"
        assert app.replicas == 3
      end
    end

    test "parses application replica_ports" do
      with_mocks([
        {System, [:passthrough], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_gcp_path end]}
      ]) do
        {:ok, config} = Yaml.load()

        [app | _rest] = config.applications
        assert length(app.replica_ports) == 1

        [port] = app.replica_ports
        assert %Ports{} = port
        assert port.key == "PORT"
        assert port.base == 4000
      end
    end

    test "parses application environment variables" do
      with_mocks([
        {System, [:passthrough], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_gcp_path end]}
      ]) do
        {:ok, config} = Yaml.load()

        [app | _rest] = config.applications
        assert length(app.env) == 2

        assert ["MYPHOENIXAPP_PHX_SERVER=false", "MYPHOENIXAPP_PHX_SERVER2=false"] = app.env
      end
    end

    test "parses application monitoring configuration" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_monitoring_multiple_apps end]}
      ]) do
        {:ok, config} = Yaml.load()

        [app | _rest] = config.applications
        assert length(app.monitoring) == 3

        monitoring_types = Enum.map(app.monitoring, fn {type, _monitoring} -> type end)
        assert :atom in monitoring_types
        assert :process in monitoring_types
        assert :port in monitoring_types

        Enum.each(app.monitoring, fn {_type, monitoring} ->
          assert %Monitoring{} = monitoring
          assert monitoring.enable_restart == true
          assert monitoring.warning_threshold_percent == 75
          assert monitoring.restart_threshold_percent == 90
        end)
      end
    end

    @tag :capture_log
    test "returns error for non-existent file" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> "/tmp/non_existing_file.yaml" end]}
      ]) do
        assert {:error, _reason} = Yaml.load()
      end
    end

    @tag :capture_log
    test "returns error for invalid YAML" do
      with_mocks([
        {System, [:passthrough], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> nil end]}
      ]) do
        assert {:error, _reason} = Yaml.load()
      end
    end
  end

  describe "load/0 with no application defined" do
    test "successfully loads with no app configured" do
      with_mocks([
        {System, [:passthrough], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_gcp_path end]}
      ]) do
        {:ok, config} = Yaml.load()

        assert %Yaml{} = config
        assert config.account_name == "prod"
        assert config.hostname == "deployex.example.com"
        assert config.port == 5001
        assert config.release_adapter == Deployer.Release.GcpStorage
        assert config.release_bucket == "myapp-prod-distribution"
        assert config.secrets_adapter == Foundation.ConfigProvider.Secrets.Gcp
        assert config.secrets_path == "deployex-myapp-prod-secrets"
        assert config.google_credentials == "/home/ubuntu/gcp-config.json"
        assert config.version == "0.4.0"
        assert config.otp_version == 26
        assert config.otp_tls_certificates == nil
        assert config.os_target == "ubuntu-20.04"
        assert config.deploy_rollback_timeout_ms == 600_000
        assert config.deploy_schedule_interval_ms == 5000
        assert config.metrics_retention_time_ms == 3_600_000
        assert config.logs_retention_time_ms == 3_600_000

        assert config.applications == [
                 %Foundation.Yaml.Application{
                   env: ["MYPHOENIXAPP_PHX_SERVER=false", "MYPHOENIXAPP_PHX_SERVER2=false"],
                   name: "myphoenixapp",
                   monitoring: [],
                   replicas: 3,
                   language: "elixir",
                   replica_ports: [%Foundation.Yaml.Ports{key: "PORT", base: 4000}]
                 },
                 %Foundation.Yaml.Application{
                   env: ["MYUMBRELLA_PHX_SERVER=false", "MYUMBRELLA_PHX_SERVER2=false"],
                   name: "myumbrella",
                   monitoring: [],
                   replicas: 2,
                   language: "erlang",
                   replica_ports: [%Foundation.Yaml.Ports{key: "PORT", base: 4050}]
                 }
               ]
      end
    end
  end

  describe "secrets and release adapter cases" do
    test "Secres/Release for AWS" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_default end]}
      ]) do
        {:ok, config} = Yaml.load()

        assert config.release_adapter == Deployer.Release.S3
        assert config.secrets_adapter == Foundation.ConfigProvider.Secrets.Aws
      end
    end

    test "Secres/Release for GCP" do
      with_mocks([
        {System, [:passthrough], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_gcp_path end]}
      ]) do
        {:ok, config} = Yaml.load()

        assert config.release_adapter == Deployer.Release.GcpStorage
        assert config.secrets_adapter == Foundation.ConfigProvider.Secrets.Gcp
      end
    end
  end

  describe "parse/1 edge cases" do
    test "handles missing optional monitoring in global config" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_optional end]}
      ]) do
        {:ok, config} = Yaml.load()

        assert config.monitoring == []
      end
    end

    test "handles application without monitoring" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_optional end]}
      ]) do
        {:ok, config} = Yaml.load()

        [app] = config.applications
        assert app.monitoring == []
      end
    end

    test "handles application without env variables" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_optional end]}
      ]) do
        {:ok, config} = Yaml.load()

        [app] = config.applications
        assert app.env == []
      end
    end

    test "handles application without replica_ports" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_deployex_aws_no_replica_ports end]}
      ]) do
        {:ok, config} = Yaml.load()

        [app] = config.applications
        assert app.replica_ports == []
      end
    end
  end

  describe "normalize_value/1" do
    test "converts different value types to strings" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_default end]}
      ]) do
        {:ok, config} = Yaml.load()

        [app | _rest] = config.applications

        assert [
                 "STRING_VALUE=string",
                 "BOOLEAN_TRUE=true",
                 "BOOLEAN_FALSE=false",
                 "NUMBER_VALUE=123"
               ] = app.env
      end
    end
  end

  describe "struct types" do
    test "Monitoring struct has correct fields" do
      monitoring = %Monitoring{
        enable_restart: true,
        warning_threshold_percent: 75,
        restart_threshold_percent: 85
      }

      assert monitoring.enable_restart == true
      assert monitoring.warning_threshold_percent == 75
      assert monitoring.restart_threshold_percent == 85
    end

    test "Ports struct has correct fields" do
      port = %Ports{key: "PORT", base: 4000}

      assert port.key == "PORT"
      assert port.base == 4000
    end

    test "Application struct has correct fields" do
      app = %Application{
        name: "test-app",
        language: "elixir",
        replicas: 3,
        replica_ports: [],
        env: [],
        monitoring: []
      }

      assert app.name == "test-app"
      assert app.language == "elixir"
      assert app.replicas == 3
    end
  end
end
