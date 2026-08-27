#!/usr/bin/env bash
################################################################################
# Z2Z - Export User Sieve Mail Filter Rules
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
#
# Description:
#   Exports the Sieve mail filter script (zimbraMailSieveScript) for every
#   non-system account into individual files under export/sieve/. Uses a
#   temp-file approach to safely capture multi-line Sieve scripts without
#   shell-quoting corruption.
#
#   Compatible with ZCS 7.x through 10.1 and Carbonio CE.
#   Run as the zimbra user on the SOURCE server.
#
# Usage:
#   bash util/export_sieve_filters.sh [output_dir]
#   Default output_dir: ./export/sieve
#
# Version: 1.0.5
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
# Global temp-file cleanup
# BUG FIX: previous version set and cleared trap inside the loop, causing
#   (a) only the last iteration's temp file to be cleaned on abnormal exit,
#   (b) no cleanup at all after each loop's 'trap - EXIT'.
# New pattern: single global variable + cleanup function registered once.
# ============================================================================

TMP_RAW=""

_cleanup_sieve_export() {
	[[ -n "${TMP_RAW}" ]] && rm -f "${TMP_RAW}" 2>/dev/null || true
}
trap _cleanup_sieve_export EXIT

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
# Argument & output directory setup
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_BASE="${1:-${SCRIPT_DIR}/../export/sieve}"
OUTPUT_BASE="$(realpath -m "${OUTPUT_BASE}")"

mkdir -p "${OUTPUT_BASE}" || {
	print_error "ERROR: Cannot create output directory: ${OUTPUT_BASE}"
	exit 1
}

SESSION_TS="$(date +'%d_%b_%Y-%H-%M')"
SESSION_LOG="${OUTPUT_BASE}/export_sieve-${SESSION_TS}.log"

print_normal "Z2Z — Export Sieve Mail Filter Rules"
separator
print_info "Output directory : ${OUTPUT_BASE}"
print_info "Session log      : ${SESSION_LOG}"
separator

# ============================================================================
# Discover accounts
# ============================================================================

print_info "Discovering accounts..."
ACCOUNT_LIST="$(
	zmprov -l gaa 2>/dev/null |
		grep -v -E '^(virus-[^@]*|ham\.[^@]*|spam\.[^@]*|galsync[^@]*)@' ||
		true
)"

TOTAL=$(echo "${ACCOUNT_LIST}" | grep -c -v '^$' || echo 0)
print_info "Accounts found : ${TOTAL}"
separator

SUCCESS=0
SKIPPED=0
FAILED=0
COUNT=0

# ============================================================================
# Main export loop
# ============================================================================

while IFS= read -r ACCT; do
	[[ -z "${ACCT}" ]] && continue
	((COUNT++)) || true

	print_normal "[${COUNT}/${TOTAL}] ${ACCT}"

	# Create temp file for this iteration; update global for cleanup trap
	TMP_RAW="$(mktemp)"

	zmprov ga "${ACCT}" zimbraMailSieveScript >"${TMP_RAW}" 2>>"${SESSION_LOG}" || true

	# Extract only lines containing the attribute value, strip the prefix.
	# Multi-line Sieve scripts are encoded by zmprov with continuation lines
	# starting with a space (LDAP ldif-style). We strip the prefix carefully.
	SIEVE_CONTENT=""
	if grep -q 'zimbraMailSieveScript:' "${TMP_RAW}" 2>/dev/null; then
		# Remove attribute header; handle both single-line and multi-line output.
		SIEVE_CONTENT="$(
			sed -n '/^zimbraMailSieveScript:/,/^[^ ]/p' "${TMP_RAW}" |
			sed '1s/^zimbraMailSieveScript: //' |
			sed '$ {/^[^ ]/d}' |
			sed 's/^ //'
		)"
	fi

	# Discard temp file immediately after use; clear global so trap is a no-op
	rm -f "${TMP_RAW}"
	TMP_RAW=""

	if [[ -z "${SIEVE_CONTENT}" ]]; then
		print_info "  No Sieve rules — skipping."
		((SKIPPED++)) || true
		echo "[SKIP] ${ACCT} — no zimbraMailSieveScript" >>"${SESSION_LOG}"
		continue
	fi

	OUT_FILE="${OUTPUT_BASE}/${ACCT}.sieve"
	printf '%s\n' "${SIEVE_CONTENT}" >"${OUT_FILE}"
	print_ok "  Sieve rules saved : ${OUT_FILE}"
	echo "[OK] ${ACCT}" >>"${SESSION_LOG}"
	((SUCCESS++)) || true

done <<<"${ACCOUNT_LIST}"

# ============================================================================
# Summary
# ============================================================================

separator
print_normal "Export complete."
print_info  "Total   : ${TOTAL}"
print_ok    "Saved   : ${SUCCESS}"
print_info  "Skipped : ${SKIPPED}"
print_error "Failed  : ${FAILED}"
separator
print_info  "Staged output : ${OUTPUT_BASE}"
print_info  "Session log   : ${SESSION_LOG}"
