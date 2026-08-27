#!/bin/bash
################################################################################
# Z2Z - Zimbra to Zimbra Migration Tool
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
# For more information, please read README.md and INSTALL
#
# Version: 1.0.3
# License: CC BY-NC-SA / GPL
################################################################################

set -euo pipefail # Exit on error, undefined variables, and pipe failures

# Script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper functions
if [[ ! -f "${SCRIPT_DIR}/func.sh" ]]; then
	echo "ERROR: func.sh not found in ${SCRIPT_DIR}" >&2
	exit 1
fi
# shellcheck source=func.sh disable=SC1091
source "${SCRIPT_DIR}/func.sh"

# Banner display
main() {
	clear
	if [[ -f "${SCRIPT_DIR}/banner.txt" ]]; then
		cat "${SCRIPT_DIR}/banner.txt"
	fi
	echo ""

	# Verify execution as Zimbra user
	run_as_zimbra
	separator_char

	# Confirm user wants to continue
	test_exec
	separator_char

	# Required commands for execution
	declare -a REQUIRED_COMMANDS=('ldapsearch' 'zmmailbox' 'zmshutil' 'zmprov')
	check_command "${REQUIRED_COMMANDS[@]}"
	separator_char

	# Validate single server or single mailbox environment
	check_mailbox
	separator_char

	# Source Zimbra environment variables
	if [[ -f ~/bin/zmshutil ]]; then
		# shellcheck source=/dev/null
		source ~/bin/zmshutil
		zmsetvars
	else
		echo "ERROR: Cannot source Zimbra environment" >&2
		exit 1
	fi

	# Set Zimbra environment variables (defined by zmsetvars)
	# shellcheck disable=SC2154
	local ZIMBRA_HOSTNAME="${zimbra_server_hostname:-}"
	# shellcheck disable=SC2154
	local ZIMBRA_BINDDN="${zimbra_ldap_userdn:-}"

	# Directory management
	local WORKDIR="${SCRIPT_DIR}/export"
	local DIRETORIO="${WORKDIR}"
	check_directory "${DIRETORIO}"
	separator_char

	DIRETORIO="${SCRIPT_DIR}/skell"
	check_directory "${DIRETORIO}"
	separator_char

	local DESTINO="${WORKDIR}"
	mkdir -p "${DESTINO}/alias" || {
		echo "ERROR: Cannot create ${DESTINO}/alias" >&2
		exit 1
	}

	# Export Class of Service (COS)
	export_cos "${ZIMBRA_HOSTNAME}" "${ZIMBRA_BINDDN}" "${DESTINO}"
	separator_char

	# Export accounts (excluding system accounts)
	export_accounts "${ZIMBRA_HOSTNAME}" "${ZIMBRA_BINDDN}" "${DESTINO}"
	separator_char

	# Export aliases
	export_aliases "${ZIMBRA_HOSTNAME}" "${ZIMBRA_BINDDN}" "${DESTINO}" "${WORKDIR}"
	separator_char

	# Export distribution lists
	export_distribution_lists "${ZIMBRA_HOSTNAME}" "${ZIMBRA_BINDDN}" "${DESTINO}"
	separator_char

	# Clean temporary files
	clear_workdir "${WORKDIR}"

	# Copy import script and simple banner
	cp -f "${SCRIPT_DIR}/skell/importar_ldap.sh" "${DESTINO}/" || {
		echo "WARNING: Cannot copy importar_ldap.sh" >&2
	}
	cp -f "${SCRIPT_DIR}/skell/banner_simples.txt" "${DESTINO}/" || {
		echo "WARNING: Cannot copy banner_simples.txt" >&2
	}
	chmod +x "${DESTINO}/importar_ldap.sh" 2>/dev/null || true

	# Interactive hostname replacement
	replace_hostname "${DESTINO}"
	separator_char

	# Interactive mailbox export
	export_mailboxes
	separator_char

	# Get export destination
	local export_path
	export_path=$(get_export_destination)
	separator_char

	# Export full mailboxes
	execute_export_full "${export_path}" "${WORKDIR}"
	separator_char

	# Export trash folders
	execute_export_trash "${export_path}" "${WORKDIR}"
	separator_char

	# Export spam/junk folders
	execute_export_junk "${export_path}" "${WORKDIR}"
	separator_char

	echo "Migration export completed successfully!"
}

# Run main function
main "$@"
