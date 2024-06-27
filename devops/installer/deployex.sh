#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage:"
    echo "  $0 --install -a <app_name> -r <replicas> -h <hostname> -c <account_name> -d <deployex_hostname> -u <aws_region> -s <os_target>"
    echo "  $0 --update -v <new_version> -s <os_target>"
    echo "  $0 --help"
    echo
    echo "Options:"
    echo "  --install                Install an application"
    echo "  --update                 Update an application"
    echo "  --help                   Print help"
    echo "  -a, --app_name           Name of the application to install (lowercase)"
    echo "  -r, --replicas           Number of replicas to deploy"
    echo "  -h, --hostname           Hostname where the monitored application will run"
    echo "  -c, --account_name       AWS account name to use"
    echo "  -d, --deployex_hostname  Deployment execution hostname"
    echo "  -u, --aws_region         AWS region for deployment"
    echo "  -s, --os_target          Target operating system for installation/update"
    echo "  -v, --new_version        New version of the application for update"
    echo
    echo "Examples:"
    echo "  Install an application:"
    echo "    $0 ./deployex.sh --install -a example -r 3 -h example.com -c prod -d deployex.example.com -u sa-east-1 -v 1.0.0 -s ubuntu-20.04"
    echo
    echo "  Update an application:"
    echo "    $0 --update -v 2.0 -s  ubuntu-20.04"
    echo
    exit 1
}

DEPLOYEX_SERVIVE_NAME=deployex.service
DEPLOYEX_SYSTEMD_PATH=/etc/systemd/system/${DEPLOYEX_SERVIVE_NAME}
DEPLOYEX_OPT_DIR=/opt/deployex
DEPLOYEX_LOG_PATH=/var/log/deployex
DEPLOYEX_VAR_LIB=/var/lib/deployex

remove_deployex() {
    echo "#           Removing Deployex              #"
    systemctl stop ${DEPLOYEX_SERVIVE_NAME}
    systemctl disable ${DEPLOYEX_SERVIVE_NAME}
    rm /etc/systemd/system/${DEPLOYEX_SERVIVE_NAME}
    rm /etc/systemd/system/${DEPLOYEX_SERVIVE_NAME} # and symlinks that might be related
    rm /usr/lib/systemd/system/${DEPLOYEX_SERVIVE_NAME} 
    rm /usr/lib/systemd/system/${DEPLOYEX_SERVIVE_NAME} # and symlinks that might be related
    systemctl daemon-reload
    systemctl reset-failed
    rm -rf ${DEPLOYEX_OPT_DIR}
    rm -rf ${DEPLOYEX_LOG_PATH}
    rm -rf ${DEPLOYEX_VAR_LIB}
    echo "#     Deployex removed with success        #"
}

install_deployex() {
    local app_name="$1"
    local replicas="$2"
    local hostname="$3"
    local account_name="$4"
    local deployex_hostname="$5"
    local aws_region="$6"
    local upper_app_name="${app_name^^}"

DEPLOYEX_SYSTEMD_FILE="
  [Unit]
  Description=Deployex daemon
  After=network.target
  
  [Service]
  Environment=SHELL=/usr/bin/bash
  Environment=AWS_REGION=${aws_region}
  Environment=${upper_app_name}_PHX_HOST=${hostname}
  Environment=${upper_app_name}_PHX_SERVER=true
  Environment=${upper_app_name}_CLOUD_ENVIRONMENT=${account_name}
  Environment=${upper_app_name}_OTP_TLS_CERT_PATH=/usr/local/share/ca-certificates
  Environment=DEPLOYEX_CLOUD_ENVIRONMENT=${account_name}
  Environment=DEPLOYEX_OTP_TLS_CERT_PATH=/usr/local/share/ca-certificates
  Environment=DEPLOYEX_MONITORED_APP_NAME=${app_name}
  Environment=DEPLOYEX_PHX_HOST=${deployex_hostname}
  Environment=DEPLOYEX_MONITORED_REPLICAS=${replicas}
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
    systemctl stop ${DEPLOYEX_SERVIVE_NAME}
    echo "# Clean and create a new directory         #"
    rm -rf ${DEPLOYEX_OPT_DIR} && mkdir ${DEPLOYEX_OPT_DIR} && cd ${DEPLOYEX_OPT_DIR}
    tar xf /tmp/deployex-${OS_TARGET}.tar.gz
    echo "# Start systemd                            #"
    echo "# Start new service                        #"
    systemctl daemon-reload
    systemctl enable --now ${DEPLOYEX_SERVIVE_NAME}
}

# Parse command-line options
while getopts ":a:r:h:c:d:u:v:s:-:" opt; do
    case $opt in
        a)
            app_name="$OPTARG"
            ;;
        r)
            replicas="$OPTARG"
            ;;
        h)
            hostname="$OPTARG"
            ;;
        c)
            account_name="$OPTARG"
            ;;
        d)
            deployex_hostname="$OPTARG"
            ;;
        u)
            aws_region="$OPTARG"
            ;;
        v)
            version="$OPTARG"
            ;;
        s)
            os_target="$OPTARG"
            ;;
        -)
            case "${OPTARG}" in
                install)
                    operation="install"
                    ;;
                update)
                    operation="update"
                    ;;
                help)
                    usage
                    ;;
                *)
                    echo "Invalid option: --${OPTARG}"
                    usage
                    ;;
            esac
            ;;
        *)
            usage
            ;;
    esac
done

# Check if all required parameters are provided based on the operation
if [ "$operation" == "install" ]; then
    if [[ -z "$app_name" || -z "$replicas" || -z "$hostname" || -z "$account_name" || -z "$deployex_hostname" || -z "$aws_region" || -z "$os_target" || -z "$version" ]]; then
        usage
    fi
    remove_deployex
    install_deployex "$app_name" "$replicas" "$hostname" "$account_name" "$deployex_hostname" "$aws_region"
    update_deployex "$version" "$os_target"
elif [ "$operation" == "update" ]; then
    if [[ -z "$version" || -z "$os_target" ]]; then
        usage
    fi
    update_deployex "$version" "$os_target"
else
    usage
fi
