#!/bin/bash
## Author: SuperManito
## Author: AcePanel
## Modified: 2025-11-28
## License: MIT
## GitHub: https://github.com/acepanel/get-docker

##############################################################################

## 定义系统判定变量
SYSTEM_DEBIAN="Debian"
SYSTEM_UBUNTU="Ubuntu"
SYSTEM_ZORIN="Zorin"
SYSTEM_REDHAT="RedHat"
SYSTEM_RHEL="Red Hat Enterprise Linux"
SYSTEM_CENTOS="CentOS"
SYSTEM_CENTOS_STREAM="CentOS Stream"
SYSTEM_ROCKY="Rocky"
SYSTEM_ALMALINUX="AlmaLinux"
SYSTEM_FEDORA="Fedora"
SYSTEM_ORACLE="Oracle Linux"
SYSTEM_OPENCLOUDOS="OpenCloudOS"
SYSTEM_OPENCLOUDOS_STREAM="OpenCloudOS Stream"
SYSTEM_TENCENTOS="TencentOS"
SYSTEM_OPENEULER="openEuler"
SYSTEM_ANOLISOS="Anolis"
SYSTEM_KYLIN_SERVER="Kylin Server"
SYSTEM_OPENKYLIN="openKylin"

## 定义系统版本文件
File_LinuxRelease=/etc/os-release
File_RedHatRelease=/etc/redhat-release
File_DebianVersion=/etc/debian_version
File_ArmbianRelease=/etc/armbian-release
File_RaspberryPiOSRelease=/etc/rpi-issue
File_openEulerRelease=/etc/openEuler-release
File_HuaweiCloudEulerOSRelease=/etc/hce-release
File_OpenCloudOSRelease=/etc/opencloudos-release
File_TencentOSServerRelease=/etc/tlinux-release
File_AnolisOSRelease=/etc/anolis-release
File_AlibabaCloudLinuxRelease=/etc/alinux-release
File_OracleLinuxRelease=/etc/oracle-release
File_ManjaroRelease=/etc/manjaro-release
File_AlpineRelease=/etc/alpine-release
File_KylinRelease=/etc/kylin-release
File_kylinVersion=/etc/kylin-version/kylin-system-version.conf

## 定义软件源相关文件或目录
File_AptSourceList=/etc/apt/sources.list
Dir_AptAdditionalSources=/etc/apt/sources.list.d
Dir_YumRepos=/etc/yum.repos.d

## 定义 Docker 相关变量
Dir_Docker=/etc/docker
File_DockerConfig=$Dir_Docker/daemon.json
File_DockerConfigBackup=$Dir_Docker/daemon.json.bak
File_DockerVersionTmp=docker-version.txt
File_DockerCEVersionTmp=docker-ce-version.txt
File_DockerCECliVersionTmp=docker-ce-cli-version.txt
File_DockerSourceList=$Dir_AptAdditionalSources/docker.list
File_DockerRepo=$Dir_YumRepos/docker-ce.repo

## 定义颜色和样式变量
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
PURPLE='\033[35m'
AZURE='\033[36m'
PLAIN='\033[0m'
BOLD='\033[1m'
SUCCESS="\033[1;32m✔${PLAIN}"
COMPLETE="\033[1;32m✔${PLAIN}"
WARN="\033[1;43m 警告 ${PLAIN}"
ERROR="\033[1;31m✘${PLAIN}"
FAIL="\033[1;31m✘${PLAIN}"
TIP="\033[1;44m 提示 ${PLAIN}"
WORKING="\033[1;36m◉${PLAIN}"

function main() {
    permission_judgment
    collect_system_info
    install_dependency_packages
    configure_docker_ce_mirror
    install_docker_engine
    change_docker_registry_mirror
    check_installed_result
}

