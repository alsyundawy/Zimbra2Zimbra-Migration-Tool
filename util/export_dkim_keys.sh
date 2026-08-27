#!/usr/bin/env bash
################################################################################
# Z2Z - DKIM Key Snapshot Utility
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
#
# Description:
#   Snapshots the DKIM selector and public key for every active domain on the
#   SOURCE server using zmdkimkeyutil. Output is saved to export/dkim/ as one
#   file per domain. The primary use case is documentation and reference:
#   the file can be used to update DNS records on the destination or to
#   manually transplant keys if the same selector must be preserved.
#
#   SECURITY NOTE: This utility exports PUBLIC key information only. Private
#   DKIM keys are stored in Zimbra LDAP and are NOT extracted here. The
#   industry best practice is to generate fresh DKIM keys on the destination
#   server with: /opt/zimbra/libexec/zmdkimkeyutil -a -d <domain>
#   Then update DNS TXT records with the new public key.
#
#   Compatible with ZCS 7.x through 10.1 and Carbonio CE.
#   Run as the zimbra user on the SOURCE server.
#
# Usage:
#   bash util/export_dkim_keys.sh [output_dir]
#   Default output_dir: ./export/dkim
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

DKIM_KEYUTIL="/opt/zimbra/libexec/zmdkimkeyutil"
if [[ ! -x "${DKIM_KEYUTIL}" ]]; then
	print_error "ERROR: zmdkimkeyutil not found at ${DKIM_KEYUTIL}"
	print_error "       DKIM key management may not be available on this Zimbra version."
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
OUTPUT_BASE="${1:-${SCRIPT_DIR}/../export/dkim}"
OUTPUT_BASE="$(realpath -m "${OUTPUT_BASE}")"

mkdir -p "${OUTPUT_BASE}" || {
	print_error "ERROR: Cannot create output directory: ${OUTPUT_BASE}"
	exit 1
}

SESSION_TS="$(date +'%d_%b_%Y-%H-%M')"
SESSION_LOG="${OUTPUT_BASE}/export_dkim-${SESSION_TS}.log"

print_normal "Z2Z — DKIM Key Snapshot Utility"
separator
print_info "Output directory : ${OUTPUT_BASE}"
print_info "Session log      : ${SESSION_LOG}"
separator

# Print security advisory.
print_info "ADVISORY: This tool snapshots DKIM selectors and DNS public keys only."
print_info "          Best practice: generate new DKIM keys on the destination server."
print_info "          Command: ${DKIM_KEYUTIL} -a -d <domain>"
print_info "          Then update your DNS TXT record with the new public key."
separator

# ============================================================================
# Discover domains
# ============================================================================

print_info "Discovering domains..."
DOMAIN_LIST="$(zmprov gad 2>/dev/null | sort || true)"

TOTAL=$(echo "${DOMAIN_LIST}" | grep -c -v '^$' || echo 0)
print_info "Domains found : ${TOTAL}"
separator

SUCCESS=0
SKIPPED=0
COUNT=0

# ============================================================================
# Main export loop
# ============================================================================

while IFS= read -r DOMAIN; do
	[[ -z "${DOMAIN}" ]] && continue
	((COUNT++)) || true

	print_normal "[${COUNT}/${TOTAL}] ${DOMAIN}"

	# Query DKIM configuration for this domain.
	DKIM_RAW="$("${DKIM_KEYUTIL}" -q -d "${DOMAIN}" 2>>"${SESSION_LOG}" || true)"

	if [[ -z "${DKIM_RAW}" ]]; then
		print_info "  No DKIM configured — skipping."
		((SKIPPED++)) || true
		echo "[SKIP] ${DOMAIN} — no DKIM" >> "${SESSION_LOG}"
		continue
	fi

	OUT_FILE="${OUTPUT_BASE}/${DOMAIN}.txt"
	SNAPSHOT_TS="$(date +'%Y-%m-%d %H:%M:%S')"
	{
		echo "# Z2Z DKIM Key Snapshot"
		echo "# Domain    : ${DOMAIN}"
		echo "# Exported  : ${SNAPSHOT_TS}"
		echo "# ADVISORY  : Regenerate keys on destination. Do NOT reuse private keys."
		echo "#             Command: ${DKIM_KEYUTIL} -a -d ${DOMAIN}"
		echo "# ============================================================"
		echo "${DKIM_RAW}"
	} > "${OUT_FILE}"

	print_ok "  DKIM snapshot saved : ${OUT_FILE}"
	echo "[OK] ${DOMAIN}" >> "${SESSION_LOG}"
	((SUCCESS++)) || true

done <<< "${DOMAIN_LIST}"

# ============================================================================
# Summary
# ============================================================================

separator
print_normal "DKIM snapshot complete."
print_info  "Total   : ${TOTAL}"
print_ok    "Saved   : ${SUCCESS}"
print_info  "Skipped : ${SKIPPED}"
separator
print_info  "Staged output : ${OUTPUT_BASE}"
print_info  "Session log   : ${SESSION_LOG}"
separator
print_info  "Next step: On the DESTINATION server, run:"
print_info  "  ${DKIM_KEYUTIL} -a -d <domain>"
print_info  "  Then update your DNS TXT record with the new public key."
