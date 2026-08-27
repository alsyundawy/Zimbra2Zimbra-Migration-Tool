#!/usr/bin/env bash
################################################################################
# Z2Z - Export Calendar Resources & Equipment Accounts
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
#
# Description:
#   Discovers all calendar resources (Rooms and Equipment) via zmprov gar
#   and exports their provisioning metadata (type, capacity, contact email,
#   display name, and account status) to export/calres/<account>/manifest.conf.
#   Also exports each resource's Calendar folder contents as a TGZ archive
#   via zmmailbox for data migration.
#
#   Compatible with ZCS 7.x through 10.1 and Carbonio CE.
#   Run as the zimbra user on the SOURCE server.
#
# Usage:
#   bash util/export_calendar_resources.sh [output_dir]
#   Default output_dir: ./export/calres
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
OUTPUT_BASE="${1:-${SCRIPT_DIR}/../export/calres}"
OUTPUT_BASE="$(realpath -m "${OUTPUT_BASE}")"

mkdir -p "${OUTPUT_BASE}" || {
	print_error "ERROR: Cannot create output directory: ${OUTPUT_BASE}"
	exit 1
}

SESSION_TS="$(date +'%d_%b_%Y-%H-%M')"
SESSION_LOG="${OUTPUT_BASE}/export_calres-${SESSION_TS}.log"

print_normal "Z2Z — Export Calendar Resources & Equipment"
separator
print_info "Output directory : ${OUTPUT_BASE}"
print_info "Session log      : ${SESSION_LOG}"
separator

# ============================================================================
# Discover calendar resources
# ============================================================================

print_info "Discovering calendar resources..."
RESOURCE_LIST="$(zmprov gar 2>/dev/null || true)"

TOTAL=$(echo "${RESOURCE_LIST}" | grep -c -v '^$' || echo 0)
print_info "Resources found : ${TOTAL}"

if ((TOTAL == 0)); then
	print_info "No calendar resources found. Nothing to export."
	exit 0
fi

separator

SUCCESS=0
FAILED=0
COUNT=0

# ============================================================================
# Helper: extract a single attribute from zmprov ga output
# ============================================================================

extract_attr() {
	local attr="$1"
	local raw="$2"
	echo "${raw}" | grep "^${attr}:" | head -n 1 | sed "s/^${attr}: //"
}

# ============================================================================
# Main export loop
# ============================================================================

while IFS= read -r RES; do
	[[ -z "${RES}" ]] && continue
	((COUNT++)) || true

	print_normal "[${COUNT}/${TOTAL}] ${RES}"
	RES_DIR="${OUTPUT_BASE}/${RES}"
	mkdir -p "${RES_DIR}"

	# Fetch resource attributes.
	RAW_ATTRS="$(
		zmprov gar "${RES}" \
			zimbraCalResType \
			zimbraCalResCapacity \
			zimbraCalResContactEmail \
			displayName \
			zimbraAccountStatus \
			zimbraAccountCalendarUserType \
			2>>"${SESSION_LOG}" || true
	)"

	RES_TYPE="$(extract_attr 'zimbraCalResType' "${RAW_ATTRS}")"
	RES_CAP="$(extract_attr 'zimbraCalResCapacity' "${RAW_ATTRS}")"
	RES_CONTACT="$(extract_attr 'zimbraCalResContactEmail' "${RAW_ATTRS}")"
	RES_DN="$(extract_attr 'displayName' "${RAW_ATTRS}")"
	RES_STATUS="$(extract_attr 'zimbraAccountStatus' "${RAW_ATTRS}")"
	RES_CAL_TYPE="$(extract_attr 'zimbraAccountCalendarUserType' "${RAW_ATTRS}")"

	# Write provisioning manifest.
	EXPORT_TS="$(date +'%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")"
	{
		echo "# Z2Z Calendar Resource Manifest"
		echo "# Exported: ${EXPORT_TS}"
		echo "# Resource: ${RES}"
		echo "email=${RES}"
		echo "displayName=${RES_DN}"
		echo "zimbraCalResType=${RES_TYPE}"
		echo "zimbraCalResCapacity=${RES_CAP}"
		echo "zimbraCalResContactEmail=${RES_CONTACT}"
		echo "zimbraAccountStatus=${RES_STATUS}"
		echo "zimbraAccountCalendarUserType=${RES_CAL_TYPE}"
	} > "${RES_DIR}/manifest.conf"

	print_info "  Manifest saved."

	# Export calendar data as TGZ.
	CAL_ARCHIVE="${RES_DIR}/calendar.tgz"
	print_info "  Exporting calendar data..."
	if zmmailbox -z -m "${RES}" -t 0 getRestURL 'Calendar/?fmt=tgz' > "${CAL_ARCHIVE}" 2>>"${SESSION_LOG}"; then
		print_ok "  Calendar TGZ saved : ${CAL_ARCHIVE}"
		echo "[OK] ${RES}" >> "${SESSION_LOG}"
		((SUCCESS++)) || true
	else
		print_error "  WARN: Calendar export failed for ${RES} (resource may be empty)"
		rm -f "${CAL_ARCHIVE}"
		echo "[WARN] ${RES} — calendar export failed" >> "${SESSION_LOG}"
		# BUG FIX: was incrementing SUCCESS here; manifest was saved but archive
		# failed, so this correctly tracks it as a failure for the summary counter.
		((FAILED++)) || true
	fi

done <<< "${RESOURCE_LIST}"

# ============================================================================
# Summary
# ============================================================================

separator
print_normal "Export complete."
print_info  "Total   : ${TOTAL}"
print_ok    "Success : ${SUCCESS}"
print_error "Failed  : ${FAILED}"
separator
print_info  "Staged output : ${OUTPUT_BASE}"
print_info  "Session log   : ${SESSION_LOG}"
