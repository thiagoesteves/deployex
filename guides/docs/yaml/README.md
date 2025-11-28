# YAML Configuration and Management

## Overview

The YAML configuration file serves as the central configuration for DeployEx, controlling both installation and runtime behavior. DeployEx fetches this configuration from the path specified in `DEPLOYEX_CONFIG_YAML_PATH`.

## Installation

DeployEx can be installed directly on **Ubuntu 24.04/Debian** servers using the [deployex script](/devops/installer/deployex.sh) included in the release package. This script supports multiple operations using the same YAML configuration file:

```bash
Usage:
  ./deployex.sh --install [config_file] [--dist <base_url>]
  ./deployex.sh --update [config_file] [--dist <base_url>]
  ./deployex.sh --uninstall [config_file]
  ./deployex.sh --hot-upgrade <release_path> [config_file]
  ./deployex.sh --help
```

**Installation Commands:**
- `--install` - Initial DeployEx installation
- `--update` - Update existing DeployEx installation
- `--uninstall` - Remove DeployEx installation
- `--hot-upgrade` - Apply hot-upgrade to running DeployEx instance

For installation examples, see:
- [Calori Web Server - AWS Setup](https://github.com/thiagoesteves/calori/blob/main/devops/aws/terraform/modules/standard-account/cloud-config.tpl)
- [Calori Web Server - GCP Setup](https://github.com/thiagoesteves/calori/blob/main/devops/gcp/terraform/modules/standard-account/cloud-config.tpl)
- [Example YAML Configuration](/devops/installer/deployex-aws.yaml)

## Configuration Structure

```yaml
# ============================================================================
# DEPLOYEX CONFIGURATION
# ============================================================================

account_name: "prod"                                     # Cloud/Environment Account name
hostname: "deployex.myphoenixapp.com"                    # Deployex hostname
port: 5001                                               # Deployex port

# Release Distribution
release_adapter: "s3"                                    # Release adapter: s3, gcp-storage or local
release_bucket: "myphoenixapp-prod-distribution"         # Release distribution bucket name

# Secrets Management
secrets_adapter: "aws"                                   # Secrets adapter: aws, gcp or env
secrets_path: "deployex-myphoenixapp-prod-secrets"       # Secret path to retrieve from

# Cloud Provider Configuration
aws_region: "sa-east-1"                                  # AWS region (only for AWS)
google_credentials: "/home/ubuntu/gcp-config.json"       # Google credentials (only for GCP)

# System Configuration
version: "0.8.0"                                         # DeployEx version
otp_version: 28                                          # OTP version (must match monitored apps)
os_target: "ubuntu-24.04"                                # Target OS server

# Path Configuration (optional with defaults)
otp_tls_certificates: "/usr/local/share/ca-certificates" # Path to TLS certificates
install_path: "/opt/deployex"                            # DeployEx installation path (default: /opt/deployex)
var_path: "/var/lib/deployex"                            # DeployEx managed data path (default: /var/lib/deployex)
log_path: "/var/log/deployex"                            # DeployEx logs path (default: /var/log/deployex)
monitored_app_log_path: "/var/log/monitored-apps"        # Monitored apps log path (default: /var/log/monitored-apps)

# Data Retention (optional with defaults)
metrics_retention_time_ms: 3600000                       # Metrics retention: 1 hour (default: 3600000)
logs_retention_time_ms: 3600000                          # Logs retention: 1 hour (default: 3600000)

# ============================================================================
# HOST-LEVEL MONITORING (optional)
# ============================================================================

monitoring:
  - type: "memory"
    enable_restart: true           # Restart app if memory exceeds restart threshold (default: true)
    warning_threshold_percent: 75  # Issue warning at this memory usage (default: 75)
    restart_threshold_percent: 90  # Restart app at this memory usage (default: 90)

# ============================================================================
# MONITORED APPLICATIONS
# ============================================================================

applications:
  # --------------------------------------------------------------------------
  # Application: myphoenixapp
  # --------------------------------------------------------------------------
  - name: "myphoenixapp"               # App name (Elixir app name format)
    language: "elixir"                 # App language: elixir, erlang or gleam (default: elixir)
    replicas: 2                        # Number of replicas (default: 3)
    
    # Deployment Configuration (optional with defaults)
    deploy_rollback_timeout_ms: 600000 # Max deployment time before rollback (default: 600000)
    deploy_schedule_interval_ms: 5000  # Check for new deployments interval (default: 5000)
    
    # Port Configuration (optional)
    replica_ports:                     # Each replica gets: base + replica_index
      - key: PORT
        base: 4000                     # First replica: 4000, second: 4001, etc.
    
    # Environment Variables (optional)
    env:
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
    
    # Application-Level Monitoring (optional with defaults)
    monitoring:
      - type: "atom"                   # Monitor atom table usage
        enable_restart: true           # Restart if exceeded (default: true)
        warning_threshold_percent: 75  # Warning threshold (default: 75)
        restart_threshold_percent: 90  # Restart threshold (default: 90)
      - type: "process"                # Monitor process count
        enable_restart: true
        warning_threshold_percent: 75
        restart_threshold_percent: 90
      - type: "port"                   # Monitor port usage
        enable_restart: true
        warning_threshold_percent: 75
        restart_threshold_percent: 90

  # --------------------------------------------------------------------------
  # Application: myapp
  # --------------------------------------------------------------------------
  - name: "myapp"
    language: "elixir"
    replicas: 2
    
    replica_ports:
      - key: PORT
        base: 4040
    
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

DeployEx supports **runtime configuration upgrades** for certain settings, enabling dynamic updates without service interruption. Changes are automatically detected, validated, and presented in the UI for approval.

### Upgradable Configuration Fields

These fields can be modified and applied at runtime without restarting DeployEx:

#### DeployEx Level (Runtime Upgradable)
- `logs_retention_time_ms` - Log data retention period
- `metrics_retention_time_ms` - Metrics data retention period
- `monitoring` - Host-level monitoring settings (memory thresholds)

#### Application Level (Runtime Upgradable)
- `monitoring` - Application monitoring settings (atom, process, port thresholds)
- `language` - Application language (Elixir, Erlang, Gleam)
- `replicas` - Number of application instances
- `deploy_rollback_timeout_ms` - Deployment rollback timeout
- `deploy_schedule_interval_ms` - Deployment check interval
- `replica_ports` - Port configuration for replicas
- `env` - Environment variables

### Non-Upgradable Configuration Fields

These fields require a **full DeployEx restart**:

#### Core System Configuration
- `account_name` - Cloud/Environment identifier
- `hostname` - DeployEx hostname
- `port` - DeployEx port

#### Infrastructure Configuration
- `release_adapter` - Release distribution adapter
- `release_bucket` - Release bucket name
- `secrets_adapter` - Secrets provider
- `secrets_path` - Secrets path
- `aws_region` - AWS region
- `google_credentials` - GCP credentials path

#### System Requirements
- `version` - DeployEx version
- `otp_version` - OTP version
- `otp_tls_certificates` - TLS certificate path
- `os_target` - Target operating system

#### Installation Paths
- `install_path` - DeployEx installation directory
- `var_path` - Managed data directory
- `log_path` - DeployEx logs directory
- `monitored_app_log_path` - Monitored apps logs directory

### How Runtime Upgrades Work

1. **Automatic Detection** - DeployEx periodically checks the YAML file for changes using checksum comparison
2. **Validation** - Changes are validated to ensure only upgradable fields are modified
3. **UI Approval** - Detected changes appear in the UI for review and approval
4. **Application** - Approved changes are applied based on their upgrade type

### Runtime Upgrade Types

Each configuration change is classified by its application method:

| Type | Description | Service Impact |
|------|-------------|----------------|
| **immediate** | Applied instantly | No interruption |
| **next_deploy** | Applied during next deployment | Minimal interruption |
| **full_deploy** | Requires full redeployment | Service interruption |

> **Note:** When `full_deploy` changes are combined with other types, they are applied last after all other changes.

### Configuration Upgrade Examples

#### Example 1: Adjusting Monitoring Thresholds (Immediate)

```yaml
# Original configuration
monitoring:
  - type: "memory"
    enable_restart: true
    warning_threshold_percent: 75
    restart_threshold_percent: 90

# Updated configuration - applied immediately at runtime
monitoring:
  - type: "memory"
    enable_restart: true
    warning_threshold_percent: 80  # ✓ Increased threshold
    restart_threshold_percent: 95  # ✓ Increased threshold
```

#### Example 2: Scaling Application Replicas (Next Deploy)

```yaml
applications:
  - name: "myphoenixapp"
    language: "elixir"
    replicas: 3  # Changed from 2 to 3
    # Applied during next deployment cycle
```

#### Example 3: Updating Retention Policies (Immediate)

```yaml
# Original
metrics_retention_time_ms: 3600000  # 1 hour
logs_retention_time_ms: 3600000     # 1 hour

# Updated - applied immediately at runtime
metrics_retention_time_ms: 7200000  # ✓ 2 hours
logs_retention_time_ms: 10800000    # ✓ 3 hours
```

#### Example 4: Mixed Changes (Various Types)

```yaml
# Immediate changes
logs_retention_time_ms: 7200000

# Next deploy changes
applications:
  - name: "myphoenixapp"
    replicas: 3
    env:
      - key: NEW_FEATURE_FLAG
        value: true

# Full deploy required
port: 5002  # Changing DeployEx port requires restart
```