#!/usr/bin/env bash
################################################################################
# Z2Z LDAP Import Script
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
# For more information, please read README.md and INSTALL
#
# Version: 1.0.5
# License: CC BY-NC-SA / GPL
################################################################################

set -Eeuo pipefail

# ============================================================================
# Color Output Functions
# ============================================================================

readonly COLOR_BLUE='\e[1;34m'
readonly COLOR_RED='\e[1;31m'
readonly COLOR_YELLOW='\e[1;33m'
readonly COLOR_GREEN='\e[1;32m'
readonly COLOR_RESET='\e[0m'

print_normal() {
	printf "%b%-6s%b\n" "${COLOR_BLUE}" "$*" "${COLOR_RESET}"
}

print_error() {
	printf "%b%s%b\n" "${COLOR_RED}" "$*" "${COLOR_RESET}" >&2
}

print_info() {
	printf "%b%s%b\n" "${COLOR_YELLOW}" "$*" "${COLOR_RESET}"
}

print_choice() {
	printf "%b%s%b\n" "${COLOR_GREEN}" "$*" "${COLOR_RESET}"
}

# ============================================================================
# Initial Setup & Environment
# ============================================================================

# Ensure all Zimbra binaries across ZCS 7.x-10.1 and multi-distro are in PATH
for p in /opt/zimbra/bin /opt/zimbra/common/bin /opt/zimbra/common/sbin /opt/zimbra/openldap/bin /opt/zimbra/postfix/sbin /opt/zimbra/mysql/bin; do
	if [[ -d "${p}" ]] && [[ ":${PATH}:" != *":${p}:"* ]]; then
		PATH="${p}:${PATH}"
	fi
done
export PATH

# Verify running as Zimbra user
current_user="$(whoami 2>/dev/null || id -un)"
if [[ "${current_user}" != "zimbra" ]]; then
	print_error "ERROR: This script must be executed as the Zimbra user."
	exit 1
fi

# Source Zimbra environment
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

# shellcheck disable=SC2154
ZIMBRA_HOSTNAME="${zimbra_server_hostname:-}"
if [[ -z "${ZIMBRA_HOSTNAME}" ]]; then
	ZIMBRA_HOSTNAME="$(zmhostname 2>/dev/null || hostname -f 2>/dev/null || echo "")"
fi
readonly ZIMBRA_HOSTNAME

# shellcheck disable=SC2154
ZIMBRA_BINDDN="${zimbra_ldap_userdn:-}"
if [[ -z "${ZIMBRA_BINDDN}" ]]; then
	ZIMBRA_BINDDN="$(zmlocalconfig -s -m nokey zimbra_ldap_userdn 2>/dev/null || echo "uid=zimbra,cn=admins,cn=zimbra")"
fi
readonly ZIMBRA_BINDDN

# shellcheck disable=SC2154
ZIMBRA_PASSWORD="${zimbra_ldap_password:-}"
if [[ -z "${ZIMBRA_PASSWORD}" ]]; then
	ZIMBRA_PASSWORD="$(zmlocalconfig -s -m nokey zimbra_ldap_password 2>/dev/null || echo "")"
fi
readonly ZIMBRA_PASSWORD

# shellcheck disable=SC2154
configured_ldap_url="${ldap_url:-${ldap_master_url:-}}"
if [[ -n "${configured_ldap_url}" ]]; then
	LDAP_URI="$(echo "${configured_ldap_url}" | awk '{print $1}')"
elif [[ -n "${ZIMBRA_HOSTNAME}" ]]; then
	LDAP_URI="ldap://${ZIMBRA_HOSTNAME}"
else
	LDAP_URI="ldap://localhost:389"
fi
readonly LDAP_URI

# DN constants
readonly DEFAULT_COS_DN="cn=default,cn=cos,cn=zimbra"
readonly DEFAULT_EXTERNAL_COS_DN="cn=defaultExternal,cn=cos,cn=zimbra"

# Session logging
SESSION_TIMESTAMP="$(date +"%d_%b_%Y-%H-%M")"
readonly SESSION_TIMESTAMP
readonly SESSION_LOG="session-${SESSION_TIMESTAMP}.log"

