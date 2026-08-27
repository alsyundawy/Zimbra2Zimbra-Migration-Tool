#!/usr/bin/env bash
################################################################################
# Z2Z - Import User Sieve Mail Filter Rules
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
#
# Description:
#   Reads the .sieve files produced by export_sieve_filters.sh and applies
#   each Sieve script to the matching account on the DESTINATION server via
#   zmprov ma zimbraMailSieveScript. Validates the target account exists
#   before applying. Logs successes and failures with counters.
#
#   IMPORTANT: Ensure destination mailbox folders referenced by Sieve rules
#   (e.g., "fileinto" targets) exist before importing. Create missing folders
#   with: zmmailbox -z -m user@domain.com cf "FolderName"
#
#   Compatible with ZCS 7.x through 10.1 and Carbonio CE.
#   Run as the zimbra user on the DESTINATION server.
#
# Usage:
#   bash util/import_sieve_filters.sh [input_dir]
#   Default input_dir: ./export/sieve
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

readonly COLOR_BLUE='\\e[1;34m'
readonly COLOR_RED='\\e[1;31m'
readonly COLOR_YELLOW='\\e[1;33m'
readonly COLOR_GREEN='\\e[1;32m'
readonly COLOR_RESET='\\e[0m'

print_normal() { printf "%b%s%b\n" "${COLOR_BLUE}"   "$*" "${COLOR_RESET}"; }
print_error()  { printf "%b%s%b\n" "${COLOR_RED}"    "$*" "${COLOR_RESET}" >&2; }
print_info()   { printf "%b%s%b\n" "${COLOR_YELLOW}" "$*" "${COLOR_RESET}"; }
print_ok()     { printf "%b%s%b\n" "${COLOR_GREEN}"  "$*" "${COLOR_RESET}"; }

separator() { echo "++++++++++++++++++++++++++++++++++++++++++++++++++"; }

# ============================================================================
# Pre-flight
# ============================================================================

current_user="$(whoami 2>/dev/null || id -un)"
if [[ "${current_user}" != "zimbra" ]]; then
	print_error "ERROR: Must be run as the zimbra user."
	exit 1
fi

if [[ -f /opt/zimbra/bin/zmshutil ]]; then
	# shellcheck source=/dev/null
	source /opt/zimbra/bin/zmshutil
	zmsetvars
elif [[ -f ~/bin/zmshutil ]]; then
	# shellcheck source=/dev/null
	source ~/bin/zmshutil
	zmsetvars
else
	print_error "ERROR: Cannot source Zimbra environment (zmshutil not found)."
	exit 1
fi

# ============================================================================
# Argument & directory setup
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_BASE="${1:-${SCRIPT_DIR}/../export/sieve}"
INPUT_BASE="$(realpath -m "${INPUT_BASE}")"

if [[ ! -d "${INPUT_BASE}" ]]; then
	print_error "ERROR: Input directory not found: ${INPUT_BASE}"
	print_error "       Run export_sieve_filters.sh on the source server first."
	exit 1
fi

SESSION_TS="$(date +'%d_%b_%Y-%H-%M')"
SESSION_LOG="${INPUT_BASE}/import_sieve-${SESSION_TS}.log"

print_normal "Z2Z — Import Sieve Mail Filter Rules"
separator
print_info "Input directory : ${INPUT_BASE}"
print_info "Session log     : ${SESSION_LOG}"
separator

SUCCESS=0
SKIPPED=0
FAILED=0
COUNT=0

# ============================================================================
# Main import loop
# ============================================================================

for SIEVE_FILE in "${INPUT_BASE}"/*.sieve; do
	[[ -f "${SIEVE_FILE}" ]] || continue

	ACCT="$(basename "${SIEVE_FILE}" .sieve)"
	((COUNT++)) || true

	print_normal "[${COUNT}] ${ACCT}"

	# Verify account exists on this server.
	if ! zmprov ga "${ACCT}" zimbraId &>/dev/null; then
		print_error "  WARN: Account '${ACCT}' not found — skipping."
		((SKIPPED++)) || true
		echo "[SKIP] ${ACCT} — account not found" >>"${SESSION_LOG}"
		continue
	fi

	SIEVE_CONTENT="$(cat "${SIEVE_FILE}")"

	if [[ -z "${SIEVE_CONTENT}" ]]; then
		print_info "  Empty Sieve file — skipping."
		((SKIPPED++)) || true
		echo "[SKIP] ${ACCT} — empty sieve file" >>"${SESSION_LOG}"
		continue
	fi

	# Apply Sieve script via zmprov ma.
	if zmprov ma "${ACCT}" zimbraMailSieveScript "${SIEVE_CONTENT}" \
		>>"${SESSION_LOG}" 2>&1; then
		print_ok "  Sieve rules applied."
		((SUCCESS++)) || true
		echo "[OK] ${ACCT}" >>"${SESSION_LOG}"
	else
		print_error "  ERROR: Failed to apply Sieve rules for ${ACCT}"
		((FAILED++)) || true
		echo "[FAIL] ${ACCT}" >>"${SESSION_LOG}"
	fi

done

# ============================================================================
# Summary
# ============================================================================

separator
print_normal "Import complete."
print_info  "Accounts processed : ${COUNT}"
print_ok    "Success            : ${SUCCESS}"
print_info  "Skipped            : ${SKIPPED}"
print_error "Failed             : ${FAILED}"
separator
print_info  "Session log : ${SESSION_LOG}"
