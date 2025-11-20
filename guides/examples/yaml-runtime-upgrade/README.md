# YAML Configuration and Management

Once DeployEx runs, it fetches the configuration from the YAML file described in the path `DEPLOYEX_CONFIG_YAML_PATH`. The YAML file configuration contains the following fields:

```yaml
account_name: "prod"                                     # Deployex: Cloud/Environment Account name
hostname: "deployex.myphoenixapp.com"                    # Deployex: hostname
port: 5001                                               # Deployex: port
release_adapter: "s3"                                    # Deployex: release adapter type s3, gcp-storage or local
release_bucket: "myphoenixapp-prod-distribution"         # Deployex: release distribution bucket name
secrets_adapter: "aws"                                   # Deployex: secrets adapter type aws, gcp or env
secrets_path: "deployex-myphoenixapp-prod-secrets"       # Deployex: secret path to be retrieved from
aws_region: "sa-east-1"                                  # Deployex: aws region (only for AWS)
google_credentials: "/home/ubuntu/gcp-config.json"       # Deployex: google credentials (only for GCP)
version: "0.8.0"                                         # Deployex: Version
otp_version: 28                                          # Deployex: Otp version (It needs to match the monitored applications)
os_target: "ubuntu-24.04"                                # Deployex: Target OS server
otp_tls_certificates: "/usr/local/share/ca-certificates" # Deployex (optional): Path to the certificates that will be consumed by Deployex
install_path: "/opt/deployex"                            # Deployex (optional, default: /opt/deployex): Path to Deployex installation in the host
var_path: "/var/lib/deployex"                            # Deployex (optional, default: /var/lib/deployex): Path to Deployex managed data
metrics_retention_time_ms: 3600000                       # Deployex (optional, default: 3600000): Retention time for metrics
logs_retention_time_ms: 3600000                          # Deployex (optional, default: 3600000): Retention time for logs
monitoring:                        # Deployex (optional, default: values described in memory): Monitoring features
  - type: "memory"
    enable_restart: true           # Deployex (default: true): Restart app if memory usage exceeds 'restart_threshold_percent'
    warning_threshold_percent: 75  # Deployex (default: 75): Issue a warning if memory usage exceeds this percent
    restart_threshold_percent: 90  # Deployex (default: 90): Restart app if memory usage exceeds this percent
applications:
  - name: "myphoenixapp"               # Application: Monitored app name (Elixir app name format)
    language: "elixir"                 # Application: (optional, default: elixir) App language (elixir, erlang or gleam)
    replicas: 2                        # Application: (optional, default: 3) Number of replicas
    deploy_rollback_timeout_ms: 600000 # Application: (optional, default: 600000): The maximum time allowed for attempting a deployment before considering the version as non-deployable and rolling back
    deploy_schedule_interval_ms: 5000  # Application: (optional, default: 5000): Periodic checking for new deployments
    replica_ports:                     # Application: (optional) Each instance receives a different port in the range (base + replicas)
      - key: PORT
        base: 4000
    env:                               # Application (optional): Environment variables
      - key: MYPHOENIXAPP_PHX_HOST
        value: "myphoenixapp.com"
      - key: MYPHOENIXAPP_PHX_SERVER
        value: true
      - key: MYPHOENIXAPP_CLOUD_ENVIRONMENT
        value: "prod"
      - key: MYPHOENIXAPP_OTP_TLS_CERT_PATH
        value: "/usr/local/share/ca-certificates"
      - key: MYPHOENIXAPP_SECRETS_ADAPTER
        value: "aws"
      - key: MYPHOENIXAPP_SECRETS_PATH
        value: "myphoenixapp-prod-secrets"
      - key: AWS_REGION
        value: "sa-east-1"
    monitoring:                       # Application (optional, default: values described in atom, process and port): Monitoring features
      - type: "atom"
        enable_restart: true          # Application (default: true): Restart app if memory usage exceeds 'restart_threshold_percent'
        warning_threshold_percent: 75 # Application (default: 75): Issue a warning if memory usage exceeds this percent
        restart_threshold_percent: 90 # Application (default: 90): Restart app if memory usage exceeds this percent
      - type: "process"
        enable_restart: true
        warning_threshold_percent: 75
        restart_threshold_percent: 90
      - type: "port"
        enable_restart: true
        warning_threshold_percent: 75
        restart_threshold_percent: 90
  - name: "myapp"
    language: "elixir"
    replica_ports:
      - key: PORT
        base: 4040
    replicas: 2
    env:
      - key: MYAPP_PHX_HOST
        value: "myapp.com"
      - key: MYAPP_PHX_SERVER
        value: true
      - key: MYAPP_CLOUD_ENVIRONMENT
        value: "prod"
      - key: MYAPP_OTP_TLS_CERT_PATH
        value: "/usr/local/share/ca-certificates"
      - key: MYAPP_SECRETS_ADAPTER
        value: "aws"
      - key: MYAPP_SECRETS_PATH
        value: "myapp-prod-secrets"
      - key: AWS_REGION
        value: "sa-east-1"
```