function handle_command_options() {
    ## 判断参数
    while [ $# -gt 0 ]; do
        case "$1" in
        ## 指定 Docker CE 软件源地址
        --source)
            if [ "$2" ]; then
                echo "$2" | grep -Eq "\(|\)|\[|\]|\{|\}"
                if [ $? -eq 0 ]; then
                    command_error "$2" "a valid address"
                else
                    SOURCE="$(echo "$2" | sed -e 's,^http[s]\?://,,g' -e 's,/$,,')"
                    shift
                fi
            else
                command_error "$1" "mirror address"
            fi
            ;;
        ## 指定 Docker Registry 仓库地址
        --source-registry)
            if [ "$2" ]; then
                echo "$2" | grep -Eq "\(|\)|\[|\]|\{|\}"
                if [ $? -eq 0 ]; then
                    command_error "$2" "a valid address"
                else
                    SOURCE_REGISTRY="$(echo "$2" | sed -e 's,^http[s]\?://,,g' -e 's,/$,,')"
                    shift
                fi
            else
                command_error "$1" "registry mirror address"
            fi
            ;;
        ## 指定 Docker CE 软件源仓库
        --branch)
            if [ "$2" ]; then
                SOURCE_BRANCH="$2"
                shift
            else
                command_error "$1" "mirror repository"
            fi
            ;;
        ## 指定 Docker CE 软件源仓库版本
        --branch-version)
            if [ "$2" ]; then
                echo "$2" | grep -Eq "^[0-9]{1,2}$"
                if [ $? -eq 0 ]; then
                    SOURCE_BRANCH_VERSION="$2"
                    shift
                else
                    command_error "$2" "a valid version number"
                fi
            else
                command_error "$1" "Docker CE mirror repository version"
            fi
            ;;
        ## 指定 Debian 版本代号
        --codename)
            if [ "$2" ]; then
                DEBIAN_CODENAME="$2"
                shift
            else
                command_error "$1" "version codename"
            fi
            ;;
        ## Web 协议（HTTP/HTTPS）
        --protocol)
            if [ "$2" ]; then
                case "$2" in
                http | https | HTTP | HTTPS)
                    WEB_PROTOCOL="${2,,}"
                    shift
                    ;;
                *)
                    command_error "$2" " http or https "
                    ;;
                esac
            else
                command_error "$1" " Web protocol(http/https)"
            fi
            ;;
        *)
            command_error "$1"
            ;;
        esac
        shift
    done
}

function output_error() {
    [ "$1" ] && echo -e "\n$ERROR $1\n"
    exit 1
}

function command_error() {
    local tmp_text="Please confirm and re-enter"
    if [[ "${2}" ]]; then
        tmp_text="Please specify ${2} after this option"
    fi
    output_error "Command option ${BLUE}$1${PLAIN} is invalid, ${tmp_text}!"
}

function unsupport_system_error() {
    if [[ "${2}" ]]; then
        output_error "Unsupported operating system (${1}), please install manually with commands:\n\n${BLUE}$2${PLAIN}"
    else
        output_error "Unsupported operating system (${1})"
    fi
}

function input_error() {
    echo -e "\n$WARN Input error, ${1}!"
}

function command_exists() {
    command -v "$@" &>/dev/null
}

function permission_judgment() {
    if [ $UID -ne 0 ]; then
        local change_cmd="su root"
        if command_exists sudo; then
            change_cmd="sudo -i"
        fi
        output_error "Insufficient privileges, please run this script as root. Switch command: ${BLUE}${change_cmd}${PLAIN}"
    fi
}

function get_os_release_value() {
    grep -E "^${1}=" $File_LinuxRelease | cut -d= -f2- | sed "s/[\'\"]//g"
}

