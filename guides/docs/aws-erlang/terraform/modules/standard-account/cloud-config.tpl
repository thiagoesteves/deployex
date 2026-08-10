#cloud-config
#
#  Cloud init template for EC2 myappname instances.
#
#  In case you need it, the log of the cloud-init can be found at: 
#    /var/log/cloud-init-output.log
#
packages:
 - certbot
 - unzip
 - nginx
 - logrotate
 - awscli
 - jq
 - amazon-ssm-agent

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
      echo "# Installing Certificates env: ${account_name} at /usr/local/share/ca-certificates #"
      echo "Retrieving and saving ......"
      aws secretsmanager get-secret-value --secret-id myappname-${account_name}-otp-tls-ca | jq -r .SecretString > /usr/local/share/ca-certificates/ca.crt
      aws secretsmanager get-secret-value --secret-id myappname-${account_name}-otp-tls-key | jq -r .SecretString > /usr/local/share/ca-certificates/deployex.key
      aws secretsmanager get-secret-value --secret-id myappname-${account_name}-otp-tls-key | jq -r .SecretString > /usr/local/share/ca-certificates/myappname.key
      aws secretsmanager get-secret-value --secret-id myappname-${account_name}-otp-tls-crt | jq -r .SecretString > /usr/local/share/ca-certificates/deployex.crt
      aws secretsmanager get-secret-value --secret-id myappname-${account_name}-otp-tls-crt | jq -r .SecretString > /usr/local/share/ca-certificates/myappname.crt
      echo "[OK]"
  - path: /home/root/deployex.yaml
    owner: root:root
    permissions: "0644"
    content: |
      account_name: "${account_name}"
      hostname: "${deployex_hostname}"
      port: 5001
      release_adapter: "s3"
      release_bucket: "myappname-${account_name}-distribution"
      secrets_adapter: "aws"
      secrets_path: "deployex-myappname-${account_name}-secrets"
      aws_region: "${aws_region}"
      version: "${deployex_version}"
      otp_version: 28
      otp_tls_certificates: "/usr/local/share/ca-certificates"
      os_target: "ubuntu-24.04"
      metrics_retention_time_ms: 3600000
      logs_retention_time_ms: 3600000
      monitoring:
        - type: "memory"
          enable_restart: true
          warning_threshold_percent: 75
          restart_threshold_percent: 85
      applications:
        - name: "myappname"
          language: "erlang"
          replicas: ${replicas}
          deploy_rollback_timeout_ms: 600000
          deploy_schedule_interval_ms: 5000
          replica_ports:
            - key: PORT
              base: 4000
          env:
            - key: MYAPPNAME_PHX_HOST
              value: "${hostname}"
            - key: MYAPPNAME_PHX_SERVER
              value: true
            - key: MYAPPNAME_CLOUD_ENVIRONMENT
              value: "${account_name}"
            - key: MYAPPNAME_OTP_TLS_CERT_PATH
              value: "/usr/local/share/ca-certificates"
            - key: AWS_REGION
              value: "${aws_region}"
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
                    "retention_in_days": 7,
                    "encoding": "utf-8"
                },
                {
                    "file_path": "/var/log/deployex/deployex-stderr.log",
                    "log_group_name": "${log_group_name}",
                    "log_stream_name": "{instance_id}-deployex-stderr-log",
                    "timezone": "UTC",
                    "timestamp_format": "%H: %M: %S%Y%b%-d",
                    "retention_in_days": 7,
                    "encoding": "utf-8"
                },
                {
                    "file_path": "/var/log/monitored-apps/myappname/myappname-*-stdout.log",
                    "log_group_name": "${log_group_name}",
                    "log_stream_name": "{instance_id}-myappname-stdout-log",
                    "timezone": "UTC",
                    "timestamp_format": "%H: %M: %S%Y%b%-d",
                    "retention_in_days": 7,
                    "encoding": "utf-8"
                },
                {
                    "file_path": "/var/log/monitored-apps/myappname/myappname-*-stderr.log",
                    "log_group_name": "${log_group_name}",
                    "log_stream_name": "{instance_id}-myappname-stderr-log",
                    "timezone": "UTC",
                    "timestamp_format": "%H: %M: %S%Y%b%-d",
                    "retention_in_days": 7,
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
          maxsize 20M
          missingok
          rotate 7
          compress
          delaycompress
          notifempty
          copytruncate
      }

  - path: /etc/logrotate.d/myappname
    owner: root:root
    permissions: "0644"
    content: |
      /var/log/monitored-apps/myappname/*.log {
          maxsize 20M
          missingok
          rotate 7
          compress
          delaycompress
          notifempty
          copytruncate
      }
  - path: /etc/nginx/sites-available/default
    owner: root:root
    permissions: "0644"
    content: |
      upstream erlang {
          # Attention: Keep (replicas + 1) upstream
          server 127.0.0.1:4000 max_fails=5 fail_timeout=60s;
          server 127.0.0.1:4001 max_fails=5 fail_timeout=60s;
          server 127.0.0.1:4002 max_fails=5 fail_timeout=60s;
          server 127.0.0.1:4003 max_fails=5 fail_timeout=60s;
      }

      upstream deployex {
          server 127.0.0.1:5001 max_fails=5 fail_timeout=60s;
      }

      server {
          listen 80 default_server;
          server_name _;
          return 404;
      }

      server {
          listen 80;
          server_name ${hostname} ${deployex_hostname};

          # HTTP-01 challenge, for the first issue and for every renewal. certbot only ever
          # writes files under this root, it does not touch the nginx configuration
          location /.well-known/acme-challenge/ {
              root /var/www/certbot;
          }

          location / {
              return 301 https://$host$request_uri;
          }
      }

  - path: /home/root/nginx-tls.conf
    owner: root:root
    permissions: "0644"
    content: |
      # Installed into /etc/nginx/conf.d/ by setup-tls.sh once the certificate exists. One
      # certificate covers both names, under a lineage named after ${hostname}.
      #
      # The TLS parameters are written out instead of including
      # /etc/letsencrypt/options-ssl-nginx.conf. That file is created by the certbot nginx
      # installer plugin, which does not run here because the certificate is obtained with
      # certonly --webroot, so it does not exist on the box. These are the same values.
      #
      # They sit inside the server blocks rather than at http level, because the stock
      # nginx.conf already sets ssl_protocols and ssl_prefer_server_ciphers there and nginx
      # rejects the duplicates.
      server {
          listen 443 ssl;
          server_name  ${deployex_hostname};
          client_max_body_size 30M;

          ssl_certificate     /etc/letsencrypt/live/${hostname}/fullchain.pem;
          ssl_certificate_key /etc/letsencrypt/live/${hostname}/privkey.pem;

          ssl_session_cache shared:deployex_SSL:10m;
          ssl_session_timeout 1440m;
          ssl_session_tickets off;
          ssl_protocols TLSv1.2 TLSv1.3;
          ssl_prefer_server_ciphers off;
          ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305";

          location / {
              allow all;

              # Proxy Headers
              proxy_http_version 1.1;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header Host $http_host;
              proxy_set_header X-Cluster-Client-Ip $remote_addr;

              # The Important Websocket Bits!
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";

              proxy_pass http://deployex;
          }
      }

      server {
          listen 443 ssl;
          server_name  ${hostname};
          client_max_body_size 30M;

          ssl_certificate     /etc/letsencrypt/live/${hostname}/fullchain.pem;
          ssl_certificate_key /etc/letsencrypt/live/${hostname}/privkey.pem;

          ssl_session_cache shared:deployex_SSL:10m;
          ssl_session_timeout 1440m;
          ssl_session_tickets off;
          ssl_protocols TLSv1.2 TLSv1.3;
          ssl_prefer_server_ciphers off;
          ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305";

          location / {
              allow all;

              # Proxy Headers
              proxy_http_version 1.1;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header Host $http_host;
              proxy_set_header X-Cluster-Client-Ip $remote_addr;

              # The Important Websocket Bits!
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";

              proxy_pass http://erlang;
          }
      }

  - path: /home/root/setup-tls.sh
    owner: root:root
    permissions: "0755"
    content: |
      #!/bin/bash
      #
      #  Obtain the TLS certificate and enable the HTTPS server blocks.
      #
      #  Runs on every boot and is idempotent: --keep-until-expiring leaves a still valid
      #  certificate alone, which matters because any cloud-config change replaces the
      #  instance and Let's Encrypt only allows 5 identical certificates per week.
      #
      set -uo pipefail

      mkdir -p /var/www/certbot

      if certbot certonly \
           --webroot --webroot-path /var/www/certbot \
           --cert-name ${hostname} \
           -d ${hostname} -d ${deployex_hostname} \
           --email ${certbot_email} \
           --agree-tos --non-interactive --keep-until-expiring \
           --deploy-hook "systemctl reload nginx"; then
        install -o root -g root -m 0644 /home/root/nginx-tls.conf /etc/nginx/conf.d/tls.conf

        if nginx -t; then
          systemctl reload nginx
        else
          # Never leave nginx unable to start, HTTP is better than nothing
          rm -f /etc/nginx/conf.d/tls.conf
          echo "setup-tls: generated TLS config failed nginx -t, staying on HTTP" >&2
          exit 1
        fi
      else
        echo "setup-tls: certbot failed, staying on HTTP. Check that ${hostname} and" >&2
        echo "           ${deployex_hostname} resolve to this instance, then re-run." >&2
        exit 1
      fi
runcmd:
  # Set the hostname so the environment is obvious on the box and in logs
  - hostnamectl set-hostname myappname-${account_name}-debian
  - echo "127.0.0.1 myappname-${account_name}-debian" >> /etc/hosts
  # Enable AWS Systems Manager agent
  - systemctl enable amazon-ssm-agent
  # RDS server certificate chain, used by the Ecto repo to verify the database
  - curl -o /etc/ssl/certs/rds-global.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
  # Download and install Deployex. deployex.sh reads its yaml with yq, which Debian does
  # not ship by default
  - wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
  - chmod a+x /usr/local/bin/yq
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
  # Enable Nginx
  - systemctl enable nginx
  - systemctl restart nginx
  # nginx is serving HTTP at this point, which is all the HTTP-01 challenge needs
  - /home/root/setup-tls.sh
  # Reboot to apply all changes
  - sleep 5
  - reboot
