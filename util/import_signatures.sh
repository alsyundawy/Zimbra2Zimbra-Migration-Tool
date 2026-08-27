#!/usr/bin/env bash
################################################################################
# Z2Z - Import User Webmail Signatures & Persona Identities
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
#
# Description:
#   Reads the staging directory produced by export_signatures.sh and recreates
#   each user's webmail signatures on the DESTINATION Zimbra server using
#   zmprov csig (createSignature). Persona identity relinks are applied via
#   zmprov mid (modifyIdentity). Idempotent: accounts with matching signatures
#   already present are skipped to prevent duplicates.
#
#   Compatible with ZCS 7.x through 10.1 and Carbonio CE.
#   Run as the zimbra user on the DESTINATION server.
#
# Usage:
#   bash util/import_signatures.sh [input_dir]
#   Default input_dir: ./export/signatures
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
# Argument & directory setup
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_BASE="${1:-${SCRIPT_DIR}/../export/signatures}"
INPUT_BASE="$(realpath -m "${INPUT_BASE}")"

if [[ ! -d "${INPUT_BASE}" ]]; then
	print_error "ERROR: Input directory not found: ${INPUT_BASE}"
	print_error "       Run export_signatures.sh on the source server first."
	exit 1
fi

SESSION_TS="$(date +'%d_%b_%Y-%H-%M')"
SESSION_LOG="${INPUT_BASE}/import_signatures-${SESSION_TS}.log"

print_normal "Z2Z — Import Webmail Signatures & Identities"
separator
print_info "Input directory : ${INPUT_BASE}"
print_info "Session log     : ${SESSION_LOG}"
separator

SUCCESS=0
SKIPPED=0
FAILED=0
COUNT=0

# ============================================================================
# Main import loop — iterate over account directories
# ============================================================================

for ACCT_DIR in "${INPUT_BASE}"/*/; do
	[[ -d "${ACCT_DIR}" ]] || continue

	ACCT="$(basename "${ACCT_DIR}")"
	# Skip log files or non-account entries (must contain @).
	[[ "${ACCT}" != *"@"* ]] && continue

	((COUNT++)) || true
	print_normal "[${COUNT}] ${ACCT}"

	# Verify account exists on destination server.
	if ! zmprov ga "${ACCT}" zimbraId &>/dev/null; then
		print_error "  WARN: Account '${ACCT}' not found on this server — skipping."
		((SKIPPED++)) || true
		echo "[SKIP] ${ACCT} — account not found" >> "${SESSION_LOG}"
		continue
	fi

	IMPORTED_SIG=0

	# Iterate over signature block directories (sig_N_name pattern).
	for BLOCK_DIR in "${ACCT_DIR}"sig_*/; do
		[[ -d "${BLOCK_DIR}" ]] || continue

		SIG_NAME=""
		SIG_TEXT=""
		SIG_HTML=""

		[[ -f "${BLOCK_DIR}/name.txt" ]] && SIG_NAME="$(cat "${BLOCK_DIR}/name.txt")"
		[[ -f "${BLOCK_DIR}/text.txt" ]] && SIG_TEXT="$(cat "${BLOCK_DIR}/text.txt")"
		[[ -f "${BLOCK_DIR}/html.txt" ]] && SIG_HTML="$(cat "${BLOCK_DIR}/html.txt")"

		if [[ -z "${SIG_NAME}" ]]; then
			print_info "  Empty signature name in ${BLOCK_DIR} — skipping block."
			continue
		fi

		# Build zmprov csig argument list dynamically.
		# We use temp files to avoid shell-quoting issues with special characters.
		local_text_arg=()
		local_html_arg=()

		if [[ -n "${SIG_TEXT}" ]]; then
			local_text_arg=(zimbraPrefMailSignature "${SIG_TEXT}")
		fi

		if [[ -n "${SIG_HTML}" ]]; then
			local_html_arg=(zimbraPrefMailSignatureHTML "${SIG_HTML}")
		fi

		if zmprov csig "${ACCT}" "${SIG_NAME}" \
			"${local_text_arg[@]+"${local_text_arg[@]}"}" \
			"${local_html_arg[@]+"${local_html_arg[@]}"}" \
			>>"${SESSION_LOG}" 2>&1; then
			print_ok "  Signature created: ${SIG_NAME}"
			((IMPORTED_SIG++)) || true
		else
			print_error "  WARN: Failed to create signature '${SIG_NAME}' for ${ACCT} (may already exist)"
			echo "[WARN] csig failed: ${ACCT} / ${SIG_NAME}" >> "${SESSION_LOG}"
		fi
	done

	if ((IMPORTED_SIG > 0)); then
		((SUCCESS++)) || true
	else
		# Account existed but had no importable blocks.
		((SKIPPED++)) || true
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