function collect_system_info() {
    if [ ! -s "${File_LinuxRelease}" ]; then
        unsupport_system_error "Unknown system"
    fi
    ## 定义系统名称
    SYSTEM_NAME="$(get_os_release_value NAME)"
    SYSTEM_PRETTY_NAME="$(get_os_release_value PRETTY_NAME)"
    ## 定义系统版本号
    SYSTEM_VERSION_ID="$(get_os_release_value VERSION_ID)"
    SYSTEM_VERSION_ID_MAJOR="${SYSTEM_VERSION_ID%%.*}"
    SYSTEM_VERSION_ID_MINOR="${SYSTEM_VERSION_ID#*.}"
    ## 定义系统ID
    SYSTEM_ID="$(get_os_release_value ID)"
    ## 判定当前系统派系
    if [ -s "${File_DebianVersion}" ]; then
        SYSTEM_FACTIONS="${SYSTEM_DEBIAN}"
    elif [ -s "${File_RedHatRelease}" ]; then
        SYSTEM_FACTIONS="${SYSTEM_REDHAT}"
    elif [ -s "${File_openEulerRelease}" ] || [ -s "${File_HuaweiCloudEulerOSRelease}" ]; then
        SYSTEM_FACTIONS="${SYSTEM_OPENEULER}"
    elif [ -s "${File_OpenCloudOSRelease}" ]; then
        SYSTEM_FACTIONS="${SYSTEM_OPENCLOUDOS}" # 自 9.0 版本起不再基于红帽
    elif [ -s "${File_AnolisOSRelease}" ]; then
        SYSTEM_FACTIONS="${SYSTEM_ANOLISOS}" # 自 8.8 版本起不再基于红帽
    elif [ -s "${File_TencentOSServerRelease}" ]; then
        SYSTEM_FACTIONS="${SYSTEM_TENCENTOS}" # 自 4 版本起不再基于红帽
    elif [ -s "${File_kylinVersion}" ] || [ -s "${File_KylinRelease}" ]; then
        if [[ "${SYSTEM_ID}" == *"openkylin"* ]]; then
            SYSTEM_FACTIONS="${SYSTEM_OPENKYLIN}"
        else
            SYSTEM_FACTIONS="${SYSTEM_KYLIN_SERVER}"
        fi
    else
        unsupport_system_error "Unknown system"
    fi
    ## 判定系统类型、版本、版本号
    case "${SYSTEM_FACTIONS}" in
    "${SYSTEM_DEBIAN}" | "${SYSTEM_OPENKYLIN}")
        if command_exists lsb_release; then
            SYSTEM_JUDGMENT="$(lsb_release -is)"
            SYSTEM_VERSION_CODENAME="${DEBIAN_CODENAME:-"$(lsb_release -cs)"}"
        else
            ## https://codeberg.org/gioele/lsb-release-minimal
            SYSTEM_JUDGMENT="${SYSTEM_ID^}"
            if [ "${SYSTEM_NAME}" ]; then
                if [[ "${SYSTEM_ID,,}" == "${SYSTEM_NAME,,}" ]]; then
                    SYSTEM_JUDGMENT="${SYSTEM_NAME}"
                fi
            fi
            SYSTEM_VERSION_CODENAME="${DEBIAN_CODENAME:-"$(get_os_release_value VERSION_CODENAME)"}"
        fi
        ;;
    "${SYSTEM_REDHAT}")
        SYSTEM_JUDGMENT="$(awk '{printf $1}' $File_RedHatRelease)"
        ## 特殊系统判断
        # Red Hat Enterprise Linux
        grep -q "${SYSTEM_RHEL}" $File_RedHatRelease && SYSTEM_JUDGMENT="${SYSTEM_RHEL}"
        # CentOS Stream
        grep -q "${SYSTEM_CENTOS_STREAM}" $File_RedHatRelease && SYSTEM_JUDGMENT="${SYSTEM_CENTOS_STREAM}"
        # Oracle Linux
        [ -s "${File_OracleLinuxRelease}" ] && SYSTEM_JUDGMENT="${SYSTEM_ORACLE}"
        ;;
    *)
        SYSTEM_JUDGMENT="${SYSTEM_FACTIONS}"
        ;;
    esac
    ## 判定系统处理器架构
    DEVICE_ARCH_RAW="$(uname -m)"
    case "${DEVICE_ARCH_RAW}" in
    x86_64)
        DEVICE_ARCH="x86_64"
        ;;
    aarch64)
        DEVICE_ARCH="ARM64"
        ;;
    armv8l)
        DEVICE_ARCH="ARMv8_32"
        ;;
    armv7l)
        DEVICE_ARCH="ARMv7"
        ;;
    armv6l)
        DEVICE_ARCH="ARMv6"
        ;;
    armv5tel)
        DEVICE_ARCH="ARMv5"
        ;;
    ppc64le)
        DEVICE_ARCH="ppc64le"
        ;;
    s390x)
        DEVICE_ARCH="s390x"
        ;;
    i386 | i686)
        output_error "Docker Engine does not support installation on x86_32 architecture!"
        ;;
    *)
        output_error "Unknown system architecture: ${DEVICE_ARCH_RAW}"
        ;;
    esac
    ## 定义软件源仓库名称
    if [[ -z "${SOURCE_BRANCH}" ]]; then
        case "${SYSTEM_FACTIONS}" in
        "${SYSTEM_DEBIAN}" | "${SYSTEM_OPENKYLIN}")
            local debian_codename_latest="trixie"
            case "${SYSTEM_JUDGMENT}" in
            "${SYSTEM_DEBIAN}")
                SOURCE_BRANCH="debian"
                ;;
            "${SYSTEM_UBUNTU}" | "${SYSTEM_ZORIN}")
                SOURCE_BRANCH="ubuntu"
                ;;
            "${SYSTEM_OPENKYLIN}")
                SOURCE_BRANCH="debian"
                SOURCE_BRANCH_CODENAME="${debian_codename_latest}"
                ;;
            *)
                # 其余 Debian 系衍生操作系统
                SOURCE_BRANCH="debian"
                SOURCE_BRANCH_CODENAME="bookworm"
                ;;
            esac
            ;;
        "${SYSTEM_REDHAT}" | "${SYSTEM_OPENEULER}" | "${SYSTEM_OPENCLOUDOS}" | "${SYSTEM_ANOLISOS}" | "${SYSTEM_TENCENTOS}" | "${SYSTEM_KYLIN_SERVER}")
            case "${SYSTEM_JUDGMENT}" in
            "${SYSTEM_FEDORA}")
                SOURCE_BRANCH="fedora"
                ;;
            "${SYSTEM_RHEL}")
                SOURCE_BRANCH="rhel"
                ;;
            *)
                SOURCE_BRANCH="centos"
                ;;
            esac
            if [[ "${DEVICE_ARCH_RAW}" == "s390x" ]]; then
                output_error "Please refer to RHEL distribution announcement for s390x support"
            fi
            ;;
        esac
    fi
    ## 定义软件源更新文字
    case "${SYSTEM_FACTIONS}" in
    "${SYSTEM_DEBIAN}" | "${SYSTEM_OPENKYLIN}")
        SYNC_MIRROR_TEXT="Update APT package index"
        ;;
    "${SYSTEM_REDHAT}" | "${SYSTEM_OPENEULER}" | "${SYSTEM_OPENCLOUDOS}" | "${SYSTEM_ANOLISOS}" | "${SYSTEM_TENCENTOS}" | "${SYSTEM_KYLIN_SERVER}")
        SYNC_MIRROR_TEXT="Generate mirror cache"
        ;;
    esac
}

