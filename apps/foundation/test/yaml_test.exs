defmodule Foundation.YamlTest do
  use ExUnit.Case, async: true

  alias Foundation.Yaml
  alias Foundation.Yaml.Application
  alias Foundation.Yaml.Monitoring
  alias Foundation.Yaml.Ports

  @sample_yaml_content """
  account_name: "prod"
  hostname: "deployex.example.com"
  port: 5001
  release_adapter: "gcp-storage"
  release_bucket: "myapp-prod-distribution"
  secrets_adapter: "gcp"
  secrets_path: "deployex-myapp-prod-secrets"
  aws_region: "sa-east-1"
  google_credentials: "/home/ubuntu/gcp-config.json"
  version: "0.7.3"
  otp_version: 28
  otp_tls_certificates: "/usr/local/share/ca-certificates"
  os_target: "ubuntu-24.04"
  deploy_rollback_timeout_ms: 600000
  deploy_schedule_interval_ms: 5000
  metrics_retention_time_ms: 3600000
  logs_retention_time_ms: 3600000
  monitoring:
    - type: "memory"
      enable_restart: true
      warning_threshold_percent: 75
      restart_threshold_percent: 85
  applications:
    - name: "myapp"
      language: "elixir"
      replicas: 3
      replica_ports:
        - key: PORT
          base: 4000
      env:
        - key: MYAPP_PHX_HOST
          value: "example.com"
        - key: MYAPP_PHX_SERVER
          value: true
        - key: MYAPP_OTP_TLS_CERT_PATH
          value: "/usr/local/share/ca-certificates"
      monitoring:
        - type: "atom"
          enable_restart: true
          warning_threshold_percent: 75
          restart_threshold_percent: 90
        - type: "process"
          enable_restart: true
          warning_threshold_percent: 75
          restart_threshold_percent: 90
        - type: "port"
          enable_restart: true
          warning_threshold_percent: 75
          restart_threshold_percent: 90
  """

  @sample_yaml_content_no_app """
  account_name: "prod"
  hostname: "deployex.example.com"
  port: 5001
  release_adapter: "gcp-storage"
  release_bucket: "myapp-prod-distribution"
  secrets_adapter: "gcp"
  secrets_path: "deployex-myapp-prod-secrets"
  aws_region: "sa-east-1"
  google_credentials: "/home/ubuntu/gcp-config.json"
  version: "0.7.3"
  otp_version: 28
  otp_tls_certificates: "/usr/local/share/ca-certificates"
  os_target: "ubuntu-24.04"
  deploy_rollback_timeout_ms: 600000
  deploy_schedule_interval_ms: 5000
  metrics_retention_time_ms: 3600000
  logs_retention_time_ms: 3600000
  monitoring:
    - type: "memory"
      enable_restart: true
      warning_threshold_percent: 75
      restart_threshold_percent: 85
  """

  describe "load/0" do
    setup do
      # Create a temporary YAML file for testing
      temp_dir = System.tmp_dir!()

      yaml_path =
        Path.join(temp_dir, "test_deployex_config_#{:erlang.unique_integer([:positive])}.yaml")

      File.write!(yaml_path, @sample_yaml_content)

      # Set the environment variable
      original_env = System.get_env("DEPLOYEX_CONFIG_YAML_PATH")
      System.put_env("DEPLOYEX_CONFIG_YAML_PATH", yaml_path)

      on_exit(fn ->
        File.rm(yaml_path)

        if original_env do
          System.put_env("DEPLOYEX_CONFIG_YAML_PATH", original_env)
        else
          System.delete_env("DEPLOYEX_CONFIG_YAML_PATH")
        end
      end)

      {:ok, yaml_path: yaml_path}
    end

    test "successfully loads and parses YAML configuration" do
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
      assert config.version == "0.7.3"
      assert config.otp_version == 28
      assert config.otp_tls_certificates == "/usr/local/share/ca-certificates"
      assert config.os_target == "ubuntu-24.04"
      assert config.deploy_rollback_timeout_ms == 600_000
      assert config.deploy_schedule_interval_ms == 5000
      assert config.metrics_retention_time_ms == 3_600_000
      assert config.logs_retention_time_ms == 3_600_000
    end

    test "successfully loads if the checksum is different or nil" do
      {:ok, config} = Yaml.load()
      {:ok, :unchanged} = Yaml.load(config)
      {:ok, ^config} = Yaml.load(%{config | config_checksum: "fsdfsdf"})
    end

    test "parses global monitoring configuration" do
      {:ok, config} = Yaml.load()

      assert length(config.monitoring) == 1

      [{:memory, monitoring}] = config.monitoring
      assert %Monitoring{} = monitoring
      assert monitoring.enable_restart == true
      assert monitoring.warning_threshold_percent == 75
      assert monitoring.restart_threshold_percent == 85
    end

    test "parses applications configuration" do
      {:ok, config} = Yaml.load()

      assert length(config.applications) == 1

      [app] = config.applications
      assert %Application{} = app
      assert app.name == "myapp"
      assert app.language == "elixir"
      assert app.replicas == 3
    end

    test "parses application replica_ports" do
      {:ok, config} = Yaml.load()

      [app] = config.applications
      assert length(app.replica_ports) == 1

      [port] = app.replica_ports
      assert %Ports{} = port
      assert port.key == "PORT"
      assert port.base == 4000
    end

    test "parses application environment variables" do
      {:ok, config} = Yaml.load()

      [app] = config.applications
      assert length(app.env) == 3

      assert [
               "MYAPP_PHX_HOST=example.com",
               "MYAPP_PHX_SERVER=true",
               "MYAPP_OTP_TLS_CERT_PATH=/usr/local/share/ca-certificates"
             ] = app.env
    end

    test "parses application monitoring configuration" do
      {:ok, config} = Yaml.load()

      [app] = config.applications
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

    @tag :capture_log
    test "returns error for non-existent file" do
      System.put_env("DEPLOYEX_CONFIG_YAML_PATH", "/path/to/nonexistent/file.yaml")

      assert {:error, _reason} = Yaml.load()
    end

    @tag :capture_log
    test "returns error for invalid YAML" do
      temp_dir = System.tmp_dir!()

      invalid_yaml_path =
        Path.join(temp_dir, "invalid_#{:erlang.unique_integer([:positive])}.yaml")

      File.write!(invalid_yaml_path, "invalid: yaml: content: [[[")
      System.put_env("DEPLOYEX_CONFIG_YAML_PATH", invalid_yaml_path)

      assert {:error, _reason} = Yaml.load()

      File.rm(invalid_yaml_path)
    end
  end

  describe "load/0 with no application defined" do
    setup do
      # Create a temporary YAML file for testing
      temp_dir = System.tmp_dir!()

      yaml_path =
        Path.join(temp_dir, "test_deployex_config_#{:erlang.unique_integer([:positive])}.yaml")

      File.write!(yaml_path, @sample_yaml_content_no_app)

      # Set the environment variable
      original_env = System.get_env("DEPLOYEX_CONFIG_YAML_PATH")
      System.put_env("DEPLOYEX_CONFIG_YAML_PATH", yaml_path)

      on_exit(fn ->
        File.rm(yaml_path)

        if original_env do
          System.put_env("DEPLOYEX_CONFIG_YAML_PATH", original_env)
        else
          System.delete_env("DEPLOYEX_CONFIG_YAML_PATH")
        end
      end)

      {:ok, yaml_path: yaml_path}
    end

    test "successfully loads with no app configured" do
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
      assert config.version == "0.7.3"
      assert config.otp_version == 28
      assert config.otp_tls_certificates == "/usr/local/share/ca-certificates"
      assert config.os_target == "ubuntu-24.04"
      assert config.deploy_rollback_timeout_ms == 600_000
      assert config.deploy_schedule_interval_ms == 5000
      assert config.metrics_retention_time_ms == 3_600_000
      assert config.logs_retention_time_ms == 3_600_000
      assert config.applications == []
    end
  end

  describe "secrets and release adapter cases" do
    test "Secres/Release for AWS" do
      yaml_without_monitoring = """
      account_name: "test"
      release_adapter: "s3"
      secrets_adapter: "aws"
      hostname: "test.example.com"
      port: 5000
      applications: []
      """

      temp_dir = System.tmp_dir!()
      yaml_path = Path.join(temp_dir, "minimal_#{:erlang.unique_integer([:positive])}.yaml")

      File.write!(yaml_path, yaml_without_monitoring)
      System.put_env("DEPLOYEX_CONFIG_YAML_PATH", yaml_path)

      {:ok, config} = Yaml.load()

      assert config.release_adapter == Deployer.Release.S3
      assert config.secrets_adapter == Foundation.ConfigProvider.Secrets.Aws

      File.rm(yaml_path)
    end

    test "Secres/Release for GCP" do
      yaml_without_monitoring = """
      account_name: "test"
      release_adapter: "gcp-storage"
      secrets_adapter: "gcp"
      hostname: "test.example.com"
      port: 5000
      applications: []
      """

      temp_dir = System.tmp_dir!()
      yaml_path = Path.join(temp_dir, "minimal_#{:erlang.unique_integer([:positive])}.yaml")

      File.write!(yaml_path, yaml_without_monitoring)
      System.put_env("DEPLOYEX_CONFIG_YAML_PATH", yaml_path)

      {:ok, config} = Yaml.load()

      assert config.release_adapter == Deployer.Release.GcpStorage
      assert config.secrets_adapter == Foundation.ConfigProvider.Secrets.Gcp

      File.rm(yaml_path)
    end
  end

  describe "parse/1 edge cases" do
    test "handles missing optional monitoring in global config" do
      yaml_without_monitoring = """
      account_name: "test"
      release_adapter: "s3"
      secrets_adapter: "aws"
      hostname: "test.example.com"
      port: 5000
      applications: []
      """

      temp_dir = System.tmp_dir!()
      yaml_path = Path.join(temp_dir, "minimal_#{:erlang.unique_integer([:positive])}.yaml")

      File.write!(yaml_path, yaml_without_monitoring)
      System.put_env("DEPLOYEX_CONFIG_YAML_PATH", yaml_path)

      {:ok, config} = Yaml.load()

      assert config.monitoring == []

      File.rm(yaml_path)
    end

    test "handles application without monitoring" do
      yaml_content = """
      account_name: "test"
      release_adapter: "s3"
      secrets_adapter: "aws"
      applications:
        - name: "simple-app"
          language: "elixir"
          replicas: 1
      """

      temp_dir = System.tmp_dir!()
      yaml_path = Path.join(temp_dir, "no_monitoring_#{:erlang.unique_integer([:positive])}.yaml")

      File.write!(yaml_path, yaml_content)
      System.put_env("DEPLOYEX_CONFIG_YAML_PATH", yaml_path)

      {:ok, config} = Yaml.load()

      [app] = config.applications
      assert app.monitoring == []

      File.rm(yaml_path)
    end

    test "handles application without env variables" do
      yaml_content = """
      account_name: "test"
      release_adapter: "s3"
      secrets_adapter: "aws"
      applications:
        - name: "simple-app"
          language: "elixir"
          replicas: 1
      """

      temp_dir = System.tmp_dir!()
      yaml_path = Path.join(temp_dir, "no_env_#{:erlang.unique_integer([:positive])}.yaml")

      File.write!(yaml_path, yaml_content)
      System.put_env("DEPLOYEX_CONFIG_YAML_PATH", yaml_path)

      {:ok, config} = Yaml.load()

      [app] = config.applications
      assert app.env == []

      File.rm(yaml_path)
    end

    test "handles application without replica_ports" do
      yaml_content = """
      account_name: "test"
      release_adapter: "s3"
      secrets_adapter: "aws"
      applications:
        - name: "simple-app"
          language: "elixir"
          replicas: 1
      """

      temp_dir = System.tmp_dir!()
      yaml_path = Path.join(temp_dir, "no_ports_#{:erlang.unique_integer([:positive])}.yaml")

      File.write!(yaml_path, yaml_content)
      System.put_env("DEPLOYEX_CONFIG_YAML_PATH", yaml_path)

      {:ok, config} = Yaml.load()

      [app] = config.applications
      assert app.replica_ports == []

      File.rm(yaml_path)
    end
  end

  describe "normalize_value/1" do
    test "converts different value types to strings" do
      yaml_with_various_types = """
      account_name: "test"
      release_adapter: "s3"
      secrets_adapter: "aws"
      applications:
        - name: "test-app"
          language: "elixir"
          replicas: 1
          env:
            - key: STRING_VALUE
              value: "string"
            - key: BOOLEAN_TRUE
              value: true
            - key: BOOLEAN_FALSE
              value: false
            - key: NUMBER_VALUE
              value: 123
      """

      temp_dir = System.tmp_dir!()
      yaml_path = Path.join(temp_dir, "types_#{:erlang.unique_integer([:positive])}.yaml")

      File.write!(yaml_path, yaml_with_various_types)
      System.put_env("DEPLOYEX_CONFIG_YAML_PATH", yaml_path)

      {:ok, config} = Yaml.load()

      [app] = config.applications

      assert [
               "STRING_VALUE=string",
               "BOOLEAN_TRUE=true",
               "BOOLEAN_FALSE=false",
               "NUMBER_VALUE=123"
             ] = app.env

      File.rm(yaml_path)
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
