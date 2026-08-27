#!/usr/bin/env bash
################################################################################
# Z2Z - Incremental Delta Mailbox Synchronization Utility
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
#
# Description:
#   Synchronizes only new incoming emails received after a specified cutover date
#   using Zimbra REST query filtering (after:MM/DD/YYYY or after:YYYY/MM/DD).
#   Generates delta TGZ archives and a companion import script for zero-downtime
#   cutover windows.
#
# Usage:
#   bash util/sync_delta_mailbox.sh <YYYY/MM/DD|MM/DD/YYYY> [output_dir]
#   Example:
#   bash util/sync_delta_mailbox.sh 2026/08/20 ./export/delta
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

separator()      { echo "+++++++++++++++++++++++++++++++++++++++++++++++++"; }
separator_thin() { echo "-------------------------------------------------"; }

# ============================================================================
# Pre-flight checks
# ============================================================================

current_user="$(whoami 2>/dev/null || id -un)"
if [[ "${current_user}" != "zimbra" ]]; then
	print_error "ERROR: Must be run as the zimbra user."
	exit 1
fi

if [[ $# -lt 1 ]]; then
	print_error "Usage: $0 <DATE_FILTER (YYYY/MM/DD or MM/DD/YYYY)> [OUTPUT_DIR]"
	print_info "Example: $0 2026/08/25 ./export/delta"
	exit 1
fi

DATE_QUERY="$1"
OUTPUT_BASE="${2:-./export/delta}"

if [[ -f /opt/zimbra/bin/zmshutil ]]; then
	# shellcheck source=/dev/null
	source /opt/zimbra/bin/zmshutil
	zmsetvars
elif [[ -f ~/bin/zmshutil ]]; then
	# shellcheck source=/dev/null
	source ~/bin/zmshutil
	zmsetvars
fi

mkdir -p "${OUTPUT_BASE}"

SESSION_TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
SESSION_LOG="${OUTPUT_BASE}/sync_delta_${SESSION_TIMESTAMP}.log"

print_header "Z2Z — Incremental Delta Mailbox Sync"
separator
print_info "Cutoff date filter : after:\"${DATE_QUERY}\""
print_info "Output directory   : ${OUTPUT_BASE}"
print_info "Session log        : ${SESSION_LOG}"
separator

# ============================================================================
# Account Discovery
# ============================================================================

print_info "Discovering accounts..."
ACCOUNT_LIST="$(
	zmprov -l gaa 2>/dev/null |
		grep -v -E '^(virus-[^@]*|ham\.[^@]*|spam\.[^@]*|galsync[^@]*)@' ||
		true
)"

TOTAL=$(echo "${ACCOUNT_LIST}" | grep -c -v '^$' || echo 0)
print_info "Accounts found     : ${TOTAL}"
separator

# ============================================================================
# Delta Export Loop & Batch Script Generation
# ============================================================================

IMPORT_SCRIPT="${OUTPUT_BASE}/import_delta_mailboxes.sh"
cat <<'SCRIPT_EOF' >"${IMPORT_SCRIPT}"
#!/usr/bin/env bash
################################################################################
# Z2Z Incremental Delta Mailbox Import Script
################################################################################
set -euo pipefail

log_msg() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_msg "Starting Incremental Delta Mailbox Import..."
SCRIPT_EOF

SUCCESS=0
FAILED=0
COUNT=0

while IFS= read -r ACCT; do
	[[ -z "${ACCT}" ]] && continue
	((COUNT++)) || true

	DELTA_FILE="${OUTPUT_BASE}/${ACCT}_delta.tgz"
	print_normal "[${COUNT}/${TOTAL}] Exporting delta for: ${ACCT}"

	# Export delta messages matching query
	if zmmailbox -z -m "${ACCT}" -t 0 getRestURL "//?fmt=tgz&query=after:\"${DATE_QUERY}\"" > "${DELTA_FILE}" 2>>"${SESSION_LOG}"; then
		if [[ -s "${DELTA_FILE}" ]]; then
			print_ok "  Delta archive created (${DELTA_FILE})"
			((SUCCESS++)) || true
			delta_size="$(wc -c <"${DELTA_FILE}" || echo 0)"
			echo "[OK] ${ACCT} — delta size ${delta_size} bytes" >> "${SESSION_LOG}"

			cat <<CMDEOF >>"${IMPORT_SCRIPT}"
log_msg "Importing delta for ${ACCT}..."
if [[ -f '${DELTA_FILE}' ]]; then
	zmmailbox -z -m '${ACCT}' -t 0 postRestURL "//?fmt=tgz&resolve=skip" '${DELTA_FILE}' || log_msg "ERROR: Failed delta import for ${ACCT}"
fi
CMDEOF
		else
			rm -f "${DELTA_FILE}"
			print_info "  No new messages since ${DATE_QUERY} (empty delta)"
			((SUCCESS++)) || true
		fi
	else
		print_error "  ERROR: Failed delta export for ${ACCT}"
		((FAILED++)) || true
		echo "[ERROR] ${ACCT} — export failed" >> "${SESSION_LOG}"
	fi

done <<< "${ACCOUNT_LIST}"

chmod +x "${IMPORT_SCRIPT}"

separator
print_header "Delta Export Summary"
print_ok    "  Successful : ${SUCCESS}"
print_error "  Failed     : ${FAILED}"
print_info  "  Import script ready : ${IMPORT_SCRIPT}"
separator
