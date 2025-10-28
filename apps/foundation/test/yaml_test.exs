defmodule Foundation.YamlTest do
  use ExUnit.Case, async: true

  alias Foundation.Yaml
  alias Foundation.Yaml.Application
  alias Foundation.Yaml.KV
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
      assert config.release_adapter == "gcp-storage"
      assert config.release_bucket == "myapp-prod-distribution"
      assert config.secrets_adapter == "gcp"
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

    test "parses global monitoring configuration" do
      {:ok, config} = Yaml.load()

      assert length(config.monitoring) == 1

      [monitoring] = config.monitoring
      assert %Monitoring{} = monitoring
      assert monitoring.type == "memory"
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

      env_map = Map.new(app.env, fn %KV{key: k, value: v} -> {k, v} end)

      assert env_map["MYAPP_PHX_HOST"] == "example.com"
      # boolean converted to string
      assert env_map["MYAPP_PHX_SERVER"] == "true"
      assert env_map["MYAPP_OTP_TLS_CERT_PATH"] == "/usr/local/share/ca-certificates"
    end

    test "parses application monitoring configuration" do
      {:ok, config} = Yaml.load()

      [app] = config.applications
      assert length(app.monitoring) == 3

      monitoring_types = Enum.map(app.monitoring, & &1.type)
      assert "atom" in monitoring_types
      assert "process" in monitoring_types
      assert "port" in monitoring_types

      Enum.each(app.monitoring, fn monitoring ->
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

  describe "parse/1 edge cases" do
    test "handles missing optional monitoring in global config" do
      yaml_without_monitoring = """
      account_name: "test"
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
      env_map = Map.new(app.env, fn %KV{key: k, value: v} -> {k, v} end)

      assert env_map["STRING_VALUE"] == "string"
      assert env_map["BOOLEAN_TRUE"] == "true"
      assert env_map["BOOLEAN_FALSE"] == "false"
      assert env_map["NUMBER_VALUE"] == "123"

      File.rm(yaml_path)
    end
  end

  describe "struct types" do
    test "Monitoring struct has correct fields" do
      monitoring = %Monitoring{
        type: "memory",
        enable_restart: true,
        warning_threshold_percent: 75,
        restart_threshold_percent: 85
      }

      assert monitoring.type == "memory"
      assert monitoring.enable_restart == true
      assert monitoring.warning_threshold_percent == 75
      assert monitoring.restart_threshold_percent == 85
    end

    test "Ports struct has correct fields" do
      port = %Ports{key: "PORT", base: 4000}

      assert port.key == "PORT"
      assert port.base == 4000
    end

    test "KV struct has correct fields" do
      kv = %KV{key: "TEST_KEY", value: "test_value"}

      assert kv.key == "TEST_KEY"
      assert kv.value == "test_value"
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
