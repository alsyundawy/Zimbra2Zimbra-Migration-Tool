#!/usr/bin/env bash
################################################################################
# Z2Z - Export User Webmail Signatures & Persona Identities
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
#
# Description:
#   Exports all user webmail signatures (plain-text and HTML) and persona
#   identity mappings for every non-system account. Output is staged in
#   export/signatures/<account>/ as individual attribute files, ready for
#   import_signatures.sh on the destination server.
#
#   Compatible with ZCS 7.x through 10.1 and Carbonio CE.
#   Run as the zimbra user on the SOURCE server.
#
# Usage:
#   bash util/export_signatures.sh [output_dir]
#   Default output_dir: ./export/signatures
#
# Version: 1.0.5
# License: CC BY-NC-SA / GPL
################################################################################

set -Eeuo pipefail

export LC_ALL='en_US.UTF-8'

# ============================================================================
# PATH setup — supports ZCS 7.x-10.1 multi-distro layouts
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
# Pre-flight: user check
# ============================================================================

current_user="$(whoami 2>/dev/null || id -un)"
if [[ "${current_user}" != "zimbra" ]]; then
	print_error "ERROR: Must be run as the zimbra user."
	exit 1
fi

# ============================================================================
# Zimbra environment
# ============================================================================

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
OUTPUT_BASE="${1:-${SCRIPT_DIR}/../export/signatures}"
OUTPUT_BASE="$(realpath -m "${OUTPUT_BASE}")"

mkdir -p "${OUTPUT_BASE}" || {
	print_error "ERROR: Cannot create output directory: ${OUTPUT_BASE}"
	exit 1
}

SESSION_TS="$(date +'%d_%b_%Y-%H-%M')"
SESSION_LOG="${OUTPUT_BASE}/export_signatures-${SESSION_TS}.log"

print_normal "Z2Z — Export Webmail Signatures & Identities"
separator
print_info "Output directory : ${OUTPUT_BASE}"
print_info "Session log      : ${SESSION_LOG}"
separator

# ============================================================================
# Discover accounts (exclude system/spam/ham/galsync/virus)
# ============================================================================

print_info "Discovering accounts..."
ACCOUNT_LIST="$(
	zmprov -l gaa 2>/dev/null |
		grep -v -E '^(virus-[^@]*|ham\.[^@]*|spam\.[^@]*|galsync[^@]*)@' ||
		true
)"

TOTAL=$(echo "${ACCOUNT_LIST}" | grep -c -v '^$' || echo 0)
print_info "Accounts found   : ${TOTAL}"
separator

SUCCESS=0
SKIPPED=0
FAILED=0
COUNT=0

# ============================================================================
# Helper: save a parsed signature block to disk
# ============================================================================

# Variables used inside the loop — declared here for clarity.
_SIG_NAME=""
_SIG_ID=""
_SIG_TEXT=""
_SIG_HTML=""
_SIG_BLOCK_COUNT=0

save_sig_block() {
	local acct_dir="$1"
	if [[ -z "${_SIG_NAME}" ]]; then
		return
	fi
	((_SIG_BLOCK_COUNT++)) || true
	local safe_name
	safe_name="$(printf '%s' "${_SIG_NAME}" | tr -cd '[:alnum:]_.-')"
	local block_dir="${acct_dir}/sig_${_SIG_BLOCK_COUNT}_${safe_name}"
	mkdir -p "${block_dir}"
	printf '%s' "${_SIG_NAME}"  > "${block_dir}/name.txt"
	printf '%s' "${_SIG_ID}"   > "${block_dir}/id.txt"
	printf '%s' "${_SIG_TEXT}" > "${block_dir}/text.txt"
	printf '%s' "${_SIG_HTML}" > "${block_dir}/html.txt"
	print_info "  Signature saved : ${_SIG_NAME}"
}

# ============================================================================
# Main export loop
# ============================================================================

while IFS= read -r ACCT; do
	[[ -z "${ACCT}" ]] && continue
	((COUNT++)) || true

	print_normal "[${COUNT}/${TOTAL}] ${ACCT}"
	ACCT_DIR="${OUTPUT_BASE}/${ACCT}"
	mkdir -p "${ACCT_DIR}"

	# ---- Signatures ----
	SIG_RAW="$(zmprov gsig "${ACCT}" 2>>"${SESSION_LOG}" || true)"

	if [[ -z "${SIG_RAW}" ]]; then
		print_info "  No signatures — skipping account."
		((SKIPPED++)) || true
	else
		# Save raw dump for reference / debugging.
		printf '%s\n' "${SIG_RAW}" > "${ACCT_DIR}/signatures_raw.txt"

		# Reset block-state counters for each account.
		_SIG_NAME=""
		_SIG_ID=""
		_SIG_TEXT=""
		_SIG_HTML=""
		_SIG_BLOCK_COUNT=0

		while IFS= read -r LINE; do
			case "${LINE}" in
			"# name "*)
				save_sig_block "${ACCT_DIR}"
				_SIG_NAME="${LINE#\# name }"
				_SIG_ID=""
				_SIG_TEXT=""
				_SIG_HTML=""
				;;
			"zimbraSignatureId: "*)
				_SIG_ID="${LINE#zimbraSignatureId: }"
				;;
			"zimbraPrefMailSignature: "*)
				_SIG_TEXT="${LINE#zimbraPrefMailSignature: }"
				;;
			"zimbraPrefMailSignatureHTML: "*)
				_SIG_HTML="${LINE#zimbraPrefMailSignatureHTML: }"
				;;
			*)
				:
				;;
			esac
		done <<< "${SIG_RAW}"
		# Flush the last block.
		save_sig_block "${ACCT_DIR}"

		((SUCCESS++)) || true
	fi

	# ---- Identities / Personas ----
	IDENT_RAW="$(zmprov gid "${ACCT}" 2>>"${SESSION_LOG}" || true)"
	if [[ -n "${IDENT_RAW}" ]]; then
		printf '%s\n' "${IDENT_RAW}" > "${ACCT_DIR}/identities_raw.txt"
		print_info "  Identities saved."
	fi

done <<< "${ACCOUNT_LIST}"

# ============================================================================
# Summary
# ============================================================================

separator
print_normal "Export complete."
print_info  "Total    : ${TOTAL}"
print_ok    "Success  : ${SUCCESS}"
print_info  "Skipped  : ${SKIPPED}"
print_error "Failed   : ${FAILED}"
separator
print_info  "Staged output : ${OUTPUT_BASE}"
print_info  "Session log   : ${SESSION_LOG}"
