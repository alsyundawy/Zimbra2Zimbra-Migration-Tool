#!/usr/bin/env bash
################################################################################
# Audit Mailbox Shares Utility
# Discovers and audits shared folders, calendars, contacts, and tasks in Zimbra
# Maintained by alsyundawy
# Reference: https://wiki.zimbra.com/wiki/How_to_find_all_shares
#
# Version: 1.0.6
# License: CC BY-NC-SA / GPL
################################################################################

set -Eeuo pipefail

# Ensure all Zimbra binaries across ZCS 7.x-10.1 and multi-distro are in PATH
for p in /opt/zimbra/bin /opt/zimbra/common/bin /opt/zimbra/common/sbin /opt/zimbra/openldap/bin /opt/zimbra/postfix/sbin /opt/zimbra/mysql/bin; do
	if [[ -d "${p}" ]] && [[ ":${PATH}:" != *":${p}:"* ]]; then
		PATH="${p}:${PATH}"
	fi
done
export PATH

# Check if running as zimbra user (optional but recommended)
current_user="$(whoami 2>/dev/null || id -un)"
if [[ "${current_user}" != "zimbra" && "${EUID}" -ne 0 ]]; then
	echo "WARNING: Not running as root or zimbra user. Some operations may fail." >&2
fi

# Color codes for output
readonly COLOR_BLUE='\e[1;34m'
readonly COLOR_GREEN='\e[1;32m'
readonly COLOR_YELLOW='\e[1;33m'
readonly COLOR_RESET='\e[0m'

# Audit all mailbox shares
audit_shares() {
	local account
	local shares_output
	local account_count=0
	local share_count=0
	local accounts

	echo "================================================================================"
	echo "                   Zimbra Mailbox Shares Audit Utility v1.0.6"
	echo "================================================================================"
	echo ""

	# Get all user accounts excluding system accounts
	accounts="$(zmprov -l gaa 2>/dev/null | grep -v -E "^(virus-[^@]*|ham\.[^@]*|spam\.[^@]*|galsync[^@]*)@" || true)"

	while IFS= read -r account; do
		if [[ -z "${account}" ]]; then
			continue
		fi

		((account_count++)) || true

		# Retrieve all shares for the account
		shares_output="$(zmmailbox -z -m "${account}" getAllShares 2>/dev/null || true)"

		# Filter out header line if present
		local clean_shares
		clean_shares="$(echo "${shares_output}" | grep -v -E "^Folder|^--|^$" || true)"

		if [[ -n "${clean_shares}" ]]; then
			printf "%b[ACCOUNT] %s%b\n" "${COLOR_BLUE}" "${account}" "${COLOR_RESET}"
			while IFS= read -r share_line; do
				[[ -z "${share_line}" ]] && continue
				printf "  %b↳ %s%b\n" "${COLOR_GREEN}" "${share_line}" "${COLOR_RESET}"
				((share_count++)) || true
			done <<<"${clean_shares}"
			echo ""
		fi
	done <<<"${accounts}"

	# Summary
	echo "================================================================================"
	echo "Shares Audit Summary:"
	printf "%b%-42s %16d%b\n" "${COLOR_BLUE}" "Total accounts scanned:" "${account_count}" "${COLOR_RESET}"
	printf "%b%-42s %16d%b\n" "${COLOR_GREEN}" "Total active shares found:" "${share_count}" "${COLOR_RESET}"
	if ((share_count == 0)); then
		printf "%bNo custom mailbox shares found across accounts.%b\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
	fi
	echo "================================================================================"
}

# Main execution
main() {
	audit_shares "$@"
}

# Run main function
main "$@"
