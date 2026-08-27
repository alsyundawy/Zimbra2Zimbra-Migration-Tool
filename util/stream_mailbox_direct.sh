#!/usr/bin/env bash
################################################################################
# Z2Z - Direct Remote SSH Mailbox Streaming Pipeline
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
#
# Description:
#   Streams mailbox TGZ archives directly from the source server over an SSH
#   tunnel into the target Zimbra server's REST API without requiring local
#   disk staging. Eliminates 50% of storage and disk I/O requirements.
#
# Usage:
#   bash util/stream_mailbox_direct.sh <target_ssh_host> [account@domain.com]
#   Example:
#   bash util/stream_mailbox_direct.sh zimbra@mail-new.example.com user@example.com
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

if [[ $# -lt 1 ]]; then
	print_error "Usage: $0 <TARGET_SSH_HOST> [OPTIONAL_SINGLE_ACCOUNT]"
	print_info "Example: $0 zimbra@192.168.1.100 user@example.com"
	exit 1
fi

TARGET_HOST="$1"
SPECIFIC_ACCOUNT="${2:-}"

print_header "Z2Z — Direct Remote SSH Mailbox Streaming"
separator
print_info "Target SSH Host : ${TARGET_HOST}"

if [[ -n "${SPECIFIC_ACCOUNT}" ]]; then
	ACCOUNT_LIST="${SPECIFIC_ACCOUNT}"
else
	print_info "Discovering accounts on source server..."
	ACCOUNT_LIST="$(
		zmprov -l gaa 2>/dev/null |
			grep -v -E '^(virus-[^@]*|ham\.[^@]*|spam\.[^@]*|galsync[^@]*)@' ||
			true
	)"
fi

TOTAL=$(echo "${ACCOUNT_LIST}" | grep -c -v '^$' || echo 0)
print_info "Accounts to stream : ${TOTAL}"
separator

COUNT=0
SUCCESS=0
FAILED=0

while IFS= read -r ACCT; do
	[[ -z "${ACCT}" ]] && continue
	((COUNT++)) || true

	print_normal "[${COUNT}/${TOTAL}] Streaming: ${ACCT} -> ${TARGET_HOST}..."

	# Pipe local getRestURL directly into remote postRestURL over SSH
	if zmmailbox -z -m "${ACCT}" -t 0 getRestURL "//?fmt=tgz" | \
		ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${TARGET_HOST}" \
		"/opt/zimbra/bin/zmmailbox -z -m '${ACCT}' -t 0 postRestURL '//?fmt=tgz&resolve=skip' -"; then
		print_ok "  [OK] Successfully streamed ${ACCT}"
		((SUCCESS++)) || true
	else
		print_error "  [ERROR] Stream failed for ${ACCT}"
		((FAILED++)) || true
	fi

done <<< "${ACCOUNT_LIST}"

separator
print_header "Streaming Summary"
print_ok    "  Streamed : ${SUCCESS}"
print_error "  Failed   : ${FAILED}"
separator
