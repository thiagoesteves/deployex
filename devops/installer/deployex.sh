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
    echo "    $0 --install deployex.yaml"
    echo
    echo "  Update an application:"
    echo "    $0 --update deployex.yaml"
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
    local yaml_file=$(realpath "${1}")
    local otp_tls_certificates="${2}"
    local app_name="${3}"

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

    mkdir /var/log/${app_name}/
    chown deployex:deployex /var/log/${app_name}/

    printf "%s\n" "${DEPLOYEX_SYSTEMD_FILE}" > ${DEPLOYEX_SYSTEMD_PATH}
    echo "#    Deployex installed with success       #"
}

update_deployex() {
  local VERSION=$1
  local OS_TARGET=$2
  local OTP_VERSION=$3
    echo ""
    echo "#           Updating Deployex              #"
    cd /tmp
    echo "# Download the deployex version: ${VERSION} #"
    rm -f deployex-ubuntu-*.tar.gz
     #wget https://github.com/thiagoesteves/deployex/releases/download/${VERSION}/deployex-${OS_TARGET}-otp-${OTP_VERSION}.tar.gz
    wget https://deployex-testing-storage.s3.sa-east-1.amazonaws.com/deployex-${OS_TARGET}-otp-${OTP_VERSION}.tar.gz

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
    tar xf /tmp/deployex-${OS_TARGET}-otp-${OTP_VERSION}.tar.gz
    echo "# Start systemd                            #"
    echo "# Start new service                        #"
    systemctl daemon-reload
    systemctl enable --now ${DEPLOYEX_SERVICE_NAME}
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --install)
            operation=install
            config_file=$2
            shift
            ;;
        --update)
            operation=update
            config_file=$2
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
if [[ -z $operation || -z $config_file ]]; then
    usage
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
app_name=$(yq '.applications[0].name' $config_file | tr -d '"')

# Check if all required parameters are provided based on the operation
if [ $operation == install ]; then
    if [[ -z $version || 
          -z $otp_version ||
          -z $otp_tls_certificates ||
          -z $app_name ||
          -z $os_target ]]; then
        usage
    fi
    remove_deployex
    install_deployex $config_file $otp_tls_certificates $app_name
    update_deployex $version $os_target $otp_version
elif [ $operation == update ]; then
    if [[ -z $version || -z $os_target || -z $otp_version ]]; then
        usage
    fi
    update_deployex $version $os_target $otp_version
else
    usage
fi
