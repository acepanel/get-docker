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
File_openEulerRelease=/etc/openEuler-release
File_HuaweiCloudEulerOSRelease=/etc/hce-release
File_OpenCloudOSRelease=/etc/opencloudos-release
File_TencentOSServerRelease=/etc/tlinux-release
File_AnolisOSRelease=/etc/anolis-release
File_AlibabaCloudLinuxRelease=/etc/alinux-release
File_OracleLinuxRelease=/etc/oracle-release
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
File_DockerSourceList=$Dir_AptAdditionalSources/docker.list
File_DockerRepo=$Dir_YumRepos/docker-ce.repo

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
    [ "$1" ] && echo -e "\n[ERROR] $1\n"
    exit 1
}

function command_error() {
    local tmp_text="Please confirm and re-enter"
    if [[ "${2}" ]]; then
        tmp_text="Please specify ${2} after this option"
    fi
    output_error "Command option '$1' is invalid, ${tmp_text}!"
}

function unsupport_system_error() {
    if [[ "${2}" ]]; then
        output_error "Unsupported operating system (${1}), please install manually with commands:\n\n$2"
    else
        output_error "Unsupported operating system (${1})"
    fi
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
        output_error "Insufficient privileges, please run this script as root. Switch command: ${change_cmd}"
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
    ## 定义系统版本号
    SYSTEM_VERSION_ID="$(get_os_release_value VERSION_ID)"
    SYSTEM_VERSION_ID_MAJOR="${SYSTEM_VERSION_ID%%.*}"
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
    x86_64 | aarch64 | armv8l | armv7l | armv6l | armv5tel | ppc64le | s390x) ;;
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
    local package_manager
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
    echo -e "[INFO] Updating package index..."
    case "${SYSTEM_FACTIONS}" in
    "${SYSTEM_DEBIAN}" | "${SYSTEM_OPENKYLIN}")
        package_manager="apt-get"
        ${package_manager} update
        ;;
    "${SYSTEM_REDHAT}" | "${SYSTEM_OPENEULER}" | "${SYSTEM_OPENCLOUDOS}" | "${SYSTEM_ANOLISOS}" | "${SYSTEM_TENCENTOS}" | "${SYSTEM_KYLIN_SERVER}")
        package_manager="$(get_package_manager)"
        ${package_manager} makecache
        ;;
    esac
    if [ $? -ne 0 ]; then
        output_error "${SYNC_MIRROR_TEXT} failed. Please fix system software sources (package repositories) so the ${package_manager} package manager is available!"
    fi

    case "${SYSTEM_FACTIONS}" in
    "${SYSTEM_DEBIAN}" | "${SYSTEM_OPENKYLIN}")
        ${package_manager} install -y ca-certificates curl
        ;;
    "${SYSTEM_REDHAT}" | "${SYSTEM_OPENEULER}" | "${SYSTEM_OPENCLOUDOS}" | "${SYSTEM_ANOLISOS}" | "${SYSTEM_TENCENTOS}" | "${SYSTEM_KYLIN_SERVER}")
        if [[ "${SYSTEM_VERSION_ID_MAJOR}" == "7" ]] || [[ "${package_manager}" != "dnf" ]]; then
            ${package_manager} install -y yum-utils device-mapper-persistent-data lvm2
        else
            ${package_manager} install -y dnf-plugins-core
        fi
        ;;
    esac
}

