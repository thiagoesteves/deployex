#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage:"
    echo "  $0 --install <config_file>"
    echo "  $0 --update <config_file>"
    echo "  $0 --help"
    echo
    echo "Options:"
    echo "  --install <config_file>   Install an application using a JSON config file"
    echo "  --update <config_file>    Update ONLY the deployex application using a JSON config file"
    echo "  --help                    Print help"
    echo
    echo "Examples:"
    echo "  Install an application:"
    echo "    $0 --install deployex-config.json"
    echo
    echo "  Update an application:"
    echo "    $0 --update deployex-config.json"
    echo
    exit 1
}

DEPLOYEX_SERVICE_NAME=deployex.service
DEPLOYEX_SYSTEMD_PATH=/etc/systemd/system/${DEPLOYEX_SERVICE_NAME}
DEPLOYEX_OPT_DIR=/opt/deployex
DEPLOYEX_STORAGE_DIR=/opt/deployex/storage
DEPLOYEX_SERVICE_DIR=/opt/deployex/service
DEPLOYEX_LOG_PATH=/var/log/deployex
DEPLOYEX_VAR_LIB=/var/lib/deployex

remove_deployex() {
    echo "#           Removing Deployex              #"
    systemctl stop ${DEPLOYEX_SERVICE_NAME}
    systemctl disable ${DEPLOYEX_SERVICE_NAME}
    rm /etc/systemd/system/${DEPLOYEX_SERVICE_NAME}
    rm /etc/systemd/system/${DEPLOYEX_SERVICE_NAME} # and symlinks that might be related
    rm /usr/lib/systemd/system/${DEPLOYEX_SERVICE_NAME}
    rm /usr/lib/systemd/system/${DEPLOYEX_SERVICE_NAME} # and symlinks that might be related
    systemctl daemon-reload
    systemctl reset-failed
    rm -rf ${DEPLOYEX_SERVICE_DIR}
    rm -rf ${DEPLOYEX_LOG_PATH}
    rm -rf ${DEPLOYEX_VAR_LIB}
    echo "#     Deployex removed with success        #"
}

install_deployex() {
    local app_name="$1"
    local replicas="$2"
    local account_name="$3"
    local deployex_hostname="$4"
    local aws_region="$5"
    local deploy_timeout_rollback_ms="$6"
    local deploy_schedule_interval_ms="$7"

    # Load environment variables from JSON
    local env_variables=$(jq -r '.env | to_entries[] | "\(.key)=\(.value)"' "$config_file")
    eval "$env_variables"

    if [ -n "$env_variables" ]; then
      DEPLOYEX_SYSTEMD_ENV_VARS="$(jq -r '.env | to_entries[] | "  Environment=\(.key)=\(.value)"' "$config_file")"
    fi

DEPLOYEX_SYSTEMD_FILE="
  [Unit]
  Description=Deployex daemon
  After=network.target
  
  [Service]
  Environment=SHELL=/usr/bin/bash
  Environment=AWS_REGION=${aws_region}
"$DEPLOYEX_SYSTEMD_ENV_VARS"
  Environment=DEPLOYEX_CLOUD_ENVIRONMENT=${account_name}
  Environment=DEPLOYEX_OTP_TLS_CERT_PATH=/usr/local/share/ca-certificates
  Environment=DEPLOYEX_MONITORED_APP_NAME=${app_name}
  Environment=DEPLOYEX_PHX_HOST=${deployex_hostname}
  Environment=DEPLOYEX_MONITORED_REPLICAS=${replicas}
  Environment=DEPLOYEX_DEPLOY_TIMEOUT_ROLLBACK_MS=${deploy_timeout_rollback_ms}
  Environment=DEPLOYEX_DEPLOY_SCHEDULE_INTERVAL_MS=${deploy_schedule_interval_ms}
  ExecStart=${DEPLOYEX_OPT_DIR}/bin/deployex start
  StandardOutput=append:${DEPLOYEX_LOG_PATH}/deployex-stdout.log
  StandardError=append:${DEPLOYEX_LOG_PATH}/deployex-stderr.log
  KillMode=process
  Restart=on-failure
  RestartSec=3
  LimitNPROC=infinity
  LimitCORE=infinity
  LimitNOFILE=infinity
  RuntimeDirectory=deployex
  User=deployex
  Group=deployex
  
  [Install]
  WantedBy=multi-user.target
"
    echo "#          Installing Deployex             #"
    mkdir ${DEPLOYEX_OPT_DIR}
    useradd  -c "Deployer User" -d  /var/deployex -s  /usr/sbin/nologin --user-group --no-create-home deployex
    mkdir ${DEPLOYEX_VAR_LIB}
    chown deployex:deployex ${DEPLOYEX_VAR_LIB}
    mkdir ${DEPLOYEX_LOG_PATH}/
    chown deployex:deployex ${DEPLOYEX_LOG_PATH}/
    touch ${DEPLOYEX_LOG_PATH}/deployex-stdout.log
    touch ${DEPLOYEX_LOG_PATH}/deployex-stderr.log

    mkdir /var/log/${app_name}/
    chown deployex:deployex /var/log/${app_name}/

    printf "%s\n" "${DEPLOYEX_SYSTEMD_FILE}" > ${DEPLOYEX_SYSTEMD_PATH}
    echo "#    Deployex installed with success       #"
}

