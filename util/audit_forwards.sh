#!/usr/bin/env bash
################################################################################
# Audit Mail Forwards Utility
# Audits email forwarding configurations across all Zimbra accounts
# Maintained by alsyundawy
# Reference: https://wiki.zimbra.com/wiki/Obtain_all_the_forwards_per_each_account
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

# Check if running as zimbra user (optional but recommended)
current_user="$(whoami 2>/dev/null || id -un)"
if [[ "${current_user}" != "zimbra" && "${EUID}" -ne 0 ]]; then
	echo "WARNING: Not running as root or zimbra user. Some operations may fail." >&2
fi

# Color codes for output
readonly COLOR_GREEN='\e[1;32m'
readonly COLOR_RESET='\e[0m'

# Audit all forwarding addresses
audit_forwards() {
	local account
	local forwarding_address
	local pref_forwarding_address
	local local_delivery
	local account_count=0
	local forward_count=0
	local accounts

	echo "================================================================================"
	echo "                     Zimbra Mail Forwarding Audit v1.0.4"
	echo "================================================================================"
	echo ""

	# Get all accounts excluding system accounts
	accounts="$(zmprov -l gaa 2>/dev/null | grep -v -E "^(virus-[^@]*|ham\.[^@]*|spam\.[^@]*|galsync[^@]*)@" || true)"

	while IFS= read -r account; do
		if [[ -z "${account}" ]]; then
			continue
		fi

		((account_count++)) || true

		# Retrieve account forwarding attributes
		local account_attrs
		account_attrs="$(zmprov ga "${account}" zimbraMailForwardingAddress zimbraPrefMailForwardingAddress zimbraPrefMailLocalDelivery 2>/dev/null || true)"

		forwarding_address="$(echo "${account_attrs}" | grep -E '^zimbraMailForwardingAddress:' | sed 's/zimbraMailForwardingAddress: //g' | tr '\n' ',' | sed 's/,$//' || echo "")"
		pref_forwarding_address="$(echo "${account_attrs}" | grep -E '^zimbraPrefMailForwardingAddress:' | sed 's/zimbraPrefMailForwardingAddress: //g' | tr '\n' ',' | sed 's/,$//' || echo "")"
		local_delivery="$(echo "${account_attrs}" | grep -E '^zimbraPrefMailLocalDelivery:' | head -n 1 | awk '{print $2}' || echo "TRUE")"

		if [[ -n "${forwarding_address}" || -n "${pref_forwarding_address}" ]]; then
			local combined_forwards=""
			if [[ -n "${forwarding_address}" && -n "${pref_forwarding_address}" && "${forwarding_address}" != "${pref_forwarding_address}" ]]; then
				combined_forwards="${forwarding_address}, ${pref_forwarding_address} (pref)"
			elif [[ -n "${forwarding_address}" ]]; then
				combined_forwards="${forwarding_address} (admin)"
			else
				combined_forwards="${pref_forwarding_address} (user-pref)"
			fi

			printf "%b%-38s -> %-30s [KeepLocal: %s]%b\n" \
				"${COLOR_GREEN}" \
				"${account}" \
				"${combined_forwards}" \
				"${local_delivery}" \
				"${COLOR_RESET}"
			((forward_count++)) || true
		fi
	done <<<"${accounts}"

	# Summary
	echo ""
	echo "================================================================================"
	echo "Audit Summary:"
	echo "  Total active accounts inspected: ${account_count}"
	echo "  Accounts with forwarding rules:  ${forward_count}"
	echo "================================================================================"
}

# Main execution
main() {
	audit_forwards "$@"
}

# Run main function
main "$@"
