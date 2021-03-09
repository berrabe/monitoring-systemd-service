#!/bin/bash

# ====================================================================
_LIST_SERVICES_=( "docker" "sshd" "nginx" )
_RESTART_DELAY_=3
_LOG_FILE_="$(pwd)/ms.log"

_TOKEN_TELEGRAM_="110xxx:Axxx_xxxx"
_CHAT_ID_="-100xxxxx"
# ====================================================================

_LIST_TOOLS_=( "curl" "awk" "sed" "jq" )

# List of Colors
Light_Red="\033[1;31m"
Light_Green="\033[1;32m"
Yellow="\033[1;33m"
Light_Blue="\033[1;34m"
Light_Purple="\033[1;35m"
Light_Cyan="\033[1;36m"
NoColor="\033[0m"

function logger() {
    category=$1
    message=$2
    printf "%-12s %s |-----> %s\n"  "[ $category ]" "$(date '+%d-%b-%y %H:%M:%S')" "$message" >> $_LOG_FILE_ 2>&1
}

function printf_() {
    if [[ $2 == 'title' ]]; then
        printf "\n\n\t\t ${Light_Purple}%s${NoColor} \n" "$1"
    elif [[ $2 == 'header' ]]; then
        printf "\n\n${Light_Cyan} [+] %-20s ${NoColor} \n" "$1"
    else
        printf "  |--[+] %-20b : %b\n" "$1" "$2"
    fi
}

function check_program() {
    for _arr_tools_ in ${_LIST_TOOLS_[@]}; do
        if ! [ -x "$(command -v $_arr_tools_)" ]; then
            printf_ "ERROR | $_arr_tools_ Is Not Installed" header
            logger "PROV" "ERROR | $_arr_tools_ Is Not Installed"
            exit 1
        fi
    done
}

function check_failed_services() {
    _service_name_=$1
    _failed_state_=$(systemctl status $_arr_service_ 2> /dev/null | grep -w 'Active:' | awk '{print $2}')

    if [[ $_failed_state_ == "failed" ]]; then
        printf_ "$_service_name_" "${Light_Red}STATE FAILED${NoColor}"
        logger "STATE" "Service $_service_name_ State FAILED"
        _SERVICE_BUFFER_="$_SERVICE_BUFFER_+$_service_name_"
        return 1
    elif [[ $_failed_state_ == "active" ]]; then
        printf_ "$_service_name_" "${Light_Green}STATE ACTIVE${NoColor}"
        logger "STATE" "Service $_service_name_ State ACTIVE"
        return 0
    fi
}


function check_inactive_services() {
    _SERVICE_BUFFER_=""
    printf_ "Checking Service Stat" header

    for _arr_service_ in ${_LIST_SERVICES_[@]}; do
        _inactive_state_=$(systemctl status $_arr_service_ 2> /dev/null | grep -w 'Active:' | awk '{print $2}')

        if [[ $_inactive_state_ == "inactive" ]]; then
            printf_ "$_arr_service_" "${Light_Red}STATE INACTIVE${NoColor}"
            logger "STATE" "Service $_arr_service_ State INACTIVE"
            _SERVICE_BUFFER_="$_SERVICE_BUFFER_+$_arr_service_"
        else
            check_failed_services $_arr_service_
        fi
    done
}

function restart_services() {
    _NOTIF_BUFFER_=""
    printf_ "Re-Starting Service" header
    _SERVICE_BUFFER_=$(echo -e $_SERVICE_BUFFER_ | sed 's/+/ /g')

    for _arr_service_ in $_SERVICE_BUFFER_; do
        systemctl restart $_arr_service_ > /dev/null 2>&1

        if [[ $? -eq 0 ]]; then
            logger "RESTART" "Service $_arr_service_ Successfully Restarted"
            sleep $_RESTART_DELAY_

            check_failed_services $_arr_service_
            if [[ $? -ne 0 ]]; then
                _NOTIF_BUFFER_="$_NOTIF_BUFFER_+$_arr_service_"
            fi
        else
            printf_ "$_arr_service_" "${Light_Red}RESTARTING FAILED${NoColor}"
            logger "RESTART" "Service $_arr_service_ Failed to Restart"
            _NOTIF_BUFFER_="$_NOTIF_BUFFER_+$_arr_service_"
        fi
    done
}

function notif_telegram() {
    printf_ "Sending Telegram Notif" header
    if [[ ! -n "$_CHAT_ID_" && ! -n "$_TOKEN_TELEGRAM_" ]]; then
        printf_ "ERROR" "Token Telegram nor Chat Id Not Set"
        exit 1
    fi

    _NOTIF_BUFFER_=$(echo -e $_NOTIF_BUFFER_ | sed 's/+/ /g')
    for _arr_notif_ in $_NOTIF_BUFFER_; do
        _status_=$(curl -s -X POST \
        https://api.telegram.org/bot$_TOKEN_TELEGRAM_/sendMessage \
        -d chat_id=$_CHAT_ID_ \
        -d text="#service <b>[ $_arr_notif_ ] FAILED on $(hostname)</b>" \
        -d parse_mode=html \
        -d disable_web_page_preview=true \
        2> /dev/null | jq '. | .ok')

        if [[ $? -eq 0 && ${PIPESTATUS[0]} -eq 0 && $_status_ == 'true' ]]; then
            printf_ "Notif $_arr_notif_" "${Light_Green}SUCCESS${NoColor}"
            logger "NOTIF" "Notif $_arr_notif_ Successfully Sent"
        else
            printf_ "Notif $_arr_notif_" "${Light_Red}FAILED${NoColor}"
            logger "NOTIF" "Notif $_arr_notif_ Failed to Send"
        fi
    done
}



function main() {
    clear
    printf_ "SYSTEMD SERVICE AUTOMATE CHECKER" title
    check_program

    if [[ "$EUID" -ne 0 ]]
        then 
            printf_ "ERROR | PLEASE RUN AS ROOT" header
            exit 1
    fi

    check_inactive_services
    if [[ $_SERVICE_BUFFER_ == "" ]]; then 
            exit 0
    fi

    restart_services
    if [[ $_NOTIF_BUFFER_ == "" ]]; then 
            exit 0
    fi

    notif_telegram

}; main