#!/usr/bin/env bash

RED="\033[0;31m"
GRN="\033[0;32m"
YLW="\033[1;33m"
RST="\033[0m"

msg()  { echo -e "\n[ ${RST}        ${RST} ] $*"; }
ok()   { echo -e   "[ ${GRN}   OK   ${RST} ] $*"; }
err()  { echo -e   "[ ${RED} FAILED ${RST} ] $*"; exit 1; }
warn() { echo -e   "[ ${YLW} WARNING ${RST} ] $*"; }

