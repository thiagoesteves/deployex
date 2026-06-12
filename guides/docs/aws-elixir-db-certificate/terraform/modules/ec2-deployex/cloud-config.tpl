#cloud-config
#
#  Cloud init template for EC2 myappname instances.
#
#  In case you need it, the log of the cloud-init can be found at: 
#    /var/log/cloud-init-output.log
#
packages:
 - unzip
 - yq
 - curl
 - wget
 - vim
 - amazon-ssm-agent
 - postgresql-client
 - tmux
 - logrotate

write_files:
  - path: /home/root/install-otp-certificates.sh
    owner: root:root
    permissions: "0755"
    content: |
      #!/bin/bash
      #
      #  Script to install certificates
      #
      echo ""
      echo "# Installing Certificates env: ${environment} at /usr/local/share/ca-certificates #"
      echo "Retrieving and saving ......"
      aws secretsmanager get-secret-value --secret-id ${environment}/${app_name}/deployex/otp-tls-ca | jq -r .SecretString > /usr/local/share/ca-certificates/ca.crt
      aws secretsmanager get-secret-value --secret-id ${environment}/${app_name}/deployex/otp-tls-key | jq -r .SecretString > /usr/local/share/ca-certificates/deployex.key
      aws secretsmanager get-secret-value --secret-id ${environment}/${app_name}/deployex/otp-tls-key | jq -r .SecretString > /usr/local/share/ca-certificates/${app_name}.key
      aws secretsmanager get-secret-value --secret-id ${environment}/${app_name}/deployex/otp-tls-crt | jq -r .SecretString > /usr/local/share/ca-certificates/deployex.crt
      aws secretsmanager get-secret-value --secret-id ${environment}/${app_name}/deployex/otp-tls-crt | jq -r .SecretString > /usr/local/share/ca-certificates/${app_name}.crt
      echo "[OK]"
  - path: /home/root/deployex.yaml
    owner: root:root
    permissions: "0644"
    content: |
      account_name: "${environment}"
      hostname: "${deployex_hostname}"
      port: 5001
      release_adapter: "s3"
      release_bucket: "${environment}-${app_name}-distribution"
      secrets_adapter: "aws"
      secrets_path: "${environment}/${app_name}/deployex/secrets"
      aws_region: "${aws_region}"
      version: "${deployex_version}"
      otp_version: 28
      otp_tls_certificates: "/usr/local/share/ca-certificates"
      os_target: "ubuntu-24.04"
      metrics_retention_time_ms: 604800000
      logs_retention_time_ms: 604800000
      monitoring:
        - type: "memory"
          enable_restart: true
          warning_threshold_percent: 75
          restart_threshold_percent: 85
      applications:
        - name: "${app_name}"
          language: "elixir"
          deploy_rollback_timeout_ms: 600000
          deploy_schedule_interval_ms: 5000
          replicas: ${myapp_replicas}
          replica_ports:
%{ for port in myapp_env_ports ~}
            - key: ${port.name}
              base: ${port.value}
%{ endfor ~}
          env:
%{ for env in myapp_env_vars ~}
            - key: ${env.name}
              value: "${env.value}"
%{ endfor ~}
%{ for secret in myapp_secrets ~}
            - key: ${secret.name}
              value: "${secret.value}"
%{ endfor ~}
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
          certificates:
            - type: "domains"
              domains: ["*.${myapp_cert_domain}", "*.other.${myapp_cert_domain}"]
              certificate_check_interval_ms: 86400000
              dns_propagation_timeout_ms: 120000
              dns_check_interval_ms: 5000
              renew_before_days: 30
              dns_provider: "cloudflare"
              dns_options:
                ttl: 10
                zone: "${myapp_cert_acme_zone}"
                api_token: "${myapp_cloudflare_api_token}" # for cloudflare only, not required for route53
              acme_provider: "lets_encrypt"
              acme_options:
                contact_email: "${myapp_cert_email}"
                url: "https://acme-v02.api.letsencrypt.org/directory"
                key_size: 2048
                propagation_timeout_ms: 120000
                check_interval_ms: 2000
              importer: "route53"
              importer_options:
                certificate_arn: "${myapp_cert_arn}"

  - path: /home/root/cloud-watch-config.json
    owner: root:root
    permissions: "0644"
    content: |
      {
        "agent": {
          "run_as_user": "root",
          "metrics_collection_interval": 60
        },
        "logs": {
          "logs_collected": {
            "files": {
              "collect_list": [
                {
                    "file_path": "/var/log/deployex/deployex-stdout.log",
                    "log_group_name": "${log_group_name}",
                    "log_stream_name": "{instance_id}-deployex-stdout-log",
                    "timezone": "UTC",
                    "timestamp_format": "%H: %M: %S%Y%b%-d",
                    "retention_in_days": 30,
                    "encoding": "utf-8"
                },
                {
                    "file_path": "/var/log/deployex/deployex-stderr.log",
                    "log_group_name": "${log_group_name}",
                    "log_stream_name": "{instance_id}-deployex-stderr-log",
                    "timezone": "UTC",
                    "timestamp_format": "%H: %M: %S%Y%b%-d",
                    "retention_in_days": 30,
                    "encoding": "utf-8"
                },
                {
                    "file_path": "/var/log/monitored-apps/myapp/myapp-*-stdout.log",
                    "log_group_name": "${log_group_name}",
                    "log_stream_name": "{instance_id}-myapp-stdout-log",
                    "timezone": "UTC",
                    "timestamp_format": "%H: %M: %S%Y%b%-d",
                    "retention_in_days": 30,
                    "encoding": "utf-8"
                },
                {
                    "file_path": "/var/log/monitored-apps/myapp/myapp-*-stderr.log",
                    "log_group_name": "${log_group_name}",
                    "log_stream_name": "{instance_id}-myapp-stderr-log",
                    "timezone": "UTC",
                    "timestamp_format": "%H: %M: %S%Y%b%-d",
                    "retention_in_days": 30,
                    "encoding": "utf-8"
                }
              ]
            }
          },
          "log_stream_name": "{instance_id}",
          "force_flush_interval": 15
        }
      }
  - path: /etc/logrotate.d/deployex
    owner: root:root
    permissions: "0644"
    content: |
      /var/log/deployex/*.log {
          maxsize 25M
          missingok
          rotate 7
          compress
          delaycompress
          notifempty
          copytruncate
      }

  - path: /etc/logrotate.d/myapp
    owner: root:root
    permissions: "0644"
    content: |
      /var/log/monitored-apps/myapp/*.log {
          maxsize 25M
          missingok
          rotate 7
          compress
          delaycompress
          notifempty
          copytruncate
      }

runcmd:
  # Install OTP certificates from AWS Secrets Manager
  - /home/root/install-otp-certificates.sh
  # Download and install Deployex
  - wget https://github.com/thiagoesteves/deployex/releases/download/${deployex_version}/deployex.sh -P /home/root
  - chmod a+x /home/root/deployex.sh
  - /home/root/deployex.sh --install /home/root/deployex.yaml
  # Install and configure CloudWatch agent
  - wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
  - dpkg -i -E ./amazon-cloudwatch-agent.deb
  - /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/home/root/cloud-watch-config.json -s
  # Set hostname
  - hostnamectl set-hostname ${environment}-${app_name}-debian
  - echo "127.0.0.1 ${environment}-${app_name}-debian" >> /etc/hosts
  # Enable AWS Systems Manager agent
  - systemctl enable amazon-ssm-agent
  # Download RDS certificate bundle
  - curl -o /etc/ssl/certs/rds-global.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
  # Reboot to apply all changes
  - sleep 5
  - reboot
