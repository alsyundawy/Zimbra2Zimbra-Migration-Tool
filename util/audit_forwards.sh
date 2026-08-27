#!/bin/bash
################################################################################
# Audit Mail Forwards Utility
# Audits all email forwarding configurations in Zimbra accounts
# Maintained by alsyundawy
# Reference: https://wiki.zimbra.com/wiki/Obtain_all_the_forwards_per_each_account
################################################################################

set -euo pipefail

# Check if running as zimbra user (optional but recommended)
current_uid="${EUID:-0}"
current_user="$(whoami || true)"
if [[ ${current_uid} -ne 0 ]] && [[ ${current_user} != "zimbra" ]]; then
	echo "WARNING: Not running as root or zimbra user. Some operations may fail." >&2
fi

# Color codes for output
readonly COLOR_GREEN='\e[1;32m'
readonly COLOR_RESET='\e[0m'

# Audit all forwarding addresses
audit_forwards() {
	local account
	local forwarding_address
	local account_count=0
	local forward_count=0
	local accounts

	echo "================================"
	echo "Zimbra Mail Forwarding Audit"
	echo "================================"
	echo ""

	# Get all accounts
	accounts=$(zmprov -l gaa 2>/dev/null || true)

	while IFS= read -r account; do
		if [[ -z ${account} ]]; then
			continue
		fi

		((account_count++))

		# Get forwarding address for the account
		forwarding_address=$(zmprov ga "${account}" 2>/dev/null |
			grep 'zimbraPrefMailForwardingAddress' |
			sed 's/zimbraPrefMailForwardingAddress: //' || echo "")

		if [[ -n ${forwarding_address} ]]; then
			printf "%b%-40s -> %s%b\n" \
				"${COLOR_GREEN}" \
				"${account}" \
				"${forwarding_address}" \
				"${COLOR_RESET}"
			((forward_count++))
		fi
	done <<<"${accounts}"

	# Summary
	echo ""
	echo "================================"
	echo "Summary:"
	echo "  Total accounts: ${account_count}"
	echo "  Accounts with forwards: ${forward_count}"
	echo "================================"
}

# Main execution
main() {
	audit_forwards "$@"
}

# Run main function
main "$@"
