#!/bin/bash
################################################################################
# Z2Z Helper Functions Library
# Changelog:
#   2016-11-15: Initial creation (Fabio Soares Schmidt)
#   2025-06-06: Optimization, English translation, ShellCheck compliance
################################################################################

set -euo pipefail

# ============================================================================
# Color Output Functions
# ============================================================================

# ANSI color codes for terminal output
readonly COLOR_BLUE='\e[1;34m'
readonly COLOR_RED='\e[1;31m'
readonly COLOR_YELLOW='\e[1;33m'
readonly COLOR_GREEN='\e[1;32m'
readonly COLOR_RESET='\e[0m'

# Output text in blue (normal information)
print_normal() {
    printf "%b%-6s%b\n" "${COLOR_BLUE}" "$*" "${COLOR_RESET}"
}

# Output text in red (error messages)
print_error() {
    printf "%b%s%b\n" "${COLOR_RED}" "$*" "${COLOR_RESET}" >&2
}

# Output text in yellow (informational)
print_info() {
    printf "%b%s%b\n" "${COLOR_YELLOW}" "$*" "${COLOR_RESET}"
}

# Output text in green (confirmation/choice)
print_choice() {
    printf "%b%s%b\n" "${COLOR_GREEN}" "$*" "${COLOR_RESET}"
}

# ============================================================================
# Utility Functions
# ============================================================================

# Display separator line
separator_char() {
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++"
}

# Prompt user for confirmation
test_exec() {
    local choice
    read -r -p "Continue (yes/no)? " choice
    case "${choice}" in
        y|Y|yes|s|S|sim)
            print_normal "Starting utility"
            ;;
        n|N|no|nao)
            exit 0
            ;;
        *)
            test_exec
            ;;
    esac
}

# ============================================================================
# Directory & File Validation
# ============================================================================

# Check if directory exists and is accessible
check_directory() {
    local dir="$1"
    if [[ ! -d "${dir}" ]]; then
        print_error "ERROR: Directory '${dir}' does not exist. Aborting."
        exit 1
    else
        print_info "OK: Directory '${dir}' exists."
    fi
}

# Check if required commands are available
check_command() {
    local -a commands=("$@")
    for cmd in "${commands[@]}"; do
        if ! type "${cmd}" &>/dev/null; then
            print_error "ERROR: Command '${cmd}' not found. Aborting."
            exit 1
        fi
        print_info "OK: Command '${cmd}' available."
        separator_char
    done
}

# ============================================================================
# Zimbra Environment Checks
# ============================================================================

# Verify script is running as Zimbra user
run_as_zimbra() {
    if [[ "$(whoami)" != "zimbra" ]]; then
        print_error "ERROR: This script must be executed as the Zimbra user."
        exit 1
    else
        print_info "OK: Running as Zimbra user."
    fi
}

# Validate single server or single mailbox environment
check_mailbox() {
    local mailbox_servers
    mailbox_servers=$(zmprov gas mailbox 2>/dev/null | wc -l)
    
    if (( mailbox_servers > 1 )); then
        print_error "WARNING: Current version is designed for single server or single mailbox environments."
        print_error "WARNING: For environments with multiple mailbox servers, manual modifications may be required."
    else
        print_normal "OK: Environment has single mailbox server."
    fi
}

# ============================================================================
# Hostname Management
# ============================================================================

# Prompt for new hostname with FQDN validation
enter_new_hostname() {
    local user_input
    local fqdn_parts
    
    read -r -p "Enter the new Zimbra server hostname: " user_input
    
    if [[ -z "${user_input}" ]]; then
        enter_new_hostname
        return
    fi
    
    fqdn_parts=$(echo "${user_input}" | awk -F. '{print NF}')
    
    if (( fqdn_parts < 2 )); then
        print_error "ERROR: Provided hostname is not a valid FQDN."
        enter_new_hostname
        return
    fi
    
    export NEW_HOSTNAME="${user_input}"
    print_choice "Hostname set to: ${NEW_HOSTNAME}"
}

# Interactive hostname replacement prompt
replace_hostname() {
    local destino="$1"
    local choice
    
    read -r -p "Replace Zimbra server hostname (yes/no)? " choice
    case "${choice}" in
        y|Y|yes|s|S|sim)
            print_choice "Hostname will be changed."
            local old_hostname="${zimbra_server_hostname}"
            enter_new_hostname
            sed -i "s/${old_hostname}/${NEW_HOSTNAME}/g" "${destino}/CONTAS.ldif"
            sed -i "s/${old_hostname}/${NEW_HOSTNAME}/g" "${destino}/LISTAS.ldif"
            print_info "Hostname replacement completed."
            ;;
        n|N|no|nao)
            print_choice "Original server hostname will be maintained."
            ;;
        *)
            replace_hostname "${destino}"
            ;;
    esac
}

