#!/usr/bin/env bash
################################################################################
# Z2Z - Generic IMAP to Zimbra Migration Wrapper (imapsync)
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
#
# Description:
#   Orchestrates batch mailbox migration from generic IMAP servers (cPanel,
#   Exchange, Postfix/Dovecot, Gmail/Google Workspace) into Zimbra using imapsync.
#   Reads account mapping from a CSV file: source_user,source_pass,dest_user,dest_pass
#
# Usage:
#   bash util/imapsync_wrapper.sh <source_imap_host> <dest_imap_host> <accounts.csv>
#
# Version: 1.0.6
# License: CC BY-NC-SA / GPL
################################################################################

set -Eeuo pipefail

export LC_ALL='en_US.UTF-8'

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

if ! type imapsync &>/dev/null; then
	print_error "ERROR: 'imapsync' command not found. Please install imapsync first."
	exit 1
fi

if [[ $# -lt 3 ]]; then
	print_error "Usage: $0 <SOURCE_IMAP_HOST> <DEST_IMAP_HOST> <ACCOUNTS_CSV>"
	print_info "CSV Format: source_user,source_password,dest_user,dest_password"
	exit 1
fi

SOURCE_HOST="$1"
DEST_HOST="$2"
CSV_FILE="$3"

if [[ ! -r "${CSV_FILE}" ]]; then
	print_error "ERROR: CSV file '${CSV_FILE}' not found or not readable."
	exit 1
fi

print_header "Z2Z — IMAP to Zimbra Batch Synchronization"
separator
print_info "Source Host : ${SOURCE_HOST}"
print_info "Dest Host   : ${DEST_HOST}"
print_info "Mapping File: ${CSV_FILE}"
separator

COUNT=0
SUCCESS=0
FAILED=0

while IFS=',' read -r SRC_USER SRC_PASS DST_USER DST_PASS; do
	[[ -z "${SRC_USER}" || "${SRC_USER}" =~ ^# ]] && continue
	((COUNT++)) || true

	print_normal "[${COUNT}] Migrating: ${SRC_USER} -> ${DST_USER}..."

	# Run imapsync with safe parameters for Zimbra target
	if imapsync \
		--host1 "${SOURCE_HOST}" --user1 "${SRC_USER}" --pass1 "${SRC_PASS}" \
		--host2 "${DEST_HOST}"   --user2 "${DST_USER}" --pass2 "${DST_PASS}" \
		--ssl1 --ssl2 \
		--noauthmd5 --nosyncacls --regexmess 's/(\r\n|\n\r)/\n/g' \
		--subfolder1 "" --subfolder2 "" \
		--quiet &>/dev/null; then
		print_ok "  [OK] Migrated ${DST_USER}"
		((SUCCESS++)) || true
	else
		print_error "  [ERROR] Sync failed for ${DST_USER}"
		((FAILED++)) || true
	fi

done < "${CSV_FILE}"

separator
print_header "IMAP Migration Summary"
print_ok    "  Completed : ${SUCCESS}"
print_error "  Failed    : ${FAILED}"
separator