## 配置 Docker CE 源
function configure_docker_ce_mirror() {
    case "${SYSTEM_FACTIONS}" in
    "${SYSTEM_DEBIAN}" | "${SYSTEM_OPENKYLIN}")
        ## 处理 GPG 密钥
        local file_keyring="/etc/apt/keyrings/docker.asc"
        apt-key del 9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88 >/dev/null 2>&1
        [ -f "${file_keyring}" ] && rm -rf $file_keyring
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL "${WEB_PROTOCOL}://${SOURCE}/linux/${SOURCE_BRANCH}/gpg" -o $file_keyring >/dev/null
        if [ $? -ne 0 ]; then
            output_error "GPG key download failed, please check network or switch Docker CE mirror and retry!"
        fi
        chmod a+r $file_keyring
        ## 添加源
        [ -d "${Dir_AptAdditionalSources}" ] || mkdir -p $Dir_AptAdditionalSources
        echo "deb [arch=$(dpkg --print-architecture) signed-by=${file_keyring}] ${WEB_PROTOCOL}://${SOURCE}/linux/${SOURCE_BRANCH} ${DEBIAN_CODENAME:-"${SOURCE_BRANCH_CODENAME:-"${SYSTEM_VERSION_CODENAME}"}"} stable" >$File_DockerSourceList
        apt-get update
        ;;
    "${SYSTEM_REDHAT}" | "${SYSTEM_OPENEULER}" | "${SYSTEM_OPENCLOUDOS}" | "${SYSTEM_ANOLISOS}" | "${SYSTEM_TENCENTOS}" | "${SYSTEM_KYLIN_SERVER}")
        local repo_file_url="${WEB_PROTOCOL}://${SOURCE}/linux/${SOURCE_BRANCH}/docker-ce.repo"
        local package_manager="$(get_package_manager)"
        if [[ "${SYSTEM_VERSION_ID_MAJOR}" == "7" ]]; then
            yum-config-manager -y --add-repo "${repo_file_url}"
        elif [[ "${SYSTEM_JUDGMENT}" == "${SYSTEM_FEDORA}" ]]; then
            dnf-3 config-manager -y --add-repo "${repo_file_url}"
        elif [[ "${package_manager}" == "dnf" ]]; then
            dnf config-manager -y --add-repo "${repo_file_url}"
        else
            yum-config-manager -y --add-repo "${repo_file_url}"
        fi
        sed -e "s|https://download.docker.com|${WEB_PROTOCOL}://${SOURCE}|g" \
            -e "s|http[s]\?://.*/linux/${SOURCE_BRANCH}/|${WEB_PROTOCOL}://${SOURCE}/linux/${SOURCE_BRANCH}/|g" \
            -i $File_DockerRepo
        ## 处理版本号
        local target_version="${SOURCE_BRANCH_VERSION}"
        if [[ -z "${target_version}" ]] && [[ "${SYSTEM_JUDGMENT}" != "${SYSTEM_FEDORA}" ]]; then
            target_version="${SYSTEM_VERSION_ID_MAJOR}"
            case "${SYSTEM_VERSION_ID_MAJOR}" in
            7 | 8 | 9 | 10) ;;
            *)
                target_version="8"
                # OpenCloudOS、Anolis OS 23 版本
                if [[ "${SYSTEM_VERSION_ID_MAJOR}" == "23" ]]; then
                    [[ "${SYSTEM_JUDGMENT}" == "${SYSTEM_OPENCLOUDOS}" || "${SYSTEM_JUDGMENT}" == "${SYSTEM_ANOLISOS}" ]] && target_version="9"
                fi
                # openEuler / Huawei Cloud EulerOS
                if [[ "${SYSTEM_JUDGMENT}" == "${SYSTEM_OPENEULER}" ]]; then
                    if [ -s "${File_HuaweiCloudEulerOSRelease}" ]; then
                        [[ "${SYSTEM_VERSION_ID_MAJOR}" == "2" ]] && target_version="9"
                    elif [[ "${SYSTEM_VERSION_ID_MAJOR}" -ge 22 ]]; then
                        target_version="9"
                    fi
                fi
                # TencentOS Server
                if [ -s "${File_TencentOSServerRelease}" ]; then
                    case "${SYSTEM_VERSION_ID_MAJOR}" in
                    4) target_version="9" ;;
                    3) target_version="8" ;;
                    2) target_version="7" ;;
                    esac
                fi
                # Alibaba Cloud Linux
                if [ -s "${File_AnolisOSRelease}" ] && [ -s "${File_AlibabaCloudLinuxRelease}" ]; then
                    [[ "${SYSTEM_VERSION_ID_MAJOR}" == "2" ]] && target_version="7"
                fi
                # Kylin Server
                if [[ "${SYSTEM_JUDGMENT}" == "${SYSTEM_KYLIN_SERVER}" ]]; then
                    case "${SYSTEM_VERSION_ID_MAJOR}" in
                    "V10") target_version="8" ;;
                    *) target_version="10" ;;
                    esac
                fi
                ;;
            esac
        fi
        if [[ "${target_version}" ]]; then
            sed -e "s|\$releasever|${target_version}|g" -i $File_DockerRepo
            ${package_manager} makecache
        fi
        ;;
    esac
}

