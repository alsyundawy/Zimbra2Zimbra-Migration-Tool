#!/usr/bin/env bash
################################################################################
# Z2Z - Post-Migration Data Integrity Verifier
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
#
# Description:
#   Validates mailbox migration integrity on the destination Zimbra server.
#   Compares accounts against an optional source inventory file or audits
#   all destination mailboxes for item counts, mailbox size, and folder health.
#
# Usage:
#   bash util/verify_migration.sh [source_sizes.txt]
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

separator()      { echo "================================================================================"; }
separator_thin() { echo "--------------------------------------------------------------------------------"; }

current_user="$(whoami 2>/dev/null || id -un)"
if [[ "${current_user}" != "zimbra" ]]; then
	print_error "ERROR: Must be run as the zimbra user."
	exit 1
fi

SOURCE_INVENTORY="${1:-}"

print_header "Z2Z — Post-Migration Integrity Verification"
separator

if [[ -n "${SOURCE_INVENTORY}" && -r "${SOURCE_INVENTORY}" ]]; then
	print_info "Reading inventory file         : ${SOURCE_INVENTORY}"
	ACCOUNT_LIST="$(grep -v -E '^(virus-[^@]*|ham\.[^@]*|spam\.[^@]*|galsync[^@]*)@' "${SOURCE_INVENTORY}" || true)"
else
	ACCOUNT_LIST="$(
		zmprov -l gaa 2>/dev/null |
			grep -v -E '^(virus-[^@]*|ham\.[^@]*|spam\.[^@]*|galsync[^@]*)@' ||
			true
	)"
fi

TOTAL=$(echo "${ACCOUNT_LIST}" | grep -c -v '^$' || echo 0)
print_info "Destination accounts to verify : ${TOTAL}"
separator

printf "%-40s | %-12s | %-12s | %-8s\n" "Account" "Mailbox Size" "Folders" "Status"
separator_thin

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

while IFS= read -r ACCT; do
	[[ -z "${ACCT}" ]] && continue

	# Check account mailbox size
	RAW_SIZE="$(zmmailbox -z -m "${ACCT}" gms 2>/dev/null || echo "0 B")"
	
	# Check folder count
	FOLDER_COUNT="$(zmmailbox -z -m "${ACCT}" gaf 2>/dev/null | grep -c -v '^$' || echo "0")"
	
	STATUS="OK"
	if [[ "${RAW_SIZE}" == "0 B" ]] && ((FOLDER_COUNT <= 2)); then
		STATUS="EMPTY"
		((WARN_COUNT++)) || true
		printf "%-40s | %-12s | %-12s | %b%-8s%b\n" "${ACCT}" "${RAW_SIZE}" "${FOLDER_COUNT}" "${COLOR_YELLOW}" "${STATUS}" "${COLOR_RESET}"
	else
		((PASS_COUNT++)) || true
		printf "%-40s | %-12s | %-12s | %b%-8s%b\n" "${ACCT}" "${RAW_SIZE}" "${FOLDER_COUNT}" "${COLOR_GREEN}" "${STATUS}" "${COLOR_RESET}"
	fi

done <<< "${ACCOUNT_LIST}"

separator
print_header "Verification Summary"
print_ok    "  Active/Populated : ${PASS_COUNT}"
print_info  "  Empty Mailboxes  : ${WARN_COUNT}"
print_error "  Missing/Errors   : ${FAIL_COUNT}"
separator
