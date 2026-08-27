#!/usr/bin/env bash
################################################################################
# Z2Z - Import Out-of-Office / Vacation Auto-Reply Settings
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
#
# Description:
#   Reads the .ooo flat files produced by export_ooo.sh and restores each
#   account's Out-of-Office configuration on the DESTINATION server via
#   zmprov ma. Date format is validated (YYYYMMDDHHMMSSZ) before applying.
#   Accounts that did not export OOO data are cleanly skipped.
#
#   Compatible with ZCS 7.x through 10.1 and Carbonio CE.
#   Run as the zimbra user on the DESTINATION server.
#
# Usage:
#   bash util/import_ooo.sh [input_dir]
#   Default input_dir: ./export/ooo
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
INPUT_BASE="${1:-${SCRIPT_DIR}/../export/ooo}"
INPUT_BASE="$(realpath -m "${INPUT_BASE}")"

if [[ ! -d "${INPUT_BASE}" ]]; then
	print_error "ERROR: Input directory not found: ${INPUT_BASE}"
	print_error "       Run export_ooo.sh on the source server first."
	exit 1
fi

SESSION_TS="$(date +'%d_%b_%Y-%H-%M')"
SESSION_LOG="${INPUT_BASE}/import_ooo-${SESSION_TS}.log"

print_normal "Z2Z — Import Out-of-Office / Vacation Settings"
separator
print_info "Input directory : ${INPUT_BASE}"
print_info "Session log     : ${SESSION_LOG}"
separator

SUCCESS=0
SKIPPED=0
FAILED=0
COUNT=0

# ============================================================================
# Helper: validate Zimbra date attribute format (YYYYMMDDHHMMSSZ)
# ============================================================================

is_valid_zimbra_date() {
	local date_val="$1"
	[[ -z "${date_val}" ]] && return 1
	[[ "${date_val}" =~ ^[0-9]{14}Z$ ]] && return 0
	return 1
}

# ============================================================================
# Main import loop
# ============================================================================

for OOO_FILE in "${INPUT_BASE}"/*.ooo; do
	[[ -f "${OOO_FILE}" ]] || continue

	ACCT="$(basename "${OOO_FILE}" .ooo)"
	((COUNT++)) || true

	print_normal "[${COUNT}] ${ACCT}"

	# Parse key=value flat file.
	OOO_ENABLED=""
	OOO_FROM=""
	OOO_UNTIL=""
	OOO_REPLY=""

	while IFS='=' read -r KEY VAL; do
		[[ -z "${KEY}" ]] && continue
		case "${KEY}" in
		zimbraPrefOutOfOfficeReplyEnabled) OOO_ENABLED="${VAL}" ;;
		zimbraPrefOutOfOfficeFromDate)      OOO_FROM="${VAL}" ;;
		zimbraPrefOutOfOfficeUntilDate)     OOO_UNTIL="${VAL}" ;;
		zimbraPrefOutOfOfficeReply)         OOO_REPLY="${VAL}" ;;
		*)                                  : ;;
		esac
	done < "${OOO_FILE}"

	# Validate account exists on this server.
	if ! zmprov ga "${ACCT}" zimbraId &>/dev/null; then
		print_error "  WARN: Account '${ACCT}' not found — skipping."
		((SKIPPED++)) || true
		echo "[SKIP] ${ACCT} — account not found" >> "${SESSION_LOG}"
		continue
	fi

	# Build the zmprov ma argument list dynamically.
	declare -a MA_ARGS=()

	[[ -n "${OOO_ENABLED}" ]] && MA_ARGS+=(zimbraPrefOutOfOfficeReplyEnabled "${OOO_ENABLED}")
	[[ -n "${OOO_REPLY}" ]]   && MA_ARGS+=(zimbraPrefOutOfOfficeReply "${OOO_REPLY}")

	# Validate and add date attributes only when they match the expected format (YYYYMMDDHHMMSSZ).
	if [[ -n "${OOO_FROM}" ]]; then
		if [[ "${OOO_FROM}" =~ ^[0-9]{14}Z$ ]]; then
			MA_ARGS+=(zimbraPrefOutOfOfficeFromDate "${OOO_FROM}")
		else
			print_error "  WARN: Invalid FromDate format '${OOO_FROM}' — skipping date."
		fi
	fi

	if [[ -n "${OOO_UNTIL}" ]]; then
		if [[ "${OOO_UNTIL}" =~ ^[0-9]{14}Z$ ]]; then
			MA_ARGS+=(zimbraPrefOutOfOfficeUntilDate "${OOO_UNTIL}")
		else
			print_error "  WARN: Invalid UntilDate format '${OOO_UNTIL}' — skipping date."
		fi
	fi

	if ((${#MA_ARGS[@]} == 0)); then
		print_info "  No valid OOO attributes to apply — skipping."
		((SKIPPED++)) || true
		continue
	fi

	if zmprov ma "${ACCT}" "${MA_ARGS[@]}" >>"${SESSION_LOG}" 2>&1; then
		print_ok "  OOO settings applied (enabled=${OOO_ENABLED})."
		((SUCCESS++)) || true
		echo "[OK] ${ACCT}" >> "${SESSION_LOG}"
	else
		print_error "  ERROR: Failed to apply OOO settings for ${ACCT}"
		((FAILED++)) || true
		echo "[FAIL] ${ACCT}" >> "${SESSION_LOG}"
	fi

	unset MA_ARGS

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