# ============================================================================
# Mailbox Export Configuration
# ============================================================================

# Prompt whether to export mailboxes
export_mailboxes() {
    local choice
    read -r -p "Export mailboxes (yes/no)? " choice
    case "${choice}" in
        y|Y|yes|s|S|sim)
            print_choice "Creating mailbox export list for all accounts."
            ;;
        n|N|no|nao)
            print_choice "Mailbox export skipped. Execution aborted by user."
            exit 0
            ;;
        *)
            export_mailboxes
            ;;
    esac
}

# Prompt for export destination directory
get_export_destination() {
    local user_input
    read -r -p "Enter export directory path: " user_input
    
    if [[ -z "${user_input}" ]]; then
        print_error "No directory specified."
        get_export_destination
        return
    fi
    
    if [[ ! -d "${user_input}" ]]; then
        mkdir -p "${user_input}" || {
            print_error "ERROR: Cannot create directory ${user_input}"
            get_export_destination
            return
        }
    fi
    
    print_choice "Export directory: ${user_input}"
    echo "${user_input}"
}

# ============================================================================
# LDAP Export Functions
# ============================================================================

# Export Class of Service (COS) from LDAP
export_cos() {
    local hostname="$1"
    local binddn="$2"
    local destino="$3"
    local password="${zimbra_ldap_password:-}"
    
    print_normal "EXPORTING CLASS OF SERVICE"
    separator_char
    
    ldapsearch -x \
        -H "ldap://${hostname}" \
        -D "${binddn}" \
        -w "${password}" \
        -b '' \
        -LLL "(objectclass=zimbraCOS)" > "${destino}/COS.ldif" || {
        print_error "ERROR: Failed to export COS"
        exit 1
    }
    
    print_info "CLASS OF SERVICE exported successfully: ${destino}/COS.ldif"
}

# Export user accounts (excluding system accounts)
export_accounts() {
    local hostname="$1"
    local binddn="$2"
    local destino="$3"
    local password="${zimbra_ldap_password:-}"
    
    print_normal "EXPORTING USER ACCOUNTS"
    separator_char
    
    ldapsearch -x \
        -H "ldap://${hostname}" \
        -D "${binddn}" \
        -w "${password}" \
        -b '' \
        -LLL '(&(!(zimbraIsSystemResource=TRUE))(objectClass=zimbraAccount))' > "${destino}/CONTAS.ldif" || {
        print_error "ERROR: Failed to export accounts"
        exit 1
    }
    
    print_info "USER ACCOUNTS exported successfully: ${destino}/CONTAS.ldif"
}

# Export mail aliases
export_aliases() {
    local hostname="$1"
    local binddn="$2"
    local destino="$3"
    local workdir="$4"
    local password="${zimbra_ldap_password:-}"
    
    print_normal "EXPORTING MAIL ALIASES"
    separator_char
    
    # Get list of aliases
    ldapsearch -x \
        -H "ldap://${hostname}" \
        -D "${binddn}" \
        -w "${password}" \
        -b '' \
        -LLL '(&(!(uid=root))(!(uid=postmaster))(objectclass=zimbraAlias))' uid | \
        grep '^uid' | \
        awk '{print $2}' > "${workdir}/lista_contas.ldif" || {
        print_error "ERROR: Failed to get alias list"
        return
    }
    
    # Export each alias
    > "${destino}/APELIDOS.ldif"  # Create empty file
    while IFS= read -r mail; do
        ldapsearch -x \
            -H "ldap://${hostname}" \
            -D "${binddn}" \
            -w "${password}" \
            -b '' \
            -LLL "(&(uid=${mail})(objectclass=zimbraAlias))" >> "${destino}/APELIDOS.ldif" || {
            print_error "WARNING: Failed to export alias ${mail}"
        }
    done < "${workdir}/lista_contas.ldif"
    
    print_info "MAIL ALIASES exported successfully: ${destino}/APELIDOS.ldif"
}