## 安装环境包
function install_dependency_packages() {
    local commands package_manager
    ## 删除原有源
    case "${SYSTEM_FACTIONS}" in
    "${SYSTEM_DEBIAN}" | "${SYSTEM_OPENKYLIN}")
        sed -i '/docker-ce/d' $File_AptSourceList
        rm -rf $File_DockerSourceList
        ;;
    "${SYSTEM_REDHAT}" | "${SYSTEM_OPENEULER}" | "${SYSTEM_OPENCLOUDOS}" | "${SYSTEM_ANOLISOS}" | "${SYSTEM_TENCENTOS}" | "${SYSTEM_KYLIN_SERVER}")
        rm -rf $Dir_YumRepos/*docker*.repo
        ;;
    esac
    ## 更新软件源
    commands=()
    case "${SYSTEM_FACTIONS}" in
    "${SYSTEM_DEBIAN}" | "${SYSTEM_OPENKYLIN}")
        package_manager="apt-get"
        commands+=("${package_manager} update")
        ;;
    "${SYSTEM_REDHAT}" | "${SYSTEM_OPENEULER}" | "${SYSTEM_OPENCLOUDOS}" | "${SYSTEM_ANOLISOS}" | "${SYSTEM_TENCENTOS}" | "${SYSTEM_KYLIN_SERVER}")
        package_manager="$(get_package_manager)"
        commands+=("${package_manager} makecache")
        ;;
    esac
    echo ''
    for cmd in "${commands[@]}"; do
        eval "${cmd}"
    done
    if [ $? -ne 0 ]; then
        output_error "${SYNC_MIRROR_TEXT} failed. Please fix system software sources (package repositories) so the ${BLUE}${package_manager}${PLAIN} package manager is available!"
    fi

    commands=()
    case "${SYSTEM_FACTIONS}" in
    "${SYSTEM_DEBIAN}" | "${SYSTEM_OPENKYLIN}")
        commands+=("${package_manager} install -y ca-certificates curl")
        ;;
    "${SYSTEM_REDHAT}" | "${SYSTEM_OPENEULER}" | "${SYSTEM_OPENCLOUDOS}" | "${SYSTEM_ANOLISOS}" | "${SYSTEM_TENCENTOS}" | "${SYSTEM_KYLIN_SERVER}")
        case "${SYSTEM_VERSION_ID_MAJOR}" in
        7)
            commands+=("${package_manager} install -y yum-utils device-mapper-persistent-data lvm2")
            ;;
        *)
            if [[ "${package_manager}" == "dnf" ]]; then
                commands+=("${package_manager} install -y dnf-plugins-core")
            else
                commands+=("${package_manager} install -y yum-utils device-mapper-persistent-data lvm2")
            fi
            ;;
        esac
        ;;
    esac
    for cmd in "${commands[@]}"; do
        eval "${cmd}"
    done
}

## 配置 Docker CE 源
function configure_docker_ce_mirror() {
    local -a commands=()
    case "${SYSTEM_FACTIONS}" in
    "${SYSTEM_DEBIAN}" | "${SYSTEM_OPENKYLIN}")
        ## 处理 GPG 密钥
        local file_keyring="/etc/apt/keyrings/docker.asc"
        apt-key del 9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88 >/dev/null 2>&1 # 删除旧的密钥
        [ -f "${file_keyring}" ] && rm -rf $file_keyring
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL "${WEB_PROTOCOL}://${SOURCE}/linux/${SOURCE_BRANCH}/gpg" -o $file_keyring >/dev/null
        if [ $? -ne 0 ]; then
            output_error "GPG key download failed, please check network or switch Docker CE mirror and retry!"
        fi
        chmod a+r $file_keyring
        ## 添加源
        [ -d "${Dir_AptAdditionalSources}" ] || mkdir -p $Dir_AptAdditionalSources
        local source_content="deb [arch=$(dpkg --print-architecture) signed-by=${file_keyring}] ${WEB_PROTOCOL}://${SOURCE}/linux/${SOURCE_BRANCH} ${DEBIAN_CODENAME:-"${SOURCE_BRANCH_CODENAME:-"${SYSTEM_VERSION_CODENAME}"}"} stable"
        echo "${source_content}" | tee $File_DockerSourceList >/dev/null 2>&1
        commands+=("apt-get update")
        ;;
    "${SYSTEM_REDHAT}" | "${SYSTEM_OPENEULER}" | "${SYSTEM_OPENCLOUDOS}" | "${SYSTEM_ANOLISOS}" | "${SYSTEM_TENCENTOS}" | "${SYSTEM_KYLIN_SERVER}")
        local repo_file_url="${WEB_PROTOCOL}://${SOURCE}/linux/${SOURCE_BRANCH}/docker-ce.repo"
        local package_manager="$(get_package_manager)"
        case "${SYSTEM_VERSION_ID_MAJOR}" in
        7)
            yum-config-manager -y --add-repo "${repo_file_url}"
            ;;
        *)
            if [[ "${SYSTEM_JUDGMENT}" == "${SYSTEM_FEDORA}" ]]; then
                dnf-3 config-manager -y --add-repo "${repo_file_url}"
            else
                if [[ "${package_manager}" == "dnf" ]]; then
                    dnf config-manager -y --add-repo "${repo_file_url}"
                else
                    yum-config-manager -y --add-repo "${repo_file_url}"
                fi
            fi
            ;;
        esac
        sed -e "s|https://download.docker.com|${WEB_PROTOCOL}://${SOURCE}|g" \
            -e "s|http[s]\?://.*/linux/${SOURCE_BRANCH}/|${WEB_PROTOCOL}://${SOURCE}/linux/${SOURCE_BRANCH}/|g" \
            -i \
            $File_DockerRepo
        ## 处理版本号
        if [[ "${SOURCE_BRANCH_VERSION}" ]]; then
            # 指定版本
            sed -e "s|\$releasever|${SOURCE_BRANCH_VERSION}|g" \
                -i \
                $File_DockerRepo
            commands+=("${package_manager} makecache")
        elif [[ "${SYSTEM_JUDGMENT}" != "${SYSTEM_FEDORA}" ]]; then
            # 兼容处理
            local target_version
            case "${SYSTEM_VERSION_ID_MAJOR}" in
            7 | 8 | 9 | 10)
                target_version="${SYSTEM_VERSION_ID_MAJOR}"
                ;;
            *)
                target_version="8" # 注：部分系统使用9版本分支会有兼容性问题
                ## 适配国产操作系统
                # OpenCloudOS、Anolis OS 的 23 版本
                if [[ "${SYSTEM_JUDGMENT}" == "${SYSTEM_OPENCLOUDOS}" || "${SYSTEM_JUDGMENT}" == "${SYSTEM_ANOLISOS}" ]]; then
                    if [[ "${SYSTEM_VERSION_ID_MAJOR}" == 23 ]]; then
                        target_version="9"
                    fi
                fi
                if [[ "${SYSTEM_JUDGMENT}" == "${SYSTEM_OPENEULER}" ]]; then
                    if [ -s "${File_HuaweiCloudEulerOSRelease}" ]; then
                        # Huawei Cloud EulerOS
                        case "${SYSTEM_VERSION_ID_MAJOR}" in
                        1)
                            target_version="8" # openEuler 20
                            ;;
                        2)
                            target_version="9" # openEuler 22
                            ;;
                        esac
                    else
                        # openEuler
                        if [[ "${SYSTEM_VERSION_ID_MAJOR}" -ge 22 ]]; then
                            target_version="9"
                        fi
                    fi
                fi
                # TencentOS Server
                if [ -s "${File_TencentOSServerRelease}" ]; then
                    case "${SYSTEM_VERSION_ID_MAJOR}" in
                    4)
                        target_version="9"
                        ;;
                    3)
                        target_version="8"
                        ;;
                    2)
                        target_version="7"
                        ;;
                    esac
                fi
                # Alibaba Cloud Linux
                if [ -s "${File_AnolisOSRelease}" ] && [ -s "${File_AlibabaCloudLinuxRelease}" ]; then
                    case "${SYSTEM_VERSION_ID_MAJOR}" in
                    3)
                        target_version="8"
                        ;;
                    2)
                        target_version="7"
                        ;;
                    esac
                fi
                if [[ "${SYSTEM_JUDGMENT}" == "${SYSTEM_KYLIN_SERVER}" ]]; then
                    case "${SYSTEM_VERSION_ID_MAJOR}" in
                    "V10")
                        target_version="8"
                        ;;
                    "V11")
                        target_version="10"
                        ;;
                    *)
                        target_version="10"
                        ;;
                    esac
                fi
                ;;
            esac
            sed -e "s|\$releasever|${target_version}|g" \
                -i \
                $File_DockerRepo
            commands+=("${package_manager} makecache")
        fi
        ;;
    esac
    for cmd in "${commands[@]}"; do
        eval "${cmd}"
    done
}

