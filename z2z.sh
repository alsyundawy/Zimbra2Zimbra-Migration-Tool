#!/usr/bin/env bash
################################################################################
# Z2Z - Zimbra to Zimbra Migration Tool
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
# For more information, please read README.md and INSTALL
#
# Version: 1.0.5
# License: CC BY-NC-SA / GPL
################################################################################

set -Eeuo pipefail # Exit on error, undefined variables, and pipe failures

# Script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper functions
if [[ ! -f "${SCRIPT_DIR}/func.sh" ]]; then
	echo "ERROR: func.sh not found in ${SCRIPT_DIR}" >&2
	exit 1
fi
# shellcheck source=func.sh disable=SC1091
source "${SCRIPT_DIR}/func.sh"

# Ensure all Zimbra binaries across ZCS 7.x-10.1 and multi-distro are in PATH
for _p in /opt/zimbra/bin /opt/zimbra/common/bin /opt/zimbra/common/sbin \
	/opt/zimbra/openldap/bin /opt/zimbra/postfix/sbin /opt/zimbra/mysql/bin; do
	if [[ -d "${_p}" ]] && [[ ":${PATH}:" != *":${_p}:"* ]]; then
		PATH="${_p}:${PATH}"
	fi
done
export PATH

# Main entry point
main() {
	# Clear terminal safely if interactive
	if [[ -t 1 ]]; then
		clear 2>/dev/null || true
	fi

	# Display banner
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
	declare -a REQUIRED_COMMANDS=('ldapsearch' 'zmmailbox' 'zmprov')
	check_command "${REQUIRED_COMMANDS[@]}"
	separator_char

	# Validate single server or single mailbox environment
	check_mailbox
	separator_char

	# Source Zimbra environment variables
	if [[ -f /opt/zimbra/bin/zmshutil ]]; then
		# shellcheck source=/dev/null
		source /opt/zimbra/bin/zmshutil
		zmsetvars
	elif [[ -f ~/bin/zmshutil ]]; then
		# shellcheck source=/dev/null
		source ~/bin/zmshutil
		zmsetvars
	else
		print_error "ERROR: Cannot source Zimbra environment (/opt/zimbra/bin/zmshutil or ~/bin/zmshutil)"
		exit 1
	fi

	# Set Zimbra environment variables (defined by zmsetvars with fallbacks)
	# shellcheck disable=SC2154
	local ZIMBRA_HOSTNAME="${zimbra_server_hostname:-}"
	if [[ -z "${ZIMBRA_HOSTNAME}" ]]; then
		ZIMBRA_HOSTNAME="$(zmhostname 2>/dev/null || hostname -f 2>/dev/null || echo "")"
	fi

	# shellcheck disable=SC2154
	local ZIMBRA_BINDDN="${zimbra_ldap_userdn:-}"
	if [[ -z "${ZIMBRA_BINDDN}" ]]; then
		ZIMBRA_BINDDN="$(zmlocalconfig -s -m nokey zimbra_ldap_userdn 2>/dev/null || echo "uid=zimbra,cn=admins,cn=zimbra")"
	fi

	# Directory management
	local WORKDIR="${SCRIPT_DIR}/export"
	check_directory "${WORKDIR}"
	separator_char

	local SKELLDIR="${SCRIPT_DIR}/skell"
	check_directory "${SKELLDIR}"
	separator_char

	local DESTINO="${WORKDIR}"
	mkdir -p "${DESTINO}/alias" || {
		print_error "ERROR: Cannot create ${DESTINO}/alias"
		exit 1
	}

	# Session logging setup
	local session_timestamp
	session_timestamp="$(date +"%d_%b_%Y-%H-%M")"
	local export_session_log="${DESTINO}/session-export-${session_timestamp}.log"
	print_info "Export session log: ${export_session_log}"
	separator_char

	# Export Email Domains (Automated Domain Provisioning)
	export_domains "${ZIMBRA_HOSTNAME}" "${ZIMBRA_BINDDN}" "${DESTINO}"
	separator_char

	# Export Global Configuration & MTA Settings Snapshot
	export_global_config "${ZIMBRA_HOSTNAME}" "${ZIMBRA_BINDDN}" "${DESTINO}"
	separator_char

	# Export Class of Service (COS)
	export_cos "${ZIMBRA_HOSTNAME}" "${ZIMBRA_BINDDN}" "${DESTINO}"
	separator_char

	# Export accounts (excluding system accounts)
	export_accounts "${ZIMBRA_HOSTNAME}" "${ZIMBRA_BINDDN}" "${DESTINO}"
	separator_char

	# Export aliases (high-speed single-pass atomic query)
	export_aliases "${ZIMBRA_HOSTNAME}" "${ZIMBRA_BINDDN}" "${DESTINO}" "${WORKDIR}"
	separator_char

	# Export distribution lists
	export_distribution_lists "${ZIMBRA_HOSTNAME}" "${ZIMBRA_BINDDN}" "${DESTINO}"
	separator_char

	# Clean temporary files
	clear_workdir "${WORKDIR}"

	# Copy import script and simple banner
	if [[ -f "${SCRIPT_DIR}/skell/importar_ldap.sh" ]]; then
		cp -f "${SCRIPT_DIR}/skell/importar_ldap.sh" "${DESTINO}/"
		chmod +x "${DESTINO}/importar_ldap.sh" 2>/dev/null || true
	else
		print_error "WARNING: ${SCRIPT_DIR}/skell/importar_ldap.sh not found"
	fi

	if [[ -f "${SCRIPT_DIR}/skell/banner_simples.txt" ]]; then
		cp -f "${SCRIPT_DIR}/skell/banner_simples.txt" "${DESTINO}/"
	fi

	# Interactive hostname replacement
	replace_hostname "${DESTINO}"
	separator_char

	# Interactive mailbox export prompt & filter configuration
	export_mailboxes
	separator_char

	# Get export destination directory
	local export_path
	export_path="$(get_export_destination)"
	separator_char

	# Generate full mailbox export/import scripts
	execute_export_full "${export_path}" "${WORKDIR}"
	separator_char

	# Generate trash folder export/import scripts
	execute_export_trash "${export_path}" "${WORKDIR}"
	separator_char

	# Generate junk/spam folder export/import scripts
	execute_export_junk "${export_path}" "${WORKDIR}"
	separator_char

	print_choice "Migration export staging completed successfully!"
	print_info "All LDAP objects, domain definitions, and batch scripts are ready in: ${WORKDIR}"
	separator_char

	# Optional immediate execution of mailbox export
	local run_export_now
	read -r -p "Do you want to start executing the mailbox export now in this session? (yes/no) " run_export_now
	case "${run_export_now}" in
	y | Y | yes | s | S | sim)
		print_normal "Starting live mailbox export..."
		bash "${WORKDIR}/script_export_FULL.sh"
		;;
	*)
		print_info "You can execute mailbox export later by running: ${WORKDIR}/script_export_FULL.sh"
		;;
	esac
}

# Run main function
main "$@"
