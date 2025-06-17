#!/bin/bash

export readonly RED='\033[31m'
export readonly GREEN='\033[32m'
export readonly YELLOW='\033[33m'
export readonly BLUE='\033[34m'
export readonly RESET='\033[0m'
export readonly BAK_ROOT="/usr/local/bin/bak"

log_info() {
    echo -e "${BLUE}==>${RESET} $1"
}

log_success() {
    echo -e "${GREEN} ✔ ${RESET} $1"
}

log_warn() {
    echo -e "${YELLOW} ! ${RESET} $1"
}

log_error() {
    echo -e "${RED} ✖ ${RESET} $1"
}

export -f log_info log_success log_warn log_error