# Export distribution lists
export_distribution_lists() {
    local hostname="$1"
    local binddn="$2"
    local destino="$3"
    local password="${zimbra_ldap_password:-}"
    
    print_normal "EXPORTING DISTRIBUTION LISTS"
    separator_char
    
    ldapsearch -x \
        -H "ldap://${hostname}" \
        -D "${binddn}" \
        -w "${password}" \
        -b '' \
        -LLL "(|(objectclass=zimbraGroup)(objectclass=zimbraDistributionList))" > "${destino}/LISTAS.ldif" || {
        print_error "ERROR: Failed to export distribution lists"
        exit 1
    }
    
    print_info "DISTRIBUTION LISTS exported successfully: ${destino}/LISTAS.ldif"
}

# ============================================================================
# Mailbox Export Script Generation
# ============================================================================

# Build full mailbox export script
execute_export_full() {
    local export_path="$1"
    local workdir="$2"
    local script_file="${workdir}/script_export_FULL.sh"
    local import_script="${workdir}/script_import_FULL.sh"
    
    print_normal "INBOX: Creating mailbox export script:"
    print_info "${script_file}"
    
    # Initialize scripts
    > "${script_file}"
    > "${import_script}"
    chmod +x "${script_file}" "${import_script}"
    
    # Get list of mailboxes
    local mailbox_list
    mailbox_list=$(zmprov -l gaa 2>/dev/null | grep -v -E "admin|virus-|ham\.|spam\.|galsync" || true)
    
    # Generate export/import commands
    while IFS= read -r mailbox; do
        [[ -z "${mailbox}" ]] && continue
        echo "zmmailbox -z -m '${mailbox}' -t 0 getRestURL \"//?fmt=tgz\" > '${export_path}/${mailbox}.tgz'" >> "${script_file}"
        echo "zmmailbox -z -m '${mailbox}' -t 0 postRestURL \"//?fmt=tgz&resolve=skip\" '${export_path}/${mailbox}.tgz'" >> "${import_script}"
    done <<< "${mailbox_list}"
}

# Build trash folder export script
execute_export_trash() {
    local export_path="$1"
    local workdir="$2"
    local script_file="${workdir}/script_export_TRASH.sh"
    local import_script="${workdir}/script_import_TRASH.sh"
    
    print_normal "TRASH: Creating mailbox trash export script:"
    print_info "${script_file}"
    
    # Initialize scripts
    > "${script_file}"
    > "${import_script}"
    chmod +x "${script_file}" "${import_script}"
    
    # Get list of mailboxes
    local mailbox_list
    mailbox_list=$(zmprov -l gaa 2>/dev/null | grep -v -E "admin|virus-|ham\.|spam\.|galsync" || true)
    
    # Generate export/import commands
    while IFS= read -r mailbox; do
        [[ -z "${mailbox}" ]] && continue
        echo "zmmailbox -z -m '${mailbox}' -t 0 gru \"//Trash?fmt=tgz\" > '${export_path}/${mailbox}-Trash.tgz'" >> "${script_file}"
        echo "zmmailbox -z -m '${mailbox}' -t 0 postRestURL \"//?fmt=tgz&resolve=skip\" '${export_path}/${mailbox}-Trash.tgz'" >> "${import_script}"
    done <<< "${mailbox_list}"
}

# Build junk/spam folder export script
execute_export_junk() {
    local export_path="$1"
    local workdir="$2"
    local script_file="${workdir}/script_export_JUNK.sh"
    local import_script="${workdir}/script_import_JUNK.sh"
    
    print_normal "SPAM: Creating mailbox junk export script:"
    print_info "${script_file}"
    
    # Initialize scripts
    > "${script_file}"
    > "${import_script}"
    chmod +x "${script_file}" "${import_script}"
    
    # Get list of mailboxes
    local mailbox_list
    mailbox_list=$(zmprov -l gaa 2>/dev/null | grep -v -E "admin|virus-|ham\.|spam\.|galsync" || true)
    
    # Generate export/import commands
    while IFS= read -r mailbox; do
        [[ -z "${mailbox}" ]] && continue
        echo "zmmailbox -z -m '${mailbox}' -t 0 gru \"//Junk?fmt=tgz\" > '${export_path}/${mailbox}-Junk.tgz'" >> "${script_file}"
        echo "zmmailbox -z -m '${mailbox}' -t 0 postRestURL \"//?fmt=tgz&resolve=skip\" '${export_path}/${mailbox}-Junk.tgz'" >> "${import_script}"
    done <<< "${mailbox_list}"
}

# ============================================================================
# Cleanup Functions
# ============================================================================

# Clean temporary files from export directory
clear_workdir() {
    local workdir="$1"
    rm -f "${workdir}/lista_contas.ldif"
    rm -rf "${workdir:?}/alias"
}
