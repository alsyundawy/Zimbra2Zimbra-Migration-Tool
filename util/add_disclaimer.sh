#!/usr/bin/env bash
################################################################################
# Add Disclaimer Utility
# Adds domain disclaimers to all Zimbra domains
# Maintained by alsyundawy
# Note: From version 8.5 onwards, disclaimers are per-domain (not universal)
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

# Check user privileges (zimbra or root)
current_user="$(whoami 2>/dev/null || id -un)"
if [[ "${current_user}" != "zimbra" && "${EUID}" -ne 0 ]] && ! sudo -n true 2>/dev/null; then
	echo "ERROR: This script requires zimbra or root privileges." >&2
	exit 1
fi

# Disclaimer file paths
readonly DISCLAIMER_TEXT="/opt/zimbra/postfix/conf/disclaimer.txt"
readonly DISCLAIMER_HTML="/opt/zimbra/postfix/conf/disclaimer.html"

# Validate disclaimer files exist
if [[ ! -f "${DISCLAIMER_TEXT}" ]] || [[ ! -f "${DISCLAIMER_HTML}" ]]; then
	echo "ERROR: Disclaimer files not found at:" >&2
	echo "  - ${DISCLAIMER_TEXT}" >&2
	echo "  - ${DISCLAIMER_HTML}" >&2
	exit 1
fi

# Add disclaimers to all domains
add_disclaimers() {
	local domain
	local text_content
	local html_content

	# Read disclaimer contents
	text_content="$(cat "${DISCLAIMER_TEXT}")" || {
		echo "ERROR: Cannot read disclaimer text file" >&2
		return 1
	}

	html_content="$(cat "${DISCLAIMER_HTML}")" || {
		echo "ERROR: Cannot read disclaimer HTML file" >&2
		return 1
	}

	# Get all domains
	local domains
	domains="$(zmprov gad 2>/dev/null || true)"

	local domain_count=0
	local success_count=0

	while IFS= read -r domain; do
		if [[ -z "${domain}" ]]; then
			continue
		fi

		((domain_count++)) || true
		echo "Adding disclaimer to domain [${domain_count}]: ${domain}"

		# Enable domain disclaimer signature and attach text & HTML
		if zmprov md "${domain}" \
			zimbraDomainMandatoryMailSignatureEnabled TRUE \
			zimbraAmavisDomainDisclaimerText "${text_content}" \
			zimbraAmavisDomainDisclaimerHTML "${html_content}" 2>/dev/null; then
			((success_count++)) || true
		else
			echo "WARNING: Failed to add disclaimer to ${domain}" >&2
		fi
	done <<<"${domains}"

	echo ""
	echo "================================"
	echo "Disclaimer update completed."
	echo "Total domains processed: ${domain_count}"
	echo "Successfully configured: ${success_count}"
	echo "================================"
}

# Main execution
main() {
	echo "================================"
	echo "Zimbra Disclaimer Utility v1.0.6"
	echo "================================================================================"
	echo ""

	# Warn user about domain-based disclaimers
	echo "NOTE: This will add disclaimers to all configured domains."
	echo "From Zimbra 8.5+, disclaimers are applied per domain."
	echo ""

	read -r -p "Continue? (yes/no) " choice
	echo ""

	case "${choice}" in
	y | Y | yes | s | S | sim)
		add_disclaimers
		;;
	n | N | no | nao)
		echo "Operation cancelled."
		exit 0
		;;
	*)
		echo "Invalid choice. Aborting."
		exit 1
		;;
	esac
}

# Run main function
main "$@"
