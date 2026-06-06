#!/bin/bash
################################################################################
# Mailbox Size Report Utility
# Generates a report of actual mailbox usage for all accounts
# Useful for validating the migration process
# Reference: https://wiki.zimbra.com/wiki/Get_all_user%27s_mailbox_size_from_CLI
################################################################################

set -euo pipefail

# Color codes for output
readonly COLOR_BLUE='\e[1;34m'
readonly COLOR_GREEN='\e[1;32m'
readonly COLOR_YELLOW='\e[1;33m'
readonly COLOR_RESET='\e[0m'

# Check if running as zimbra user
if [[ "$(whoami)" != "zimbra" ]]; then
    echo "ERROR: This script must be executed as the Zimbra user." >&2
    exit 1
fi

# Generate mailbox size report
generate_report() {
    local account
    local mailbox_size
    local total_size=0
    local account_count=0
    local failed_count=0
    
    echo "================================"
    echo "Zimbra Mailbox Size Report"
    echo "================================"
    echo ""
    
    # Get all user accounts
    while IFS= read -r account; do
        if [[ -z "${account}" ]]; then
            continue
        fi
        
        ((account_count++))
        
        # Get mailbox size
        mailbox_size=$(zmmailbox -z -m "${account}" gms 2>/dev/null) || {
            printf "%bERROR: Failed to get size for %s%b\n" \
                "${COLOR_YELLOW}" "${account}" "${COLOR_RESET}" >&2
            ((failed_count++))
            continue
        }
        
        # Display account info
        printf "%b%-40s %8s%b\n" \
            "${COLOR_GREEN}" \
            "${account}" \
            "${mailbox_size}" \
            "${COLOR_RESET}"
        
        # Accumulate total if size is a number
        if [[ "${mailbox_size}" =~ ^[0-9]+$ ]]; then
            ((total_size += mailbox_size))
        fi
    done < <(zmprov -l gaa)
    
    # Summary statistics
    echo ""
    echo "================================"
    echo "Summary:"
    printf "%b%-40s %8d%b\n" \
        "${COLOR_BLUE}" \
        "Total accounts processed:" \
        "${account_count}" \
        "${COLOR_RESET}"
    printf "%b%-40s %8d%b\n" \
        "${COLOR_BLUE}" \
        "Failed retrievals:" \
        "${failed_count}" \
        "${COLOR_RESET}"
    
    # Convert total size to human-readable format
    local size_unit="bytes"
    local display_size="${total_size}"
    
    if (( total_size > 1073741824 )); then
        display_size=$(( (total_size + 536870912) / 1073741824 ))
        size_unit="GB"
    elif (( total_size > 1048576 )); then
        display_size=$(( (total_size + 524288) / 1048576 ))
        size_unit="MB"
    elif (( total_size > 1024 )); then
        display_size=$(( (total_size + 512) / 1024 ))
        size_unit="KB"
    fi
    
    printf "%b%-40s %8d %s%b\n" \
        "${COLOR_BLUE}" \
        "Total mailbox storage:" \
        "${display_size}" \
        "${size_unit}" \
        "${COLOR_RESET}"
    echo "================================"
}

# Main execution
main() {
    generate_report "$@"
}

# Run main function
main "$@"
