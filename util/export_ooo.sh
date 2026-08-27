#!/usr/bin/env bash
################################################################################
# Z2Z - Export Out-of-Office / Vacation Auto-Reply Settings
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
#
# Description:
#   Exports Out-of-Office (OOO) configuration for every non-system account.
#   Captures the following LDAP attributes per account:
#     - zimbraPrefOutOfOfficeReplyEnabled  (TRUE / FALSE)
#     - zimbraPrefOutOfOfficeReply         (message body, plain-text)
#     - zimbraPrefOutOfOfficeFromDate      (YYYYMMDDHHMMSSZ)
#     - zimbraPrefOutOfOfficeUntilDate     (YYYYMMDDHHMMSSZ)
#   Saves each account's settings as a key=value flat file in export/ooo/.
#
#   Compatible with ZCS 7.x through 10.1 and Carbonio CE.
#   Run as the zimbra user on the SOURCE server.
#
# Usage:
#   bash util/export_ooo.sh [output_dir]
#   Default output_dir: ./export/ooo
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

readonly COLOR_BLUE='\e[1;34m'
readonly COLOR_RED='\e[1;31m'
readonly COLOR_YELLOW='\e[1;33m'
readonly COLOR_GREEN='\e[1;32m'
readonly COLOR_RESET='\e[0m'

print_normal() { printf "%b%s%b\n" "${COLOR_BLUE}"   "$*" "${COLOR_RESET}"; }
print_error()  { printf "%b%s%b\n" "${COLOR_RED}"    "$*" "${COLOR_RESET}" >&2; }
print_info()   { printf "%b%s%b\n" "${COLOR_YELLOW}" "$*" "${COLOR_RESET}"; }
print_ok()     { printf "%b%s%b\n" "${COLOR_GREEN}"  "$*" "${COLOR_RESET}"; }

separator() { echo "+++++++++++++++++++++++++++++++++++++++++++++++++"; }

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
OUTPUT_BASE="${1:-${SCRIPT_DIR}/../export/ooo}"
OUTPUT_BASE="$(realpath -m "${OUTPUT_BASE}")"

mkdir -p "${OUTPUT_BASE}" || {
	print_error "ERROR: Cannot create output directory: ${OUTPUT_BASE}"
	exit 1
}

SESSION_TS="$(date +'%d_%b_%Y-%H-%M')"
SESSION_LOG="${OUTPUT_BASE}/export_ooo-${SESSION_TS}.log"

print_normal "Z2Z — Export Out-of-Office / Vacation Settings"
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
# Helper: extract a single attribute value from zmprov ga output
# ============================================================================

extract_attr() {
	local attr="$1"
	local raw="$2"
	echo "${raw}" | grep "^${attr}:" | head -n 1 | sed "s/^${attr}: //"
}

# ============================================================================
# Main export loop
# ============================================================================

while IFS= read -r ACCT; do
	[[ -z "${ACCT}" ]] && continue
	((COUNT++)) || true

	print_normal "[${COUNT}/${TOTAL}] ${ACCT}"

	# Fetch all OOO-related attributes in one query.
	RAW_OOO="$(
		zmprov ga "${ACCT}" \
			zimbraPrefOutOfOfficeReplyEnabled \
			zimbraPrefOutOfOfficeReply \
			zimbraPrefOutOfOfficeFromDate \
			zimbraPrefOutOfOfficeUntilDate \
			2>>"${SESSION_LOG}" || true
	)"

	OOO_ENABLED="$(extract_attr 'zimbraPrefOutOfOfficeReplyEnabled' "${RAW_OOO}")"
	OOO_REPLY="$(extract_attr 'zimbraPrefOutOfOfficeReply' "${RAW_OOO}")"
	OOO_FROM="$(extract_attr 'zimbraPrefOutOfOfficeFromDate' "${RAW_OOO}")"
	OOO_UNTIL="$(extract_attr 'zimbraPrefOutOfOfficeUntilDate' "${RAW_OOO}")"

	# Skip accounts where OOO is disabled and no message is configured.
	if [[ "${OOO_ENABLED}" != "TRUE" ]] && [[ -z "${OOO_REPLY}" ]]; then
		print_info "  OOO not configured — skipping."
		((SKIPPED++)) || true
		echo "[SKIP] ${ACCT} — OOO disabled/empty" >> "${SESSION_LOG}"
		continue
	fi

	OUT_FILE="${OUTPUT_BASE}/${ACCT}.ooo"
	cat > "${OUT_FILE}" << EOF
zimbraPrefOutOfOfficeReplyEnabled=${OOO_ENABLED}
zimbraPrefOutOfOfficeFromDate=${OOO_FROM}
zimbraPrefOutOfOfficeUntilDate=${OOO_UNTIL}
zimbraPrefOutOfOfficeReply=${OOO_REPLY}
EOF

	print_ok "  OOO settings saved : ${OUT_FILE}"
	echo "[OK] ${ACCT} — enabled=${OOO_ENABLED}" >> "${SESSION_LOG}"
	((SUCCESS++)) || true

done <<< "${ACCOUNT_LIST}"

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
