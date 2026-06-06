#!/bin/bash
################################################################################
# Z2Z LDAP Import Script
# Maintains by BKTECH <http://www.bktech.com.br>
# Copyright (C) 2016  Fabio Soares Schmidt <fabio@respirandolinux.com.br>
# For more information, please read the README and INSTALL files
#
# Version: 1.0.3 (Optimized & English-translated)
################################################################################

set -euo pipefail

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
# Initial Setup
# ============================================================================

# Verify running as Zimbra user
if [[ "$(whoami)" != "zimbra" ]]; then
    print_error "ERROR: This script must be executed as the Zimbra user."
    exit 1
fi

# Source Zimbra environment
if [[ -f ~/bin/zmshutil ]]; then
    # shellcheck source=/dev/null
    source ~/bin/zmshutil
    zmsetvars
else
    print_error "ERROR: Cannot source Zimbra environment (~/bin/zmshutil)"
    exit 1
fi

# ============================================================================
# Environment Variables
# ============================================================================

readonly ZIMBRA_HOSTNAME="${zimbra_server_hostname}"
readonly ZIMBRA_BINDDN="${zimbra_ldap_userdn}"
readonly ZIMBRA_PASSWORD="${zimbra_ldap_password}"

# DN constants
readonly DEFAULT_COS_DN="cn=default,cn=cos,cn=zimbra"
readonly DEFAULT_EXTERNAL_COS_DN="cn=defaultExternal,cn=cos,cn=zimbra"

# Session logging
readonly SESSION_TIMESTAMP=$(date +"%d_%b_%Y-%H-%M")
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

echo ""

# Verify hostname consistency
local_hostname="${ZIMBRA_HOSTNAME}"
ldif_hostname=$(grep zimbraMailHost CONTAS.ldif 2>/dev/null | head -1 | awk '{print $2}')

if [[ "${local_hostname}" != "${ldif_hostname}" ]]; then
    print_error "ERROR: Hostname mismatch!"
    print_info "  Local server: ${local_hostname}"
    print_info "  LDIF files: ${ldif_hostname}"
    exit 1
fi

print_info "OK: Hostname verified (${local_hostname})"
echo ""

# Verify required commands
declare -a REQUIRED_COMMANDS=('ldapsearch' 'ldapadd' 'ldapdelete' 'zmhostname' 'zmshutil' 'zmmailbox')

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

print_info "WARNING: This version does NOT create or import domains."
print_info "Please ensure all target domains have been created before proceeding."
print_info "Session started: ${SESSION_TIMESTAMP}"
print_normal "Session log: ${SESSION_LOG}"

echo ""

# ============================================================================
# Interactive Prompts
# ============================================================================

# Prompt for import confirmation
test_exec() {
    local choice
    read -r -p "Begin import of COS, accounts, aliases, and distribution lists? (yes/no) " choice
    case "${choice}" in
        y|Y|yes|s|S|sim)
            print_normal "Starting Z2Z import..."
            ;;
        n|N|no|nao)
            print_choice "Import cancelled by user."
            exit 0
            ;;
        *)
            test_exec
            ;;
    esac
}

# Prompt for admin user import
test_import_admin() {
    local choice
    read -r -p "Import ADMIN user? (yes/no) " choice
    case "${choice}" in
        y|Y|yes|s|S|sim)
            print_normal "Removing existing ADMIN user..."
            
            # Get current admin DN
            local admin_dn
            admin_dn=$(ldapsearch -x \
                -H "ldap://${ZIMBRA_HOSTNAME}" \
                -D "${ZIMBRA_BINDDN}" \
                -w "${ZIMBRA_PASSWORD}" \
                -b '' \
                -LLL "uid=admin" dn 2>/dev/null | awk 'NR==1 {print $2}' || echo "")
            
            if [[ -n "${admin_dn}" ]]; then
                ldapdelete -r -x \
                    -H "ldap://${ZIMBRA_HOSTNAME}" \
                    -D "${ZIMBRA_BINDDN}" \
                    -w "${ZIMBRA_PASSWORD}" \
                    "${admin_dn}" &>> "${SESSION_LOG}" || {
                    print_error "WARNING: Failed to delete existing admin user"
                }
            fi
            ;;
        n|N|no|nao)
            print_choice "Admin user will not be imported. Use the new installation password."
            ;;
        *)
            test_import_admin
            ;;
    esac
}

# Run confirmation prompts
test_exec
echo ""
test_import_admin

# ============================================================================
# LDAP Import Operations
# ============================================================================

echo ""
print_info "Removing default Zimbra COS entries..."
ldapdelete -r -x \
    -H "ldap://${ZIMBRA_HOSTNAME}" \
    -D "${ZIMBRA_BINDDN}" \
    -w "${ZIMBRA_PASSWORD}" \
    "${DEFAULT_COS_DN}" &>> "${SESSION_LOG}" || {
    print_error "WARNING: Could not delete default COS (may not exist)"
}

ldapdelete -r -x \
    -H "ldap://${ZIMBRA_HOSTNAME}" \
    -D "${ZIMBRA_BINDDN}" \
    -w "${ZIMBRA_PASSWORD}" \
    "${DEFAULT_EXTERNAL_COS_DN}" &>> "${SESSION_LOG}" || {
    print_error "WARNING: Could not delete external COS (may not exist)"
}

echo ""

# Import Class of Service
print_info "Importing classes of service..."
if ldapadd -c -x \
    -H "ldap://${ZIMBRA_HOSTNAME}" \
    -D "${ZIMBRA_BINDDN}" \
    -w "${ZIMBRA_PASSWORD}" \
    -f COS.ldif &>> "${SESSION_LOG}"; then
    print_choice "COS import completed."
else
    print_error "ERROR: COS import failed. See ${SESSION_LOG}"
fi

echo ""

# Import User Accounts
print_info "Importing user accounts..."
if ldapadd -c -x \
    -H "ldap://${ZIMBRA_HOSTNAME}" \
    -D "${ZIMBRA_BINDDN}" \
    -w "${ZIMBRA_PASSWORD}" \
    -f CONTAS.ldif &>> "${SESSION_LOG}"; then
    print_choice "Account import completed."
else
    print_error "ERROR: Account import failed. See ${SESSION_LOG}"
fi

echo ""

# Import Mail Aliases
print_info "Importing mail aliases..."
if ldapadd -c -x \
    -H "ldap://${ZIMBRA_HOSTNAME}" \
    -D "${ZIMBRA_BINDDN}" \
    -w "${ZIMBRA_PASSWORD}" \
    -f APELIDOS.ldif &>> "${SESSION_LOG}"; then
    print_choice "Alias import completed."
else
    print_error "ERROR: Alias import failed. See ${SESSION_LOG}"
fi

echo ""

# Import Distribution Lists
print_info "Importing distribution lists..."
if ldapadd -c -x \
    -H "ldap://${ZIMBRA_HOSTNAME}" \
    -D "${ZIMBRA_BINDDN}" \
    -w "${ZIMBRA_PASSWORD}" \
    -f LISTAS.ldif &>> "${SESSION_LOG}"; then
    print_choice "Distribution list import completed."
else
    print_error "ERROR: Distribution list import failed. See ${SESSION_LOG}"
fi

echo ""
echo "================================"
print_choice "LDAP import process completed successfully!"
print_normal "Review the session log: ${SESSION_LOG}"
echo "================================"
