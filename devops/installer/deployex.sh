#!/bin/bash

# Default values
DEFAULT_CONFIG_FILE="deployex.yaml"
DEFAULT_DIST_URL="https://github.com/thiagoesteves/deployex/releases/download"
DEFAULT_DEPLOYEX_OPT_DIR="/opt/deployex"
DEFAULT_DEPLOYEX_VAR_LIB="/var/lib/deployex"

# Function to display usage information
usage() {
    echo "Usage:"
    echo "  $0 --install [config_file] [--dist <base_url>]"
    echo "  $0 --update [config_file] [--dist <base_url>]"
    echo "  $0 --help"
    echo
    echo "Options:"
    echo "  --install [config_file]   Install an application using a config file"
    echo "                            (default: ${DEFAULT_CONFIG_FILE})"
    echo "  --update [config_file]    Update ONLY the deployex application using a config file"
    echo "                            (default: ${DEFAULT_CONFIG_FILE})"
    echo "  --dist <base_url>         Base URL for downloading releases"
    echo "                            (default: ${DEFAULT_DIST_URL})"
    echo "  --help                    Print help"
    echo
    echo "Examples:"
    echo "  Install an application with default config name (deployex.yaml):"
    echo "    $0 --install"
    echo
    echo "  Install an application with custom config:"
    echo "    $0 --install /home/root/deployex.yaml"
    echo
    echo "  Update an application with defaults"
    echo "    $0 --update"
    echo
    echo "  Update an application with custom distribution URL:"
    echo "    $0 --update --dist https://deployex-testing-storage.s3.sa-east-1.amazonaws.com"
    echo
    echo "  Update with custom config and distribution:"
    echo "    $0 --update my-config.yaml --dist https://example.com/releases"
    echo
    exit 1
}

DEPLOYEX_SERVICE_NAME=deployex.service
DEPLOYEX_SYSTEMD_PATH=/etc/systemd/system/${DEPLOYEX_SERVICE_NAME}
DEPLOYEX_LOG_PATH=/var/log/deployex
DEPLOYEX_MONITORED_APP_LOG_PATH=/var/log/monitored-apps

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
    rm -rf ${DEPLOYEX_OPT_DIR}
    rm -rf ${DEPLOYEX_LOG_PATH}
    rm -rf ${DEPLOYEX_VAR_LIB}
    rm -rf ${DEPLOYEX_MONITORED_APP_LOG_PATH}
    echo "#     Deployex removed with success        #"
}

install_deployex() {
    local yaml_file=$(realpath "${1}")
    local otp_tls_certificates="${2}"

DEPLOYEX_SYSTEMD_FILE="
  [Unit]
  Description=Deployex daemon
  After=network.target
  
  [Service]
  Environment=SHELL=/usr/bin/bash
  Environment=LANG=C.UTF-8
  Environment=LC_CTYPE=C.UTF-8
  Environment=LS_COLORS=rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arc=01;31:*.arj=01;31:*.taz=01;31:*.lha=01;31:*.lz4=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.tzo=01;31:*.t7z=01;31:*.zip=01;31:*.z=01;31:*.dz=01;31:*.gz=01;31:*.lrz=01;31:*.lz=01;31:*.lzo=01;31:*.xz=01;31:*.zst=01;31:*.tzst=01;31:*.bz2=01;31:*.bz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.war=01;31:*.ear=01;31:*.sar=01;31:*.rar=01;31:*.alz=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:*.cab=01;31:*.wim=01;31:*.swm=01;31:*.dwm=01;31:*.esd=01;31:*.jpg=01;35:*.jpeg=01;35:*.mjpg=01;35:*.mjpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.webm=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.ogv=01;35:*.ogx=01;35:*.aac=00;36:*.au=00;36:*.flac=00;36:*.m4a=00;36:*.mid=00;36:*.midi=00;36:*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:*.oga=00;36:*.opus=00;36:*.spx=00;36:*.xspf=00;36:
  Environment=TERM=xterm-256color
  Environment=DEPLOYEX_CONFIG_YAML_PATH=${yaml_file}
  Environment=DEPLOYEX_OTP_TLS_CERT_PATH=${otp_tls_certificates}
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

    # Create log directories for all applications
    echo "# Creating log directories for applications #"
    echo "  - Application logs at: $DEPLOYEX_MONITORED_APP_LOG_PATH"
    mkdir -p ${DEPLOYEX_MONITORED_APP_LOG_PATH}/
    chown deployex:deployex ${DEPLOYEX_MONITORED_APP_LOG_PATH}/

    printf "%s\n" "${DEPLOYEX_SYSTEMD_FILE}" > ${DEPLOYEX_SYSTEMD_PATH}
    echo "#    Deployex installed with success       #"
}