# ============================================================================
# Pre-Flight Checks
# ============================================================================

echo "Verifying required files..."

# Check for required import files
declare -a REQUIRED_FILES=('CONTAS.ldif' 'COS.ldif' 'APELIDOS.ldif' 'LISTAS.ldif')

for file in "${REQUIRED_FILES[@]}"; do
	if [[ ! -r "${file}" ]]; then
		print_error "ERROR: File '${file}' not found or not readable."
		exit 1
	fi
	print_info "OK: File '${file}' found and readable."
done

if [[ -f "DOMINIOS.ldif" ]]; then
	print_info "OK: File 'DOMINIOS.ldif' found (Automated domain provisioning enabled)."
fi

echo ""

# Verify hostname consistency
local_hostname="${ZIMBRA_HOSTNAME}"
ldif_hostname="$(grep -E '^zimbraMailHost:' CONTAS.ldif 2>/dev/null | head -n 1 | awk '{print $2}' || echo "")"

if [[ -n "${ldif_hostname}" && "${local_hostname}" != "${ldif_hostname}" ]]; then
	print_error "ERROR: Hostname mismatch!"
	print_info "  Local server: ${local_hostname}"
	print_info "  LDIF files:   ${ldif_hostname}"
	print_info "Please ensure hostnames match or use replace_hostname in export before import."
	exit 1
fi

print_info "OK: Hostname verified (${local_hostname})"
echo ""

# Verify required commands
declare -a REQUIRED_COMMANDS=('ldapsearch' 'ldapadd' 'ldapdelete' 'zmhostname' 'zmmailbox')

for cmd in "${REQUIRED_COMMANDS[@]}"; do
	if ! type "${cmd}" &>/dev/null; then
		print_error "ERROR: Required command '${cmd}' not found."
		exit 1
	fi
done

print_info "OK: All required commands available."
echo ""

# ============================================================================
# Banner & Initial Information
# ============================================================================

if [[ -f banner_simples.txt ]]; then
	cat banner_simples.txt
fi

echo ""
echo ""

print_info "Session started: ${SESSION_TIMESTAMP}"
print_normal "Session log: ${SESSION_LOG}"

echo ""

# ============================================================================
# Interactive Prompts
# ============================================================================

# Prompt for import confirmation — uses while loop to avoid unbounded recursion
test_exec() {
	local choice
	while true; do
		read -r -p "Begin import of domains, COS, accounts, aliases, and distribution lists? (yes/no) " choice
		case "${choice}" in
		y | Y | yes | s | S | sim)
			print_normal "Starting Z2Z import..."
			return 0
			;;
		n | N | no | nao)
			print_choice "Import cancelled by user."
			exit 0
			;;
		*)
			print_info "Please enter yes or no."
			;;
		esac
	done
}

# Prompt for admin user import — uses while loop to avoid unbounded recursion
test_import_admin() {
	local choice
	while true; do
		read -r -p "Import ADMIN user? (yes/no) " choice
		case "${choice}" in
		y | Y | yes | s | S | sim)
			print_normal "Removing existing ADMIN user..."

			# Get current admin DN safely
			local admin_dn
			admin_dn=$(ldapsearch -x \
				-H "${LDAP_URI}" \
				-D "${ZIMBRA_BINDDN}" \
				-w "${ZIMBRA_PASSWORD}" \
				-b '' \
				-LLL "uid=admin" dn 2>/dev/null | sed -n 's/^dn: //p' | head -n 1 || echo "")

			if [[ -n "${admin_dn}" ]]; then
				ldapdelete -r -x \
					-H "${LDAP_URI}" \
					-D "${ZIMBRA_BINDDN}" \
					-w "${ZIMBRA_PASSWORD}" \
					"${admin_dn}" &>>"${SESSION_LOG}" || {
					print_error "WARNING: Failed to delete existing admin user"
				}
			fi
			return 0
			;;
		n | N | no | nao)
			print_choice "Admin user will not be imported. Use the new installation password."
			return 0
			;;
		*)
			print_info "Please enter yes or no."
			;;
		esac
	done
}

