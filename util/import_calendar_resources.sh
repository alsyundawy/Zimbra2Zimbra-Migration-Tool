#!/usr/bin/env bash
################################################################################
# Z2Z - Import Calendar Resources & Equipment Accounts
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
#
# Description:
#   Reads the manifests and TGZ archives produced by export_calendar_resources.sh
#   and provisions each calendar resource on the DESTINATION server. Steps:
#     1. Create the resource account with zmprov car (createCalendarResource).
#     2. Set zimbraCalResType, capacity, and contact email via zmprov mar.
#     3. Import calendar data from the TGZ archive via zmmailbox postRestURL.
#   Already-existing resources are detected and the import step is retried
#   without the provision step (idempotent).
#
#   Compatible with ZCS 7.x through 10.1 and Carbonio CE.
#   Run as the zimbra user on the DESTINATION server.
#
# Usage:
#   bash util/import_calendar_resources.sh [input_dir]
#   Default input_dir: ./export/calres
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
INPUT_BASE="${1:-${SCRIPT_DIR}/../export/calres}"
INPUT_BASE="$(realpath -m "${INPUT_BASE}")"

if [[ ! -d "${INPUT_BASE}" ]]; then
	print_error "ERROR: Input directory not found: ${INPUT_BASE}"
	print_error "       Run export_calendar_resources.sh on the source server first."
	exit 1
fi

SESSION_TS="$(date +'%d_%b_%Y-%H-%M')"
SESSION_LOG="${INPUT_BASE}/import_calres-${SESSION_TS}.log"

print_normal "Z2Z — Import Calendar Resources & Equipment"
separator
print_info "Input directory : ${INPUT_BASE}"
print_info "Session log     : ${SESSION_LOG}"
separator

SUCCESS=0
SKIPPED=0
FAILED=0
COUNT=0

# ============================================================================
# Helper: read a key=value manifest file
# ============================================================================

read_manifest_key() {
	local key="$1"
	local file="$2"
	grep "^${key}=" "${file}" | head -n 1 | cut -d'=' -f2-
}

# ============================================================================
# Main import loop
# ============================================================================

for RES_DIR in "${INPUT_BASE}"/*/; do
	[[ -d "${RES_DIR}" ]] || continue

	MANIFEST="${RES_DIR}/manifest.conf"
	[[ -f "${MANIFEST}" ]] || continue

	RES_EMAIL="$(read_manifest_key 'email' "${MANIFEST}")"
	[[ -z "${RES_EMAIL}" ]] && continue
	[[ "${RES_EMAIL}" != *"@"* ]] && continue

	((COUNT++)) || true
	print_normal "[${COUNT}] ${RES_EMAIL}"

	RES_DN="$(read_manifest_key 'displayName' "${MANIFEST}")"
	RES_TYPE="$(read_manifest_key 'zimbraCalResType' "${MANIFEST}")"
	RES_CAP="$(read_manifest_key 'zimbraCalResCapacity' "${MANIFEST}")"
	RES_CONTACT="$(read_manifest_key 'zimbraCalResContactEmail' "${MANIFEST}")"

	# Check if resource already exists.
	RESOURCE_EXISTS=false
	if zmprov gar "${RES_EMAIL}" zimbraId &>/dev/null 2>&1; then
		RESOURCE_EXISTS=true
		print_info "  Resource already exists — skipping provisioning."
	fi

	# Provision if needed.
	if [[ "${RESOURCE_EXISTS}" == "false" ]]; then
		print_info "  Provisioning resource..."
		if zmprov car "${RES_EMAIL}" "${RES_DN:-${RES_EMAIL}}" >>"${SESSION_LOG}" 2>&1; then
			print_ok "  Resource account created."
		else
			print_error "  ERROR: Failed to create resource '${RES_EMAIL}'"
			((FAILED++)) || true
			echo "[FAIL] ${RES_EMAIL} — car failed" >> "${SESSION_LOG}"
			continue
		fi

		# Set resource-specific attributes.
		declare -a MAR_ARGS=()
		[[ -n "${RES_TYPE}" ]]    && MAR_ARGS+=(zimbraCalResType "${RES_TYPE}")
		[[ -n "${RES_CAP}" ]]     && MAR_ARGS+=(zimbraCalResCapacity "${RES_CAP}")
		[[ -n "${RES_CONTACT}" ]] && MAR_ARGS+=(zimbraCalResContactEmail "${RES_CONTACT}")

		if ((${#MAR_ARGS[@]} > 0)); then
			zmprov mar "${RES_EMAIL}" "${MAR_ARGS[@]}" >>"${SESSION_LOG}" 2>&1 || true
		fi
		unset MAR_ARGS
	fi

	# Import calendar TGZ if present.
	CAL_ARCHIVE="${RES_DIR}/calendar.tgz"
	if [[ -f "${CAL_ARCHIVE}" ]]; then
		print_info "  Importing calendar data..."
		if zmmailbox -z -m "${RES_EMAIL}" -t 0 \
			postRestURL "//?fmt=tgz&resolve=skip" "${CAL_ARCHIVE}" \
			>>"${SESSION_LOG}" 2>&1; then
			print_ok "  Calendar data imported."
			echo "[OK] ${RES_EMAIL}" >> "${SESSION_LOG}"
			((SUCCESS++)) || true
		else
			print_error "  ERROR: Calendar import failed for ${RES_EMAIL}"
			((FAILED++)) || true
			echo "[FAIL] ${RES_EMAIL} — postRestURL failed" >> "${SESSION_LOG}"
		fi
	else
		print_info "  No calendar TGZ found — skipping data import."
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