update_deployex() {
  local OS_TARGET=$1
  local OTP_VERSION=$2
  local BASE_RELEASE=$3
  local FILENAME="deployex-${OS_TARGET}-otp-${OTP_VERSION}.tar.gz"
  local CHECKSUM_FILE="checksum.txt"

    echo ""
    echo "#           Updating Deployex              #"
    cd /tmp
    echo "# Download the deployex from Distribution URL: ${BASE_RELEASE}"
    rm -f deployex-ubuntu-*.tar.gz
    rm -f ${CHECKSUM_FILE}
    echo "#           Downloading files              #"
    wget ${BASE_RELEASE}/${CHECKSUM_FILE}
    wget ${BASE_RELEASE}/${FILENAME}

    if [ $? != 0 ]; then
            echo "Error while trying to download from: ${BASE_RELEASE}"
            exit
    fi
    
    echo "# Verify checksum                          #"
    # Extract the expected checksum for this specific file
    EXPECTED_CHECKSUM=$(cat ${CHECKSUM_FILE} | grep "${FILENAME}"  | awk '{print $1}')
  
    if [ -z "$EXPECTED_CHECKSUM" ]; then
      echo "Error: No checksum found for ${FILENAME}"
      exit 1
    fi
  
    # Calculate actual checksum
    ACTUAL_CHECKSUM=$(sha256sum "${FILENAME}" | awk '{print $1}')
    
    if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
      echo "Error: Checksum verification failed!"
      echo "Expected: $EXPECTED_CHECKSUM"
      echo "Got:      $ACTUAL_CHECKSUM"
      exit 1
    fi
  
    echo "# Checksum verified successfully           #"
    echo "# Stop current service                     #"
    systemctl stop ${DEPLOYEX_SERVICE_NAME}
    echo "# Clean and create a new directory         #"
    rm -rf ${DEPLOYEX_OPT_DIR}
    mkdir ${DEPLOYEX_OPT_DIR}
    cd ${DEPLOYEX_OPT_DIR}
    tar xf /tmp/deployex-${OS_TARGET}-otp-${OTP_VERSION}.tar.gz
    echo "# Start systemd                            #"
    echo "# Start new service                        #"
    systemctl daemon-reload
    systemctl enable --now ${DEPLOYEX_SERVICE_NAME}
}

# Initialize variables
operation=""
config_file=""
dist_url=${DEFAULT_DIST_URL}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --install)
            operation=install
            shift
            # Check if next argument exists and is not another flag
            if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
                config_file="$1"
                shift
            else
                config_file=${DEFAULT_CONFIG_FILE}
            fi
            ;;
        --update)
            operation=update
            shift
            # Check if next argument exists and is not another flag
            if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
                config_file="$1"
                shift
            else
                config_file=${DEFAULT_CONFIG_FILE}
            fi
            ;;
        --dist)
            if [[ -z "$2" || "$2" =~ ^-- ]]; then
                echo "Error: --dist requires a URL argument"
                usage
            fi
            dist_url="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "Invalid option: $1"
            usage
            ;;
    esac
done

# Ensure operation is set
if [[ -z $operation ]]; then
    usage
fi

# Use default config file if not provided
if [[ -z $config_file ]]; then
    config_file=${DEFAULT_CONFIG_FILE}
fi

# Validate config file existence
if [ ! -f $config_file ]; then
    echo "Config file '$config_file' not found."
    exit 1
fi

version=$(yq '.version' $config_file | tr -d '"')
otp_version=$(yq '.otp_version' $config_file | tr -d '"')
otp_tls_certificates=$(yq '.otp_tls_certificates' $config_file | tr -d '"')
os_target=$(yq '.os_target' $config_file | tr -d '"')
install_path=$(yq '.install_path' $config_file | tr -d '"')
var_path=$(yq '.var_path' $config_file | tr -d '"')

# Use defaults if not defined or null
if [[ -z $install_path || $install_path == "null" ]]; then
    DEPLOYEX_OPT_DIR=${DEFAULT_DEPLOYEX_OPT_DIR}
else
    DEPLOYEX_OPT_DIR=${install_path}
fi

if [[ -z $var_path || $var_path == "null" ]]; then
    DEPLOYEX_VAR_LIB=${DEFAULT_DEPLOYEX_VAR_LIB}
else
    DEPLOYEX_VAR_LIB=${var_path}
fi

if [ $dist_url != $DEFAULT_DIST_URL ]; then
    base_release=${dist_url}
else
    base_release=${dist_url}/${version}
fi

# Check if all required parameters are provided based on the operation
if [ $operation == install ]; then
    if [[ -z $version || 
          -z $otp_version ||
          -z $otp_tls_certificates ||
          -z $os_target ]]; then
        echo "Error: Missing required parameters in config file"
        usage
    fi
    remove_deployex
    install_deployex $config_file $otp_tls_certificates
    update_deployex $os_target $otp_version $base_release
elif [ $operation == update ]; then
    if [[ -z $version || -z $os_target || -z $otp_version ]]; then
        echo "Error: Missing required parameters in config file"
        usage
    fi
    update_deployex $os_target $otp_version $base_release
else
    usage
fi