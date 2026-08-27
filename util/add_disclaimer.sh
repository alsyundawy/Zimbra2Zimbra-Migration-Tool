#!/bin/bash
################################################################################
# Add Disclaimer Utility
# Adds disclaimers to all Zimbra domains
# Maintained by alsyundawy
# Note: From version 8.5 onwards, disclaimers are per-domain (not universal)
################################################################################

set -euo pipefail

# Check if running as root or with appropriate privileges
if [[ ${EUID} -ne 0 ]] && ! sudo -n true 2>/dev/null; then
	echo "ERROR: This script requires root privileges or sudo access" >&2
	exit 1
fi

# Disclaimer file paths
readonly DISCLAIMER_TEXT="/opt/zimbra/postfix/conf/disclaimer.txt"
readonly DISCLAIMER_HTML="/opt/zimbra/postfix/conf/disclaimer.html"

# Validate disclaimer files exist
if [[ ! -f ${DISCLAIMER_TEXT} ]] || [[ ! -f ${DISCLAIMER_HTML} ]]; then
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
	text_content=$(cat "${DISCLAIMER_TEXT}") || {
		echo "ERROR: Cannot read disclaimer text file" >&2
		return 1
	}

	html_content=$(cat "${DISCLAIMER_HTML}") || {
		echo "ERROR: Cannot read disclaimer HTML file" >&2
		return 1
	}

	# Get all domains and add disclaimers
	local domains
	domains=$(zmprov gad 2>/dev/null || true)

	while IFS= read -r domain; do
		if [[ -z ${domain} ]]; then
			continue
		fi

		echo "Adding disclaimer to domain: ${domain}"

		# Add text disclaimer
		zmprov md "${domain}" \
			zimbraAmavisDomainDisclaimerText "${text_content}" || {
			echo "WARNING: Failed to add text disclaimer to ${domain}" >&2
		}

		# Add HTML disclaimer
		zmprov md "${domain}" \
			zimbraAmavisDomainDisclaimerHTML "${html_content}" || {
			echo "WARNING: Failed to add HTML disclaimer to ${domain}" >&2
		}
	done <<<"${domains}"

	echo "Disclaimer update completed."
}

# Main execution
main() {
	echo "================================"
	echo "Zimbra Disclaimer Utility"
	echo "================================"
	echo ""

	# Warn user about domain-based disclaimers
	echo "NOTE: This will add disclaimers to all configured domains."
	echo "From Zimbra 8.5+, disclaimers are applied per domain."
	echo ""

	read -r -p "Continue? (yes/no) " -n 1 choice
	echo ""

	case "${choice}" in
	y | Y)
		add_disclaimers
		;;
	n | N)
		echo "Operation cancelled."
		exit 0
		;;
	*)
		echo "Invalid choice."
		exit 1
		;;
	esac
}

# Run main function
main "$@"