## 安装 Docker Engine
function install_docker_engine() {
    ## 卸载 Docker Engine 原有版本软件包
    if command_exists docker; then
        systemctl disable --now docker >/dev/null 2>&1
        sleep 2s
    fi
    local package_list package_manager
    case "${SYSTEM_FACTIONS}" in
    "${SYSTEM_DEBIAN}" | "${SYSTEM_OPENKYLIN}")
        package_list='docker* podman podman-docker containerd runc'
        apt-get remove -y $package_list >/dev/null 2>&1
        apt-get autoremove -y >/dev/null 2>&1
        ;;
    "${SYSTEM_REDHAT}" | "${SYSTEM_OPENEULER}" | "${SYSTEM_OPENCLOUDOS}" | "${SYSTEM_ANOLISOS}" | "${SYSTEM_TENCENTOS}" | "${SYSTEM_KYLIN_SERVER}")
        package_list='docker* podman podman-docker runc'
        package_manager="$(get_package_manager)"
        $package_manager remove -y $package_list >/dev/null 2>&1
        $package_manager autoremove -y >/dev/null 2>&1
        ;;
    esac

    ## 安装
    local pkgs="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    echo -e "[INFO] Installing Docker Engine..."
    case "${SYSTEM_FACTIONS}" in
    "${SYSTEM_DEBIAN}" | "${SYSTEM_OPENKYLIN}")
        apt-get install -y ${pkgs}
        ;;
    "${SYSTEM_REDHAT}" | "${SYSTEM_OPENEULER}" | "${SYSTEM_OPENCLOUDOS}" | "${SYSTEM_ANOLISOS}" | "${SYSTEM_TENCENTOS}" | "${SYSTEM_KYLIN_SERVER}")
        $(get_package_manager) install -y ${pkgs}
        ;;
    esac
    [ $? -ne 0 ] && output_error "Docker Engine installation failed!"
}

## 修改 Docker Registry 镜像仓库源
function change_docker_registry_mirror() {
    if [ -d "${Dir_Docker}" ] && [ -e "${File_DockerConfig}" ]; then
        echo -e "[INFO] Backing up Docker config..."
        cp -rvf $File_DockerConfig $File_DockerConfigBackup 2>&1
        echo -e "[OK] Original Docker config file has been backed up"
        sleep 2s
    else
        mkdir -p $Dir_Docker >/dev/null 2>&1
    fi

    local mirrors="$(format_registry_mirrors ${SOURCE_REGISTRY})"
    echo -e '{\n  "registry-mirrors": '"${mirrors}"'\n}' >$File_DockerConfig
    systemctl daemon-reload
    [[ "$(systemctl is-active docker 2>/dev/null)" == "active" ]] && systemctl restart docker
}

function format_registry_mirrors() {
    local input="${1//[ ,]/ }"
    local result=""
    for item in $input; do
        [[ -z "${item}" ]] && continue
        [[ -n "${result}" ]] && result+=","
        result+='"https://'"${item}"'"'
    done
    echo "[${result}]"
}

## 查看版本并验证安装结果
function check_installed_result() {
    if ! command_exists docker; then
        echo -e "[FAIL] Installation failed"
        return 1
    fi

    systemctl enable --now docker >/dev/null 2>&1
    echo -en "[OK] "
    docker -v
    if [ $? -ne 0 ]; then
        echo -e "[FAIL] Installation failed"
        local source_file package_manager
        case "${SYSTEM_FACTIONS}" in
        "${SYSTEM_DEBIAN}" | "${SYSTEM_OPENKYLIN}")
            source_file="${File_DockerSourceList}"
            package_manager="apt-get"
            ;;
        *)
            source_file="${File_DockerRepo}"
            package_manager="$(get_package_manager)"
            ;;
        esac
        echo -e "Check source file: cat ${source_file}"
        echo -e "Please try manually executing installation command: ${package_manager} install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin\n"
        exit 1
    fi

    echo -e "  $(docker compose version 2>&1)"

    if [[ "$(systemctl is-active docker 2>/dev/null)" != "active" ]]; then
        sleep 2
        systemctl disable --now docker >/dev/null 2>&1
        sleep 2
        systemctl enable --now docker >/dev/null 2>&1
        sleep 2
        if [[ "$(systemctl is-active docker)" != "active" ]]; then
            echo -e "[WARN] Detected Docker service startup error, try running this script again"
            local start_cmd="systemctl start docker"
            command_exists systemctl || start_cmd="service docker start"
            echo -e "[TIP] Please execute '${start_cmd}' command to try starting or investigate error cause"
        fi
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
