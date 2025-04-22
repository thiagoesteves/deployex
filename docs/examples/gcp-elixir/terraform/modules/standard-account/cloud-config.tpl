#cloud-config
#
#  Cloud init template for Google Compute Instance.
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
      gcloud secrets versions access 1 --secret=myappname-${account_name}-otp-tls-ca > /usr/local/share/ca-certificates/ca.crt
      gcloud secrets versions access 1 --secret=myappname-${account_name}-otp-tls-key > /usr/local/share/ca-certificates/deployex.key
      gcloud secrets versions access 1 --secret=myappname-${account_name}-otp-tls-key > /usr/local/share/ca-certificates/myappname.key
      gcloud secrets versions access 1 --secret=myappname-${account_name}-otp-tls-crt > /usr/local/share/ca-certificates/deployex.crt
      gcloud secrets versions access 1 --secret=myappname-${account_name}-otp-tls-crt > /usr/local/share/ca-certificates/myappname.crt
      echo "[OK]"
  - path: /home/ubuntu/gcp-config.json
    owner: root:root
    permissions: "0644"
    content: |
      {
        "type": "service_account" # Populate it after installation
        ...
      }
  - path: /home/ubuntu/deployex.yaml
    owner: root:root
    permissions: "0644"
    content: |
      account_name: "${account_name}"
      hostname: "${deployex_hostname}"
      port: 5001
      release_adapter: "gcp-storage"
      release_bucket: "myappname-${account_name}-distribution"
      secrets_adapter: "gcp"
      secrets_path: "deployex-myappname-${account_name}-secrets"
      google_credentials: "/home/ubuntu/gcp-config.json"
      version: "${deployex_version}"
      otp_version: 27
      otp_tls_certificates: "/usr/local/share/ca-certificates"
      os_target: "ubuntu-24.04"
      deploy_timeout_rollback_ms: 600000
      deploy_schedule_interval_ms: 5000
      metrics_retention_time_ms: 3600000
      logs_retention_time_ms: 3600000
      applications:
        - name: "myappname"
          language: "elixir"
          initial_port: 4000
          replicas: "${replicas}"
          env:
            - key: MYAPPNAME_PHX_HOST
              value: "${hostname}"
            - key: MYAPPNAME_PHX_SERVER
              value: true
            - key: MYAPPNAME_CLOUD_ENVIRONMENT
              value: "${account_name}"
            - key: MYAPPNAME_OTP_TLS_CERT_PATH
              value: "/usr/local/share/ca-certificates"
  - path: /etc/nginx/sites-available/default
    owner: root:root
    permissions: "0644"
    content: |
      upstream phoenix {
          server 127.0.0.1:4000 max_fails=5 fail_timeout=60s;
          server 127.0.0.1:4001 max_fails=5 fail_timeout=60s;
          server 127.0.0.1:4002 max_fails=5 fail_timeout=60s;
      }

      upstream deployex {
          server 127.0.0.1:5001 max_fails=5 fail_timeout=60s;
      }

      server {
          listen 80;
          server_name ${hostname} ${deployex_hostname};

          if ($host = ${hostname}) {
              return 301 https://$host$request_uri;
          } # managed by Certbot


          if ($host = ${deployex_hostname}) {
              return 301 https://$host$request_uri;
          } # managed by Certbot

          return 404; # managed by Certbot
      }

      server { 
          #listen 443 ssl; # managed by Certbot
          server_name  ${deployex_hostname};
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
          server_name  ${hostname};
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

              proxy_pass http://phoenix;
          }
          # Add here the letsencrypt paths
      }
runcmd:
  - /home/ubuntu/install-otp-certificates.sh
  - wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
  - chmod a+x /usr/local/bin/yq
  - wget https://github.com/thiagoesteves/deployex/releases/download/${deployex_version}/deployex.sh -P /home/ubuntu
  - chmod a+x /home/ubuntu/deployex.sh
  - /home/ubuntu/deployex.sh --install /home/ubuntu/deployex.yaml
  - systemctl enable --no-block nginx 
  - systemctl start --no-block nginx
  - reboot