## 安装 Docker Engine
function install_docker_engine() {
    ## 卸载 Docker Engine 原有版本软件包
    function uninstall_original_version() {
        if command_exists docker; then
            # 先停止并禁用 Docker 服务
            systemctl disable --now docker >/dev/null 2>&1
            sleep 2s
        fi
        # 确定需要卸载的软件包
        local package_list
        case "${SYSTEM_FACTIONS}" in
        "${SYSTEM_DEBIAN}" | "${SYSTEM_OPENKYLIN}")
            package_list='docker* podman podman-docker containerd runc'
            ;;
        "${SYSTEM_REDHAT}" | "${SYSTEM_OPENEULER}" | "${SYSTEM_OPENCLOUDOS}" | "${SYSTEM_ANOLISOS}" | "${SYSTEM_TENCENTOS}" | "${SYSTEM_KYLIN_SERVER}")
            package_list='docker* podman podman-docker runc'
            ;;
        esac
        # 卸载软件包并清理残留
        case "${SYSTEM_FACTIONS}" in
        "${SYSTEM_DEBIAN}" | "${SYSTEM_OPENKYLIN}")
            apt-get remove -y $package_list >/dev/null 2>&1
            apt-get autoremove -y >/dev/null 2>&1
            ;;
        "${SYSTEM_REDHAT}" | "${SYSTEM_OPENEULER}" | "${SYSTEM_OPENCLOUDOS}" | "${SYSTEM_ANOLISOS}" | "${SYSTEM_TENCENTOS}" | "${SYSTEM_KYLIN_SERVER}")
            local package_manager="$(get_package_manager)"
            $package_manager remove -y $package_list >/dev/null 2>&1
            $package_manager autoremove -y >/dev/null 2>&1
            ;;
        esac
    }

    ## 安装
    function install_main() {
        local target_docker_version
        local pkgs=""
        local -a commands=()
        pkgs="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
        case "${SYSTEM_FACTIONS}" in
        "${SYSTEM_DEBIAN}" | "${SYSTEM_OPENKYLIN}")
            commands+=("apt-get install -y ${pkgs}")
            ;;
        "${SYSTEM_REDHAT}" | "${SYSTEM_OPENEULER}" | "${SYSTEM_OPENCLOUDOS}" | "${SYSTEM_ANOLISOS}" | "${SYSTEM_TENCENTOS}" | "${SYSTEM_KYLIN_SERVER}")
            commands+=("$(get_package_manager) install -y ${pkgs}")
            ;;
        esac
        echo ''
        for cmd in "${commands[@]}"; do
            eval "${cmd}"
        done
        [ $? -ne 0 ] && output_error "Docker Engine installation failed!"
    }

    uninstall_original_version
    install_main
}

