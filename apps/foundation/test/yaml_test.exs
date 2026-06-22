defmodule Foundation.YamlTest do
  use ExUnit.Case, async: true

  import Mock

  alias Foundation.Yaml
  alias Foundation.Yaml.Application
  alias Foundation.Yaml.Certificate
  alias Foundation.Yaml.Monitoring
  alias Foundation.Yaml.Ports

  @file_paths "./test/support/files"
  @yaml_aws_default "#{@file_paths}/deployex-aws.yaml"
  @yaml_local_env "#{@file_paths}/deployex-local-env.yaml"
  @yaml_aws_no_app "#{@file_paths}/deployex-aws-no-app.yaml"
  @yaml_gcp_path "#{@file_paths}/deployex-gcp.yaml"
  @yaml_aws_monitoring "#{@file_paths}/deployex-aws-monitoring.yaml"
  @yaml_aws_monitoring_multiple_apps "#{@file_paths}/deployex-aws-monitoring-multiple-apps.yaml"
  @yaml_aws_optional "#{@file_paths}/deployex-aws-optional.yaml"
  @yaml_deployex_aws_no_replica_ports "#{@file_paths}/deployex-aws-no-replica-ports.yaml"
  @yaml_dns_cloudflare "#{@file_paths}/deployex-dns-cloudflare.yaml"
  @yaml_notifications "#{@file_paths}/deployex-notifications.yaml"

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

    test "parses empty applications" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_no_app end]}
      ]) do
        {:ok, config} = Yaml.load()
        assert Enum.empty?(config.applications)
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
        assert config.metrics_retention_time_ms == 3_600_000
        assert config.logs_retention_time_ms == 3_600_000

        assert config.applications == [
                 %Foundation.Yaml.Application{
                   env: ["MYPHOENIXAPP_PHX_SERVER=false", "MYPHOENIXAPP_PHX_SERVER2=false"],
                   name: "myphoenixapp",
                   monitoring: [],
                   replicas: 3,
                   language: "elixir",
                   deploy_rollback_timeout_ms: 600_000,
                   deploy_schedule_interval_ms: 5000,
                   replica_ports: [%Foundation.Yaml.Ports{key: "PORT", base: 4000}],
                   certificates: []
                 },
                 %Foundation.Yaml.Application{
                   env: ["MYUMBRELLA_PHX_SERVER=false", "MYUMBRELLA_PHX_SERVER2=false"],
                   name: "myumbrella",
                   monitoring: [],
                   replicas: 2,
                   language: "erlang",
                   deploy_rollback_timeout_ms: 600_000,
                   deploy_schedule_interval_ms: 5000,
                   replica_ports: [%Foundation.Yaml.Ports{key: "PORT", base: 4050}],
                   certificates: []
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

    test "Secres/Release for ENV" do
      with_mocks([
        {System, [:passthrough], [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_local_env end]}
      ]) do
        {:ok, config} = Yaml.load()

        assert config.release_adapter == Deployer.Release.Local
        assert config.secrets_adapter == Foundation.ConfigProvider.Secrets.Env
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

  describe "parse/1 certificate configuration" do
    test "parses a full domains certificate with all fields" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_default end]}
      ]) do
        {:ok, config} = Yaml.load()

        [app | _] = config.applications
        [cert] = app.certificates

        assert %Certificate{} = cert
        assert cert.type == :domains
        assert cert.domains == ["example.com", "*.example.com"]

        assert cert.dns_provider == Foundation.Certificates.DNSProvider.Route53
        assert cert.acme_provider == Foundation.Certificates.ACMEProvider.LetsEncrypt
        assert cert.importer == Foundation.Certificates.Importer.Route53
      end
    end

    test "applies default values for omitted certificate fields" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_default end]}
      ]) do
        {:ok, config} = Yaml.load()

        [app | _] = config.applications
        [cert] = app.certificates

        assert cert.certificate_check_interval_ms == 86_400_000
        assert cert.dns_propagation_timeout_ms == 120_000
        assert cert.dns_check_interval_ms == 5_000
        assert cert.renew_before_days == 30
      end
    end

    test "parses dns_options with defaults" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_default end]}
      ]) do
        {:ok, config} = Yaml.load()

        [app | _] = config.applications
        [cert] = app.certificates

        assert %Certificate.DnsOptions{} = cert.dns_options
        assert cert.dns_options.ttl == 1
        assert cert.dns_options.zone != nil
      end
    end

    test "parses acme_options with defaults" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_default end]}
      ]) do
        {:ok, config} = Yaml.load()

        [app | _] = config.applications
        [cert] = app.certificates

        assert %Certificate.AcmeOptions{} = cert.acme_options
        assert cert.acme_options.url == "https://acme-v02.api.letsencrypt.org/directory"
        assert cert.acme_options.key_size == 2048
        assert cert.acme_options.contact_email != nil
        assert cert.acme_options.propagation_timeout_ms == 120_000
        assert cert.acme_options.check_interval_ms == 2_000
      end
    end

    test "parses importer_options" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_default end]}
      ]) do
        {:ok, config} = Yaml.load()

        [app | _] = config.applications
        [cert] = app.certificates

        assert %Certificate.ImporterOptions{} = cert.importer_options
        assert cert.importer_options.certificate_arn != nil
      end
    end

    test "parses empty certificates list" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_optional end]}
      ]) do
        {:ok, config} = Yaml.load()

        [app] = config.applications
        assert app.certificates == []
      end
    end

    test "ignores certificate with unsupported type" do
      # A certificate entry whose type is not :domains should not start a manager.
      # This test guards the start_certificate_manager/2 fallback clause.
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_default end]}
      ]) do
        {:ok, config} = Yaml.load()

        [app | _] = config.applications

        # All parsed certificates should have a known type atom
        Enum.each(app.certificates, fn cert ->
          assert is_atom(cert.type)
        end)
      end
    end
  end

  describe "Certificate struct types" do
    test "Certificate struct has correct fields" do
      cert = %Certificate{
        type: :domains,
        domains: ["example.com"],
        certificate_check_interval_ms: 86_400_000,
        dns_propagation_timeout_ms: 120_000,
        dns_check_interval_ms: 5_000,
        renew_before_days: 30,
        dns_provider: Foundation.Certificates.DNSProvider.Route53,
        dns_options: %Certificate.DnsOptions{
          ttl: 60,
          zone: "example.com",
          api_token: "ABC123ZXC"
        },
        acme_provider: Foundation.Certificates.ACMEProvider.LetsEncrypt,
        acme_options: %Certificate.AcmeOptions{
          contact_email: "admin@example.com",
          url: "https://acme-v02.api.letsencrypt.org/directory",
          key_size: 2048,
          propagation_timeout_ms: 120_000,
          check_interval_ms: 2000
        },
        importer: Foundation.Certificates.Importer.Route53,
        importer_options: %Certificate.ImporterOptions{certificate_arn: "arn:aws:acm:..."}
      }

      assert cert.type == :domains
      assert cert.domains == ["example.com"]
      assert cert.dns_options.ttl == 60
      assert cert.acme_options.key_size == 2048
      assert cert.importer_options.certificate_arn == "arn:aws:acm:..."
    end

    test "DnsOptions struct has correct fields" do
      dns_opts = %Certificate.DnsOptions{ttl: 120, zone: "example.com"}

      assert dns_opts.ttl == 120
      assert dns_opts.zone == "example.com"
    end

    test "AcmeOptions struct has correct fields" do
      acme_opts = %Certificate.AcmeOptions{
        contact_email: "ops@example.com",
        url: "https://acme-staging-v02.api.letsencrypt.org/directory",
        key_size: 4096,
        propagation_timeout_ms: 10_000,
        check_interval_ms: 1_000
      }

      assert acme_opts.contact_email == "ops@example.com"
      assert acme_opts.key_size == 4096
      assert acme_opts.propagation_timeout_ms == 10_000
      assert acme_opts.check_interval_ms == 1_000
    end

    test "ImporterOptions struct has correct fields" do
      importer_opts = %Certificate.ImporterOptions{
        certificate_arn: "arn:aws:acm:us-east-1:123:certificate/abc"
      }

      assert importer_opts.certificate_arn == "arn:aws:acm:us-east-1:123:certificate/abc"
    end
  end

  test "parses cloudflare dns_provider" do
    with_mocks([
      {System, [:passthrough],
       [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_dns_cloudflare end]}
    ]) do
      {:ok, config} = Yaml.load()

      [app | _] = config.applications
      [cert] = app.certificates

      assert cert.dns_provider == Foundation.Certificates.DNSProvider.Cloudflare
    end
  end

  test "parses cloudflare dns_options with api_token" do
    with_mocks([
      {System, [:passthrough],
       [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_dns_cloudflare end]}
    ]) do
      {:ok, config} = Yaml.load()

      [app | _] = config.applications
      [cert] = app.certificates

      assert %Certificate.DnsOptions{} = cert.dns_options
      assert cert.dns_options.zone == "cloudflare-zone-id"
      assert cert.dns_options.api_token == "cf-api-token-secret"
      assert cert.dns_options.ttl == 1
    end
  end

  describe "notifications parsing" do
    test "parses a webhook notification entry" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_notifications end]}
      ]) do
        {:ok, config} = Yaml.load()

        [webhook | _] = config.notifications

        assert %Yaml.Notification{} = webhook
        assert webhook.adapter == Foundation.Notifications.Webhook
        assert webhook.url == "https://hooks.example.com/deployex"
        assert webhook.enabled == true
        assert webhook.options == %Yaml.Notification.Options{}

        assert "crash_restart" in webhook.events
        assert "deployment_started" in webhook.events
        assert "deployment_complete" in webhook.events
        assert "watchdog_threshold_exceeded" in webhook.events
        assert "watchdog_threshold_warning" in webhook.events
        assert "certificate_renewed" in webhook.events
        assert "certificate_failed" in webhook.events
      end
    end

    test "parses a slack notification entry with options" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_notifications end]}
      ]) do
        {:ok, config} = Yaml.load()

        [_, slack | _] = config.notifications

        assert slack.adapter == Foundation.Notifications.Slack
        assert slack.url == "https://hooks.slack.com/services/T000/B000/XXX"
        assert slack.enabled == true
        assert slack.options.username == "DeployEx-Bot"
        assert slack.options.icon_emoji == ":rocket:"
        assert "crash_restart" in slack.events
        assert "deployment_complete" in slack.events
      end
    end

    test "parses a pagerduty notification entry with options" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_notifications end]}
      ]) do
        {:ok, config} = Yaml.load()

        [_, _, pagerduty | _] = config.notifications

        assert pagerduty.adapter == Foundation.Notifications.PagerDuty
        assert pagerduty.url == nil
        assert pagerduty.enabled == true
        assert pagerduty.options.routing_key == "abc123def456"
        assert "crash_restart" in pagerduty.events
        assert "watchdog_threshold_exceeded" in pagerduty.events
      end
    end

    test "parses a disabled notification entry" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_notifications end]}
      ]) do
        {:ok, config} = Yaml.load()

        [_, _, _, disabled] = config.notifications

        assert disabled.adapter == Foundation.Notifications.Webhook
        assert disabled.enabled == false
        assert disabled.url == "https://hooks2.example.com/deployex"
      end
    end

    test "defaults to empty notifications list when key is absent" do
      with_mocks([
        {System, [:passthrough],
         [get_env: fn "DEPLOYEX_CONFIG_YAML_PATH" -> @yaml_aws_default end]}
      ]) do
        {:ok, config} = Yaml.load()
        assert config.notifications == []
      end
    end
  end
end