## Runtime Configuration Upgrades

DeployEx supports **runtime configuration upgrades** for certain settings, eliminating the need for system restarts when modifying specific configuration values. This feature enables dynamic updates to monitoring thresholds, application settings, and retention policies without service interruption.

### Upgradable Configuration Fields

The following fields can be modified in the YAML configuration file and will be automatically applied at runtime:

#### DeployEx Level
- `logs_retention_time_ms` - How long to retain log data
- `metrics_retention_time_ms` - How long to retain metrics data
- `monitoring` - Host-level monitoring settings (memory thresholds)

#### Application Level
- `monitoring` - Application-specific monitoring settings (atom, process, port thresholds)
- `language` - Application language (Elixir, Erlang or Gleam)
- `replicas` - Number of application instances
- `deploy_rollback_timeout_ms` - Deployment rollback timeout
- `deploy_schedule_interval_ms` - Deployment check interval
- `replica_ports` - Port configuration for replicas
- `env` - Environment variables for applications

### Non-Upgradable Configuration Fields

These fields require a **full DeployEx restart** to take effect:

- `account_name` - Cloud/Environment account identifier
- `hostname` - DeployEx hostname
- `port` - DeployEx port
- `release_adapter` - Release distribution adapter (s3, gcp-storage or local)
- `release_bucket` - Release distribution bucket name
- `secrets_adapter` - Secrets provider (aws, gcp or env)
- `secrets_path` - Path to secrets in provider
- `aws_region` - AWS region configuration
- `google_credentials` - GCP credentials file path
- `version` - DeployEx version
- `otp_version` - OTP version
- `otp_tls_certificates` - TLS certificate path
- `os_target` - Target operating system

### How Runtime Upgrades Work

1. **Automatic Detection**: DeployEx periodically checks the YAML configuration file for changes using checksum comparison
2. **Validation**: Changes are validated to ensure they contain only upgradable fields
3. **Application**: Once the upgradable changes are approved (via UI/UX), changes will be applied immediately without restarting DeployEx

### Runtime Upgrades types

Once the changes are detected, they will appear in the UI for approval. Each value will be presented with an apply method, which can be one of the following:

 * **immediate** – Applied instantly without requiring a deployment.
 * **next_deploy** – Takes effect during the next scheduled deployment.
 * **full_deploy** – Requires a full redeployment and may cause a service interruption.

> [!IMPORTANT]
> When `full_deploy` is combined with other changes, it will be applied last. All other changes will be applied first.

### Configuration Upgrade Examples

#### Example 1: Adjusting Monitoring Thresholds

```yaml
# Original configuration
monitoring:
  - type: "memory"
    enable_restart: true
    warning_threshold_percent: 75
    restart_threshold_percent: 90

# Updated configuration (applied at runtime)
monitoring:
  - type: "memory"
    enable_restart: true
    warning_threshold_percent: 80  # Increased threshold
    restart_threshold_percent: 95  # Increased threshold
```

#### Example 2: Scaling Application Replicas

```yaml
applications:
  - name: "myphoenixapp"
    language: "elixir"
    replicas: 2  # Changed from 3 to 2 - applied at runtime
    # ... other settings
```

#### Example 3: Updating Retention Policies

```yaml
# Original
metrics_retention_time_ms: 3600000  # 1 hour
logs_retention_time_ms: 3600000     # 1 hour

# Updated (applied at runtime)
metrics_retention_time_ms: 7200000  # 2 hours
logs_retention_time_ms: 10800000    # 3 hours
```