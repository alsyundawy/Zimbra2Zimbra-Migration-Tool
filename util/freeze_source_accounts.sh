#!/usr/bin/env bash
################################################################################
# Z2Z - Source Account Maintenance & Freeze Utility
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
#
# Description:
#   Sets source Zimbra user accounts to 'maintenance' mode during migration
#   cutover windows to prevent users from logging in or receiving new mail
#   on the legacy server while DNS MX propagation is completing.
#   Supports '--unfreeze' to restore accounts back to 'active' mode.
#
# Usage:
#   bash util/freeze_source_accounts.sh [--freeze | --unfreeze] [domain]
#   Example:
#   bash util/freeze_source_accounts.sh --freeze example.com
#
# Version: 1.0.6
# License: CC BY-NC-SA / GPL
################################################################################

set -Eeuo pipefail

export LC_ALL='en_US.UTF-8'

# ============================================================================
# PATH setup
# ============================================================================

for _p in /opt/zimbra/bin /opt/zimbra/common/bin /opt/zimbra/common/sbin \
	/opt/zimbra/openldap/bin /opt/zimbra/postfix/sbin /opt/zimbra/mysql/bin; do
	if [[ -d "${_p}" ]] && [[ ":${PATH}:" != *":${_p}:"* ]]; then
		PATH="${_p}:${PATH}"
	fi
done
export PATH

# ============================================================================
# Color output helpers
# ============================================================================

readonly COLOR_BLUE='\e[1;34m'
readonly COLOR_RED='\e[1;31m'
readonly COLOR_YELLOW='\e[1;33m'
readonly COLOR_GREEN='\e[1;32m'
readonly COLOR_CYAN='\e[1;36m'
readonly COLOR_RESET='\e[0m'

print_header() { printf "%b%s%b\n" "${COLOR_CYAN}"   "$*" "${COLOR_RESET}"; }
print_normal() { printf "%b%s%b\n" "${COLOR_BLUE}"   "$*" "${COLOR_RESET}"; }
print_error()  { printf "%b%s%b\n" "${COLOR_RED}"    "$*" "${COLOR_RESET}" >&2; }
print_info()   { printf "%b%s%b\n" "${COLOR_YELLOW}" "$*" "${COLOR_RESET}"; }
print_ok()     { printf "%b%s%b\n" "${COLOR_GREEN}"  "$*" "${COLOR_RESET}"; }

separator() { echo "+++++++++++++++++++++++++++++++++++++++++++++++++"; }

current_user="$(whoami 2>/dev/null || id -un)"
if [[ "${current_user}" != "zimbra" ]]; then
	print_error "ERROR: Must be run as the zimbra user."
	exit 1
fi

ACTION="${1:---freeze}"
TARGET_DOMAIN="${2:-}"

TARGET_STATUS="maintenance"
if [[ "${ACTION}" == "--unfreeze" || "${ACTION}" == "-u" ]]; then
	TARGET_STATUS="active"
fi

print_header "Z2Z — Source Account Status Manager (${TARGET_STATUS^^})"
separator

if [[ -n "${TARGET_DOMAIN}" ]]; then
	print_info "Scope: Domain '${TARGET_DOMAIN}'"
	ACCOUNT_LIST="$(zmprov -l gaa "${TARGET_DOMAIN}" 2>/dev/null || true)"
else
	print_info "Scope: All domains"
	ACCOUNT_LIST="$(zmprov -l gaa 2>/dev/null || true)"
fi

ACCOUNT_LIST="$(
	echo "${ACCOUNT_LIST}" |
		grep -v -E '^(virus-[^@]*|ham\.[^@]*|spam\.[^@]*|galsync[^@]*)@' ||
		true
)"

TOTAL=$(echo "${ACCOUNT_LIST}" | grep -c -v '^$' || echo 0)
print_info "Accounts to update : ${TOTAL}"
separator

COUNT=0
SUCCESS=0
FAILED=0

while IFS= read -r ACCT; do
	[[ -z "${ACCT}" ]] && continue
	((COUNT++)) || true

	if zmprov ma "${ACCT}" zimbraAccountStatus "${TARGET_STATUS}" 2>/dev/null; then
		print_ok "  [${COUNT}/${TOTAL}] ${ACCT} -> ${TARGET_STATUS}"
		((SUCCESS++)) || true
	else
		print_error "  [${COUNT}/${TOTAL}] FAILED: ${ACCT}"
		((FAILED++)) || true
	fi
done <<< "${ACCOUNT_LIST}"

separator
print_header "Status Update Summary"
print_ok    "  Updated : ${SUCCESS}"
print_error "  Failed  : ${FAILED}"
separator