update_deployex() {
  local VERSION="$1"
  local OS_TARGET="$2"
    echo ""
    echo "#           Updating Deployex              #"
    cd /tmp
    echo "# Download the deployex version: ${VERSION} #"
    rm -f deployex-ubuntu-*.tar.gz
    wget https://github.com/thiagoesteves/deployex/releases/download/${VERSION}/deployex-${OS_TARGET}.tar.gz
    if [ $? != 0 ]; then
            echo "Error while trying to download the version: ${VERSION}"
            exit
    fi
    echo "# Stop current service                     #"
    systemctl stop ${DEPLOYEX_SERVICE_NAME}
    echo "# Clean and create a new directory         #"
    rm -rf ${DEPLOYEX_SERVICE_DIR}
    mkdir ${DEPLOYEX_OPT_DIR}
    cd ${DEPLOYEX_OPT_DIR}
    tar xf /tmp/deployex-${OS_TARGET}.tar.gz
    echo "# Start systemd                            #"
    echo "# Start new service                        #"
    systemctl daemon-reload
    systemctl enable --now ${DEPLOYEX_SERVICE_NAME}
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --install)
            operation="install"
            config_file="$2"
            shift
            ;;
        --update)
            operation="update"
            config_file="$2"
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Invalid option: $1"
            usage
            ;;
    esac
    shift
done

# Ensure operation is set and config_file is provided
if [[ -z "$operation" || -z "$config_file" ]]; then
    usage
fi

# Validate config file existence
if [ ! -f "$config_file" ]; then
    echo "Config file '$config_file' not found."
    exit 1
fi

# Load variables from JSON config file
if ! variables=$(jq -e '. | {app_name, replicas, account_name, deployex_hostname, aws_region, version, os_target, deploy_timeout_rollback_ms, deploy_schedule_interval_ms}' "$config_file"); then
    echo "Failed to parse JSON config file."
    exit 1
fi

# Assign variables
eval "$(echo "$variables" | jq -r '@sh "app_name=\(.app_name) replicas=\(.replicas) account_name=\(.account_name) deployex_hostname=\(.deployex_hostname) aws_region=\(.aws_region) version=\(.version) os_target=\(.os_target) deploy_timeout_rollback_ms=\(.deploy_timeout_rollback_ms) deploy_schedule_interval_ms=\(.deploy_schedule_interval_ms)"')"

# Check if all required parameters are provided based on the operation
if [ "$operation" == "install" ]; then
    if [[ -z "$app_name" || -z "$replicas" || -z "$account_name" || -z "$deployex_hostname" || -z "$aws_region" || -z "$deploy_timeout_rollback_ms" || -z "$deploy_schedule_interval_ms" ]]; then
        usage
    fi
    remove_deployex
    install_deployex "$app_name" "$replicas" "$account_name" "$deployex_hostname" "$aws_region" "$deploy_timeout_rollback_ms" "$deploy_schedule_interval_ms"
    update_deployex "$version" "$os_target"
elif [ "$operation" == "update" ]; then
    if [[ -z "$version" || -z "$os_target" ]]; then
        usage
    fi
    update_deployex "$version" "$os_target"
else
    usage
fi