# Run confirmation prompts
test_exec
echo ""
test_import_admin

# ============================================================================
# LDAP Import Operations
# ============================================================================

echo ""
# Import Domains First (if DOMINIOS.ldif or create_domains.sh exists)
if [[ -f "DOMINIOS.ldif" ]]; then
	print_info "Importing email domains from DOMINIOS.ldif..."
	if ldapadd -c -x \
		-H "${LDAP_URI}" \
		-D "${ZIMBRA_BINDDN}" \
		-w "${ZIMBRA_PASSWORD}" \
		-f DOMINIOS.ldif &>>"${SESSION_LOG}"; then
		print_choice "Domain import completed."
	else
		print_error "WARNING: Domain LDAP import had some warnings (existing domains were skipped). See ${SESSION_LOG}"
	fi
elif [[ -f "create_domains.sh" ]]; then
	print_info "Executing domain provisioning helper (create_domains.sh)..."
	bash create_domains.sh &>>"${SESSION_LOG}" || true
	print_choice "Domain provisioning script finished."
fi

echo ""
print_info "Removing default Zimbra COS entries..."
ldapdelete -r -x \
	-H "${LDAP_URI}" \
	-D "${ZIMBRA_BINDDN}" \
	-w "${ZIMBRA_PASSWORD}" \
	"${DEFAULT_COS_DN}" &>>"${SESSION_LOG}" || {
	print_error "WARNING: Could not delete default COS (may not exist)"
}

ldapdelete -r -x \
	-H "${LDAP_URI}" \
	-D "${ZIMBRA_BINDDN}" \
	-w "${ZIMBRA_PASSWORD}" \
	"${DEFAULT_EXTERNAL_COS_DN}" &>>"${SESSION_LOG}" || {
	print_error "WARNING: Could not delete external COS (may not exist)"
}

echo ""

# Import Class of Service
print_info "Importing classes of service..."
if ldapadd -c -x \
	-H "${LDAP_URI}" \
	-D "${ZIMBRA_BINDDN}" \
	-w "${ZIMBRA_PASSWORD}" \
	-f COS.ldif &>>"${SESSION_LOG}"; then
	print_choice "COS import completed."
else
	print_error "ERROR: COS import failed. See ${SESSION_LOG}"
fi

echo ""

# Import User Accounts
print_info "Importing user accounts..."
if ldapadd -c -x \
	-H "${LDAP_URI}" \
	-D "${ZIMBRA_BINDDN}" \
	-w "${ZIMBRA_PASSWORD}" \
	-f CONTAS.ldif &>>"${SESSION_LOG}"; then
	print_choice "Account import completed."
else
	print_error "ERROR: Account import failed. See ${SESSION_LOG}"
fi

echo ""

# Import Mail Aliases
print_info "Importing mail aliases..."
if ldapadd -c -x \
	-H "${LDAP_URI}" \
	-D "${ZIMBRA_BINDDN}" \
	-w "${ZIMBRA_PASSWORD}" \
	-f APELIDOS.ldif &>>"${SESSION_LOG}"; then
	print_choice "Alias import completed."
else
	print_error "ERROR: Alias import failed. See ${SESSION_LOG}"
fi

echo ""

# Import Distribution Lists
print_info "Importing distribution lists..."
if ldapadd -c -x \
	-H "${LDAP_URI}" \
	-D "${ZIMBRA_BINDDN}" \
	-w "${ZIMBRA_PASSWORD}" \
	-f LISTAS.ldif &>>"${SESSION_LOG}"; then
	print_choice "Distribution list import completed."
else
	print_error "ERROR: Distribution list import failed. See ${SESSION_LOG}"
fi

if [[ -f "global_settings_snapshot.txt" ]]; then
	echo ""
	print_info "NOTE: Source server global MTA settings snapshot is available in: global_settings_snapshot.txt"
fi

echo ""
echo "================================"
print_choice "LDAP import process completed successfully!"
print_normal "Review the session log: ${SESSION_LOG}"
echo "================================"
