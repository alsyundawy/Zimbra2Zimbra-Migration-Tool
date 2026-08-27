#!/usr/bin/env bash
################################################################################
# Mailbox Size Report Utility
# Generates a report of actual mailbox storage usage across all accounts
# Maintained by alsyundawy
# Useful for pre-migration planning and post-migration validation
# Reference: https://wiki.zimbra.com/wiki/Get_all_user%27s_mailbox_size_from_CLI
#
# Version: 1.0.4
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

# Color codes for output
readonly COLOR_BLUE='\e[1;34m'
readonly COLOR_GREEN='\e[1;32m'
readonly COLOR_YELLOW='\e[1;33m'
readonly COLOR_RESET='\e[0m'

# Check if running as zimbra user
current_user="$(whoami 2>/dev/null || id -un)"
if [[ "${current_user}" != "zimbra" ]]; then
	echo "ERROR: This script must be executed as the Zimbra user." >&2
	exit 1
fi

# Human-readable size converter helper
format_bytes() {
	local bytes="$1"
	if ((bytes >= 1099511627776)); then
		awk -v b="${bytes}" 'BEGIN { printf "%.2f TB", b / 1099511627776 }'
	elif ((bytes >= 1073741824)); then
		awk -v b="${bytes}" 'BEGIN { printf "%.2f GB", b / 1073741824 }'
	elif ((bytes >= 1048576)); then
		awk -v b="${bytes}" 'BEGIN { printf "%.2f MB", b / 1048576 }'
	elif ((bytes >= 1024)); then
		awk -v b="${bytes}" 'BEGIN { printf "%.2f KB", b / 1024 }'
	else
		printf "%d B" "${bytes}"
	fi
}

# Generate mailbox size report
generate_report() {
	local account
	local raw_output
	local mailbox_bytes
	local total_size=0
	local account_count=0
	local failed_count=0
	local accounts

	echo "================================================================================"
	echo "                     Zimbra Mailbox Size Report v1.0.4"
	echo "================================================================================"
	echo ""

	# Get all user accounts excluding system accounts
	accounts="$(zmprov -l gaa 2>/dev/null | grep -v -E "^(virus-[^@]*|ham\.[^@]*|spam\.[^@]*|galsync[^@]*)@" || true)"

	while IFS= read -r account; do
		if [[ -z "${account}" ]]; then
			continue
		fi

		((account_count++))

		# Get mailbox size
		raw_output="$(zmmailbox -z -m "${account}" gms 2>/dev/null || echo "")"
		mailbox_bytes="$(echo "${raw_output}" | tr -dc '0-9')"

		if [[ -z "${mailbox_bytes}" ]]; then
			printf "%b%-42s %16s%b\n" \
				"${COLOR_YELLOW}" "${account}" "[FAILED/EMPTY]" "${COLOR_RESET}" >&2
			((failed_count++))
			continue
		fi

		((total_size += mailbox_bytes))
		local readable_size
		readable_size="$(format_bytes "${mailbox_bytes}")"

		# Display account info
		printf "%b%-42s %16s%b\n" \
			"${COLOR_GREEN}" \
			"${account}" \
			"${readable_size}" \
			"${COLOR_RESET}"
	done <<<"${accounts}"

	# Summary statistics
	echo ""
	echo "================================================================================"
	echo "Report Summary:"
	printf "%b%-42s %16d%b\n" \
		"${COLOR_BLUE}" "Total accounts processed:" "${account_count}" "${COLOR_RESET}"
	printf "%b%-42s %16d%b\n" \
		"${COLOR_BLUE}" "Failed retrievals:" "${failed_count}" "${COLOR_RESET}"

	local total_readable
	total_readable="$(format_bytes "${total_size}")"
	printf "%b%-42s %16s%b\n" \
		"${COLOR_BLUE}" "Total mailbox storage consumed:" "${total_readable}" "${COLOR_RESET}"
	echo "================================================================================"
}

# Main execution
main() {
	generate_report "$@"
}

# Run main function
main "$@"
