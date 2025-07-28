#!/usr/bin/env bash

RED="\033[0;31m"
GRN="\033[0;32m"
YLW="\033[1;33m"
RST="\033[0m"

msg()  { echo -e "\n             $*"; }
ok()   { echo -e   "[ ${GRN}   OK   ${RST} ] $*"; }
err()  { echo -e   "[ ${RED} FAILED ${RST} ] $*"; }
warn() { echo -e   "[ ${YLW}  WARN  ${RST} ] $*"; }

# Stores command output
TMP_OUTPUT=$(mktemp)

cleanup() {
    rm -f "$TMP_OUTPUT"
}
trap cleanup EXIT

# run_cmd <description> <command>
run_cmd() {
    local desc="$1"
    shift

    if "$@" >"$TMP_OUTPUT" 2>&1; then
        ok "$desc"
    else
        err "$desc"
        echo -e "\n${RED}>>> Command Failed >>>${RST}" >&2
        echo -e "${YLW}Command:${RST} $*" >&2
        echo -e "${YLW}Location:${RST} ${BASH_SOURCE[1]}: line ${BASH_LINENO[0]}" >&2
        echo -e "${RED}>>> Output Start >>>${RST}" >&2
        cat "$TMP_OUTPUT" >&2
        echo -e "${RED}<<< Output End <<<${RST}\n" >&2
        exit 1
    fi
}

get_cmd_output() {
    cat "$TMP_OUTPUT"
}

# check_vars_set <var1> <var2> ... 
check_vars_set() {
    for var in "$@"; do
        if [[ -z "${!var-}" ]]; then
            echo "Error: $var is not set. Aborting." >&2
            exit 1
        fi
    done
}
