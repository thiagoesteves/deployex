#cloud-config
#
#  Cloud init template for EC2 myappname instances.
#
#  In case you need it, the log of the cloud-init can be found at: 
#    /var/log/cloud-init-output.log
#
packages:
 - unzip
 - nginx

write_files:
  - path: /home/ubuntu/install-otp-certificates.sh
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
  - path: /home/ubuntu/deployex.yaml
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
        - name: "myappname"
          language: "gleam"
          replicas: ${replicas}
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
  - path: /home/ubuntu/config.json
    owner: root:root
    permissions: "0644"
    content: |
      {
        "agent": {
          "run_as_user": "root"
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
                    "timestamp_format": "%H: %M: %S%Y%b%-d"
                },
                {
                    "file_path": "/var/log/deployex/deployex-stderr.log",
                    "log_group_name": "${log_group_name}",
                    "log_stream_name": "{instance_id}-deployex-stderr-log",
                    "timezone": "UTC",
                    "timestamp_format": "%H: %M: %S%Y%b%-d"
                },
                {
                    "file_path": "/var/log/myappname/myappname-*-stdout.log",
                    "log_group_name": "${log_group_name}",
                    "log_stream_name": "{instance_id}-myappname-stdout-log",
                    "timezone": "UTC",
                    "timestamp_format": "%H: %M: %S%Y%b%-d"
                },
                {
                    "file_path": "/var/log/myappname/myappname-*-stderr.log",
                    "log_group_name": "${log_group_name}",
                    "log_stream_name": "{instance_id}-myappname-stderr-log",
                    "timezone": "UTC",
                    "timestamp_format": "%H: %M: %S%Y%b%-d"
                }
              ]
            }
          }
        }
      }
  - path: /etc/nginx/sites-available/default
    owner: root:root
    permissions: "0644"
    content: |
      upstream gleam {
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
          listen 80;
          server_name myappname.com.br deployex.myappname.com.br;

          if ($host = myappname.com.br) {
              return 301 https://$host$request_uri;
          } # managed by Certbot


          if ($host = deployex.myappname.com.br) {
              return 301 https://$host$request_uri;
          } # managed by Certbot

          return 404; # managed by Certbot
      }

      server { 
          #listen 443 ssl; # managed by Certbot
          server_name  deployex.myappname.com.br;
          client_max_body_size 30M;

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
          
          # Add here the letsencrypt paths
      }

      server {
          #listen 443 ssl; # managed by Certbot
          server_name  myappname.com.br;
          client_max_body_size 30M;

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

              proxy_pass http://gleam;
          }
          # Add here the letsencrypt paths
      }
runcmd:
  - cd /tmp
  - curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" "-o"  "awscliv2.zip"
  - unzip "awscliv2.zip"
  - ./aws/install
  - ./aws/install --update
  - /home/ubuntu/install-otp-certificates.sh
  - wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
  - chmod a+x /usr/local/bin/yq
  - wget https://github.com/thiagoesteves/deployex/releases/download/${deployex_version}/deployex.sh -P /home/ubuntu
  - chmod a+x /home/ubuntu/deployex.sh
  - /home/ubuntu/deployex.sh --install /home/ubuntu/deployex.yaml
  - wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
  - dpkg -i -E ./amazon-cloudwatch-agent.deb
  - /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/home/ubuntu/config.json -s
  - apt install -y build-essential libssl-dev libgtk-3-dev libncurses5-dev libncursesw5-dev libreadline-dev
  - wget https://github.com/erlang/otp/releases/download/OTP-26.1.2/otp_src_26.1.2.tar.gz
  - tar -xzf otp_src_26.1.2.tar.gz && cd otp_src_26.1.2 && ./configure && make && make install
  - systemctl enable --no-block nginx 
  - systemctl start --no-block nginx
  - reboot