## 修改 Docker Registry 镜像仓库源
function change_docker_registry_mirror() {
    ## 备份原有配置文件
    if [ -d "${Dir_Docker}" ] && [ -e "${File_DockerConfig}" ]; then
        echo ''
        cp -rvf $File_DockerConfig $File_DockerConfigBackup 2>&1
        echo -e "\n$COMPLETE Original Docker config file has been backed up"
        sleep 2s
    else
        mkdir -p $Dir_Docker >/dev/null 2>&1
        touch $File_DockerConfig
    fi

    echo -e '{\n  "registry-mirrors": '"$(handleRegistryMirrorsValue ${SOURCE_REGISTRY})"'\n}' >$File_DockerConfig
    ## 重启服务
    systemctl daemon-reload
    if [[ "$(systemctl is-active docker 2>/dev/null)" == "active" ]]; then
        systemctl restart docker
    fi
}

function handleRegistryMirrorsValue() {
    local content="$1"
    local result=""
    content="$(echo "${content}" | sed 's| ||g')"
    local -a items=(${content//,/ })
    for item in "${items[@]}"; do
        [[ -z "${item}" ]] && continue
        if [[ -z "${result}" ]]; then
            result='"https://'"${item}"'"'
        else
            result="${result},\"https://${item}\""
        fi
    done
    if [[ "${result}" ]]; then
        echo "[${result}]"
    else
        echo ""
    fi
}

## 查看版本并验证安装结果
function check_installed_result() {
    if command_exists docker; then
        systemctl enable --now docker >/dev/null 2>&1
        echo -en "\n$COMPLETE "
        docker -v
        if [ $? -eq 0 ]; then
            echo -e "  $(docker compose version 2>&1)"
            # echo -e "\n$COMPLETE 安装完成"
        else
            echo -e "\n$FAIL Installation failed"
            local source_file package_manager
            case "${SYSTEM_FACTIONS}" in
            "${SYSTEM_DEBIAN}" | "${SYSTEM_OPENKYLIN}")
                source_file="${File_DockerSourceList}"
                package_manager="apt-get"
                ;;
            "${SYSTEM_REDHAT}" | "${SYSTEM_OPENEULER}" | "${SYSTEM_OPENCLOUDOS}" | "${SYSTEM_ANOLISOS}" | "${SYSTEM_TENCENTOS}" | "${SYSTEM_KYLIN_SERVER}")
                source_file="${File_DockerRepo}"
                package_manager="$(get_package_manager)"
                ;;
            esac
            echo -e "\nCheck source file: cat ${source_file}"
            echo -e "Please try manually executing installation command: ${package_manager} install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin\n"
            exit 1
        fi
        if [[ "$(systemctl is-active docker 2>/dev/null)" != "active" ]]; then
            sleep 2
            systemctl disable --now docker >/dev/null 2>&1
            sleep 2
            systemctl enable --now docker >/dev/null 2>&1
            sleep 2
            if [[ "$(systemctl is-active docker)" != "active" ]]; then
                echo -e "\n$WARN Detected Docker service startup error, try running this script again"
                local start_cmd
                if command_exists systemctl; then
                    start_cmd="systemctl start docker"
                else
                    start_cmd="service docker start"
                fi
                echo -e "\n$TIP Please execute ${BLUE}${start_cmd}${PLAIN} command to try starting or investigate error cause"
            fi
        fi
    else
        echo -e "\n$FAIL Installation failed"
    fi
}

## 选择系统包管理器
function get_package_manager() {
    local command="yum"
    case "${SYSTEM_JUDGMENT}" in
    "${SYSTEM_RHEL}" | "${SYSTEM_CENTOS_STREAM}" | "${SYSTEM_ROCKY}" | "${SYSTEM_ALMALINUX}" | "${SYSTEM_ORACLE}")
        case "${SYSTEM_VERSION_ID_MAJOR}" in
        9 | 10)
            command="dnf"
            ;;
        esac
        ;;
    "${SYSTEM_FEDORA}" | "${SYSTEM_OPENEULER}" | "${SYSTEM_OPENCLOUDOS}" | "${SYSTEM_ANOLISOS}" | "${SYSTEM_TENCENTOS}" | "${SYSTEM_KYLIN_SERVER}")
        command="dnf"
        ;;
    esac
    echo "${command}"
}

##############################################################################

handle_command_options "$@"
main
