#!/usr/bin/env bash
################################################################################
# Z2Z Helper Functions Library
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
#
# Version: 1.0.4
# License: CC BY-NC-SA / GPL
################################################################################

set -Eeuo pipefail

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
	y | Y | yes | s | S | sim)
		print_normal "Starting utility"
		;;
	n | N | no | nao)
		exit 0
		;;
	*)
		test_exec
		;;
	esac
}

# Portable in-place string replacement
portable_replace() {
	local search_str="$1"
	local replace_str="$2"
	local target_file="$3"

	if [[ ! -f "${target_file}" ]]; then
		return 0
	fi

	local tmp_file
	tmp_file="$(mktemp "${target_file}.tmp.XXXXXX")"
	sed "s|${search_str}|${replace_str}|g" "${target_file}" >"${tmp_file}"
	mv -f "${tmp_file}" "${target_file}"
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
	local current_user
	current_user="$(whoami 2>/dev/null || id -un)"
	if [[ "${current_user}" != "zimbra" ]]; then
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

	if ((mailbox_servers > 1)); then
		print_error "WARNING: Current version is designed for single server or single mailbox environments."
		print_error "WARNING: For environments with multiple mailbox servers, manual modifications may be required."
	else
		print_normal "OK: Environment has single mailbox server."
	fi
}

# ============================================================================
# LDAP URI & Credential Resolvers
# ============================================================================

get_ldap_uri() {
	local hostname="$1"
	# shellcheck disable=SC2154
	local configured_url="${ldap_url:-${ldap_master_url:-}}"

	if [[ -n "${configured_url}" ]]; then
		# Extract first URL from multi-URI string
		echo "${configured_url}" | awk '{print $1}'
	elif [[ -n "${hostname}" ]]; then
		echo "ldap://${hostname}"
	else
		echo "ldap://localhost:389"
	fi
}

get_ldap_credential() {
	# shellcheck disable=SC2154
	if [[ -n "${zimbra_ldap_password:-}" ]]; then
		echo "${zimbra_ldap_password}"
	else
		zmlocalconfig -s -m nokey zimbra_ldap_password 2>/dev/null || echo ""
	fi
}

get_ldap_binddn() {
	local fallback_dn="$1"
	# shellcheck disable=SC2154
	if [[ -n "${zimbra_ldap_userdn:-}" ]]; then
		echo "${zimbra_ldap_userdn}"
	elif [[ -n "${fallback_dn}" ]]; then
		echo "${fallback_dn}"
	else
		zmlocalconfig -s -m nokey zimbra_ldap_userdn 2>/dev/null || echo "uid=zimbra,cn=admins,cn=zimbra"
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

	if ((fqdn_parts < 2)); then
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
	y | Y | yes | s | S | sim)
		print_choice "Hostname will be changed."
		# shellcheck disable=SC2154
		local old_hostname="${zimbra_server_hostname:-}"
		if [[ -z "${old_hostname}" ]]; then
			old_hostname="$(zmhostname 2>/dev/null || hostname -f 2>/dev/null || echo "")"
		fi
		enter_new_hostname
		if [[ -n "${old_hostname}" && -n "${NEW_HOSTNAME:-}" ]]; then
			portable_replace "${old_hostname}" "${NEW_HOSTNAME}" "${destino}/DOMINIOS.ldif"
			portable_replace "${old_hostname}" "${NEW_HOSTNAME}" "${destino}/CONTAS.ldif"
			portable_replace "${old_hostname}" "${NEW_HOSTNAME}" "${destino}/LISTAS.ldif"
			portable_replace "${old_hostname}" "${NEW_HOSTNAME}" "${destino}/APELIDOS.ldif"
			portable_replace "${old_hostname}" "${NEW_HOSTNAME}" "${destino}/COS.ldif"
			portable_replace "${old_hostname}" "${NEW_HOSTNAME}" "${destino}/CONFIG_GLOBAL.ldif"
			portable_replace "${old_hostname}" "${NEW_HOSTNAME}" "${destino}/create_domains.sh"
			print_info "Hostname replacement completed across all LDIF exports and scripts."
		else
			print_error "WARNING: Hostname replacement skipped due to missing hostname variable."
		fi
		;;
	n | N | no | nao)
		print_choice "Original server hostname will be maintained."
		;;
	*)
		replace_hostname "${destino}"
		;;
	esac
}

# ============================================================================
# Mailbox Export Configuration & Filtering
# ============================================================================

# Global filter settings
MAILBOX_FILTER_MODE="all"
MAILBOX_FILTER_VALUE=""

# Prompt whether to export mailboxes and configure filtering mode
export_mailboxes() {
	local choice
	read -r -p "Export mailboxes (yes/no)? " choice
	case "${choice}" in
	y | Y | yes | s | S | sim)
		print_choice "Mailbox export enabled."
		echo ""
		print_info "Select mailbox filter mode:"
		echo "  1) All non-system accounts (Default)"
		echo "  2) Active accounts only (zimbraAccountStatus=active)"
		echo "  3) Specific domain only"
		read -r -p "Enter choice [1-3] (default: 1): " filter_choice
		case "${filter_choice}" in
		2)
			MAILBOX_FILTER_MODE="active"
			print_choice "Filter set: Active accounts only."
			;;
		3)
			MAILBOX_FILTER_MODE="domain"
			read -r -p "Enter domain name to export (e.g. example.com): " MAILBOX_FILTER_VALUE
			while [[ -z "${MAILBOX_FILTER_VALUE}" ]]; do
				read -r -p "Domain cannot be empty. Enter domain name: " MAILBOX_FILTER_VALUE
			done
			print_choice "Filter set: Domain '${MAILBOX_FILTER_VALUE}' only."
			;;
		*)
			MAILBOX_FILTER_MODE="all"
			print_choice "Filter set: All non-system accounts."
			;;
		esac
		;;
	n | N | no | nao)
		print_choice "Mailbox export skipped. Execution aborted by user."
		exit 0
		;;
	*)
		export_mailboxes
		;;
	esac
}

# Retrieve filtered mailbox list
get_filtered_mailbox_list() {
	local raw_list=""
	case "${MAILBOX_FILTER_MODE}" in
	"active")
		raw_list="$(zmprov -l gaa -s active 2>/dev/null || zmprov -l gaa 2>/dev/null || true)"
		;;
	"domain")
		raw_list="$(zmprov -l gaa "${MAILBOX_FILTER_VALUE}" 2>/dev/null || true)"
		;;
	*)
		raw_list="$(zmprov -l gaa 2>/dev/null || true)"
		;;
	esac

	# Filter out system accounts, resources, spam/ham, and galsync
	echo "${raw_list}" | grep -v -E "^(virus-[^@]*|ham\.[^@]*|spam\.[^@]*|galsync[^@]*)@" || true
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

# Export Domains from LDAP & Generate Companion Provisioning Script
export_domains() {
	local hostname="$1"
	local binddn="$2"
	local destino="$3"
	local ldap_auth_token
	ldap_auth_token="$(get_ldap_credential)"
	local ldap_uri
	ldap_uri="$(get_ldap_uri "${hostname}")"
	local actual_binddn
	actual_binddn="$(get_ldap_binddn "${binddn}")"

	print_normal "EXPORTING EMAIL DOMAINS"
	separator_char

	ldapsearch -x \
		-H "${ldap_uri}" \
		-D "${actual_binddn}" \
		-w "${ldap_auth_token}" \
		-b '' \
		-LLL "(objectclass=zimbraDomain)" >"${destino}/DOMINIOS.ldif" || {
		print_error "ERROR: Failed to export domains"
		exit 1
	}

	# Generate companion create_domains.sh helper script
	local create_domains_script="${destino}/create_domains.sh"
	cat <<'EOF' >"${create_domains_script}"
#!/usr/bin/env bash
################################################################################
# Z2Z Domain Provisioning Helper Script
# Creates all migrated domains on destination Zimbra server
################################################################################
set -euo pipefail

log_msg() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_msg "Provisioning email domains on target Zimbra server..."
EOF

	local domain_list
	domain_list="$(zmprov gad 2>/dev/null || true)"
	while IFS= read -r dom; do
		[[ -z "${dom}" ]] && continue
		cat <<EOF >>"${create_domains_script}"
if zmprov gd '${dom}' &>/dev/null; then
	log_msg "Domain '${dom}' already exists. Skipping."
else
	log_msg "Creating domain '${dom}'..."
	zmprov cd '${dom}' || log_msg "WARNING: Failed to create domain '${dom}'"
fi
EOF
	done <<<"${domain_list}"

	chmod +x "${create_domains_script}"
	print_info "EMAIL DOMAINS exported successfully: ${destino}/DOMINIOS.ldif & create_domains.sh"
}

# Export Global Configuration & MTA Settings Snapshot
export_global_config() {
	local hostname="$1"
	local binddn="$2"
	local destino="$3"
	local ldap_auth_token
	ldap_auth_token="$(get_ldap_credential)"
	local ldap_uri
	ldap_uri="$(get_ldap_uri "${hostname}")"
	local actual_binddn
	actual_binddn="$(get_ldap_binddn "${binddn}")"

	print_normal "EXPORTING GLOBAL CONFIGURATION & MTA SETTINGS"
	separator_char

	ldapsearch -x \
		-H "${ldap_uri}" \
		-D "${actual_binddn}" \
		-w "${ldap_auth_token}" \
		-b '' \
		-LLL "(objectclass=zimbraGlobalConfig)" >"${destino}/CONFIG_GLOBAL.ldif" || {
		print_error "WARNING: Could not export global config object via LDAP"
	}

	# Snapshot key global settings
	local snapshot_file="${destino}/global_settings_snapshot.txt"
	local current_date
	current_date="$(date +'%Y-%m-%d %H:%M:%S')"
	local relay_host
	relay_host="$(zmprov gacf zimbraMtaRelayHost 2>/dev/null | head -n 1 || echo "None")"
	local my_networks
	my_networks="$(zmprov gacf zimbraMtaMyNetworks 2>/dev/null | head -n 1 || echo "None")"
	local mta_restriction
	mta_restriction="$(zmprov gacf zimbraMtaRestriction 2>/dev/null || echo "None")"
	local dns_lookups
	dns_lookups="$(zmprov gacf zimbraMtaDnsLookupsEnabled 2>/dev/null | head -n 1 || echo "TRUE")"
	local auth_mech
	auth_mech="$(zmprov gacf zimbraAuthMech 2>/dev/null | head -n 1 || echo "zimbra")"
	local gal_mode
	gal_mode="$(zmprov gacf zimbraGalMode 2>/dev/null | head -n 1 || echo "zimbra")"

	cat <<EOF >"${snapshot_file}"
# Zimbra Global Configuration & MTA Settings Snapshot
# Exported on: ${current_date}
# Source Hostname: ${hostname}

[ZIMBRA MTA SETTINGS]
zimbraMtaRelayHost: ${relay_host}
zimbraMtaMyNetworks: ${my_networks}
zimbraMtaRestriction: ${mta_restriction}
zimbraMtaDnsLookupsEnabled: ${dns_lookups}

[AUTH & GENERAL]
zimbraAuthMech: ${auth_mech}
zimbraGalMode: ${gal_mode}
EOF

	print_info "GLOBAL CONFIGURATION exported: ${destino}/CONFIG_GLOBAL.ldif & global_settings_snapshot.txt"
}

# Export Class of Service (COS) from LDAP
export_cos() {
	local hostname="$1"
	local binddn="$2"
	local destino="$3"
	local ldap_auth_token
	ldap_auth_token="$(get_ldap_credential)"
	local ldap_uri
	ldap_uri="$(get_ldap_uri "${hostname}")"
	local actual_binddn
	actual_binddn="$(get_ldap_binddn "${binddn}")"

	print_normal "EXPORTING CLASS OF SERVICE"
	separator_char

	ldapsearch -x \
		-H "${ldap_uri}" \
		-D "${actual_binddn}" \
		-w "${ldap_auth_token}" \
		-b '' \
		-LLL "(objectclass=zimbraCOS)" >"${destino}/COS.ldif" || {
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
	local ldap_auth_token
	ldap_auth_token="$(get_ldap_credential)"
	local ldap_uri
	ldap_uri="$(get_ldap_uri "${hostname}")"
	local actual_binddn
	actual_binddn="$(get_ldap_binddn "${binddn}")"

	print_normal "EXPORTING USER ACCOUNTS"
	separator_char

	# Filter out system accounts, resources, spam/ham training, virus quarantine, and galsync accounts
	ldapsearch -x \
		-H "${ldap_uri}" \
		-D "${actual_binddn}" \
		-w "${ldap_auth_token}" \
		-b '' \
		-LLL '(&(!(zimbraIsSystemResource=TRUE))(!(zimbraIsSystemAccount=TRUE))(!(uid=spam.*))(!(uid=ham.*))(!(uid=virus-quarantine.*))(!(uid=galsync*))(!(uid=zimbra))(!(uid=root))(objectClass=zimbraAccount))' >"${destino}/CONTAS.ldif" || {
		print_error "ERROR: Failed to export accounts"
		exit 1
	}

	print_info "USER ACCOUNTS exported successfully: ${destino}/CONTAS.ldif"
}

# Export mail aliases (high-speed single-pass atomic LDAP query)
export_aliases() {
	local hostname="$1"
	local binddn="$2"
	local destino="$3"
	local workdir="${4:-}"
	local ldap_auth_token
	ldap_auth_token="$(get_ldap_credential)"
	local ldap_uri
	ldap_uri="$(get_ldap_uri "${hostname}")"
	local actual_binddn
	actual_binddn="$(get_ldap_binddn "${binddn}")"

	print_normal "EXPORTING MAIL ALIASES"
	separator_char

	# Single-pass atomic export of all aliases excluding root and postmaster
	ldapsearch -x \
		-H "${ldap_uri}" \
		-D "${actual_binddn}" \
		-w "${ldap_auth_token}" \
		-b '' \
		-LLL '(&(!(uid=root))(!(uid=postmaster))(objectclass=zimbraAlias))' >"${destino}/APELIDOS.ldif" || {
		print_error "ERROR: Failed to export mail aliases"
		exit 1
	}

	# Clean legacy list if present
	if [[ -n "${workdir}" && -f "${workdir}/lista_contas.ldif" ]]; then
		rm -f "${workdir}/lista_contas.ldif"
	fi

	print_info "MAIL ALIASES exported successfully: ${destino}/APELIDOS.ldif"
}

# Export distribution lists
export_distribution_lists() {
	local hostname="$1"
	local binddn="$2"
	local destino="$3"
	local ldap_auth_token
	ldap_auth_token="$(get_ldap_credential)"
	local ldap_uri
	ldap_uri="$(get_ldap_uri "${hostname}")"
	local actual_binddn
	actual_binddn="$(get_ldap_binddn "${binddn}")"

	print_normal "EXPORTING DISTRIBUTION LISTS"
	separator_char

	ldapsearch -x \
		-H "${ldap_uri}" \
		-D "${actual_binddn}" \
		-w "${ldap_auth_token}" \
		-b '' \
		-LLL "(|(objectclass=zimbraGroup)(objectclass=zimbraDistributionList))" >"${destino}/LISTAS.ldif" || {
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

	# Initialize scripts with shebang and headers
	cat <<'EOF' >"${script_file}"
#!/usr/bin/env bash
################################################################################
# Z2Z Auto-Generated Mailbox Export Script (FULL)
# Executes zmmailbox getRestURL with no timeout (-t 0)
################################################################################
set -euo pipefail

TOTAL_ACCOUNTS=0
SUCCESS_COUNT=0
FAIL_COUNT=0

log_msg() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_msg "Starting Full Mailbox Export..."
EOF

	cat <<'EOF' >"${import_script}"
#!/usr/bin/env bash
################################################################################
# Z2Z Auto-Generated Mailbox Import Script (FULL)
# Executes zmmailbox postRestURL with resolve=skip
################################################################################
set -euo pipefail

TOTAL_ACCOUNTS=0
SUCCESS_COUNT=0
FAIL_COUNT=0

log_msg() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_msg "Starting Full Mailbox Import..."
EOF

	# Get filtered mailbox list
	local mailbox_list
	mailbox_list="$(get_filtered_mailbox_list)"

	local count=0
	local total
	total=$(echo "${mailbox_list}" | grep -c -v '^$' || echo 0)

	echo "TOTAL_ACCOUNTS=${total}" >>"${script_file}"
	echo "TOTAL_ACCOUNTS=${total}" >>"${import_script}"

	# Generate export/import commands
	while IFS= read -r mailbox; do
		[[ -z "${mailbox}" ]] && continue
		((count++))
		cat <<EOF >>"${script_file}"
log_msg "Exporting [${count}/${total}] ${mailbox}..."
if zmmailbox -z -m '${mailbox}' -t 0 getRestURL "//?fmt=tgz" > '${export_path}/${mailbox}.tgz'; then
	((SUCCESS_COUNT++))
else
	log_msg "ERROR: Failed to export ${mailbox}"
	((FAIL_COUNT++))
fi
EOF

		cat <<EOF >>"${import_script}"
log_msg "Importing [${count}/${total}] ${mailbox}..."
if [[ -f '${export_path}/${mailbox}.tgz' ]]; then
	if zmmailbox -z -m '${mailbox}' -t 0 postRestURL "//?fmt=tgz&resolve=skip" '${export_path}/${mailbox}.tgz'; then
		((SUCCESS_COUNT++))
	else
		log_msg "ERROR: Failed to import ${mailbox}"
		((FAIL_COUNT++))
	fi
else
	log_msg "WARNING: Archive not found: ${export_path}/${mailbox}.tgz"
	((FAIL_COUNT++))
fi
EOF
	done <<<"${mailbox_list}"

	cat <<'EOF' >>"${script_file}"
log_msg "Export completed. Total: ${TOTAL_ACCOUNTS}, Success: ${SUCCESS_COUNT}, Failed: ${FAIL_COUNT}"
EOF

	cat <<'EOF' >>"${import_script}"
log_msg "Import completed. Total: ${TOTAL_ACCOUNTS}, Success: ${SUCCESS_COUNT}, Failed: ${FAIL_COUNT}"
EOF

	chmod +x "${script_file}" "${import_script}"
}

# Build trash folder export script
execute_export_trash() {
	local export_path="$1"
	local workdir="$2"
	local script_file="${workdir}/script_export_TRASH.sh"
	local import_script="${workdir}/script_import_TRASH.sh"

	print_normal "TRASH: Creating mailbox trash export script:"
	print_info "${script_file}"

	cat <<'EOF' >"${script_file}"
#!/usr/bin/env bash
################################################################################
# Z2Z Auto-Generated Mailbox Trash Export Script
################################################################################
set -euo pipefail

TOTAL_ACCOUNTS=0
SUCCESS_COUNT=0
FAIL_COUNT=0

log_msg() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_msg "Starting Trash Mailbox Export..."
EOF

	cat <<'EOF' >"${import_script}"
#!/usr/bin/env bash
################################################################################
# Z2Z Auto-Generated Mailbox Trash Import Script
################################################################################
set -euo pipefail

TOTAL_ACCOUNTS=0
SUCCESS_COUNT=0
FAIL_COUNT=0

log_msg() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_msg "Starting Trash Mailbox Import..."
EOF

	local mailbox_list
	mailbox_list="$(get_filtered_mailbox_list)"

	local count=0
	local total
	total=$(echo "${mailbox_list}" | grep -c -v '^$' || echo 0)

	echo "TOTAL_ACCOUNTS=${total}" >>"${script_file}"
	echo "TOTAL_ACCOUNTS=${total}" >>"${import_script}"

	while IFS= read -r mailbox; do
		[[ -z "${mailbox}" ]] && continue
		((count++))
		cat <<EOF >>"${script_file}"
log_msg "Exporting Trash [${count}/${total}] ${mailbox}..."
if zmmailbox -z -m '${mailbox}' -t 0 getRestURL "//Trash?fmt=tgz" > '${export_path}/${mailbox}-Trash.tgz'; then
	((SUCCESS_COUNT++))
else
	log_msg "ERROR: Failed to export Trash for ${mailbox}"
	((FAIL_COUNT++))
fi
EOF

		cat <<EOF >>"${import_script}"
log_msg "Importing Trash [${count}/${total}] ${mailbox}..."
if [[ -f '${export_path}/${mailbox}-Trash.tgz' ]]; then
	if zmmailbox -z -m '${mailbox}' -t 0 postRestURL "//?fmt=tgz&resolve=skip" '${export_path}/${mailbox}-Trash.tgz'; then
		((SUCCESS_COUNT++))
	else
		log_msg "ERROR: Failed to import Trash for ${mailbox}"
		((FAIL_COUNT++))
	fi
else
	log_msg "WARNING: Archive not found: ${export_path}/${mailbox}-Trash.tgz"
	((FAIL_COUNT++))
fi
EOF
	done <<<"${mailbox_list}"

	cat <<'EOF' >>"${script_file}"
log_msg "Trash export completed. Total: ${TOTAL_ACCOUNTS}, Success: ${SUCCESS_COUNT}, Failed: ${FAIL_COUNT}"
EOF

	cat <<'EOF' >>"${import_script}"
log_msg "Trash import completed. Total: ${TOTAL_ACCOUNTS}, Success: ${SUCCESS_COUNT}, Failed: ${FAIL_COUNT}"
EOF

	chmod +x "${script_file}" "${import_script}"
}

# Build junk/spam folder export script
execute_export_junk() {
	local export_path="$1"
	local workdir="$2"
	local script_file="${workdir}/script_export_JUNK.sh"
	local import_script="${workdir}/script_import_JUNK.sh"

	print_normal "SPAM: Creating mailbox junk export script:"
	print_info "${script_file}"

	cat <<'EOF' >"${script_file}"
#!/usr/bin/env bash
################################################################################
# Z2Z Auto-Generated Mailbox Junk/Spam Export Script
################################################################################
set -euo pipefail

TOTAL_ACCOUNTS=0
SUCCESS_COUNT=0
FAIL_COUNT=0

log_msg() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_msg "Starting Junk/Spam Mailbox Export..."
EOF

	cat <<'EOF' >"${import_script}"
#!/usr/bin/env bash
################################################################################
# Z2Z Auto-Generated Mailbox Junk/Spam Import Script
################################################################################
set -euo pipefail

TOTAL_ACCOUNTS=0
SUCCESS_COUNT=0
FAIL_COUNT=0

log_msg() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_msg "Starting Junk/Spam Mailbox Import..."
EOF

	local mailbox_list
	mailbox_list="$(get_filtered_mailbox_list)"

	local count=0
	local total
	total=$(echo "${mailbox_list}" | grep -c -v '^$' || echo 0)

	echo "TOTAL_ACCOUNTS=${total}" >>"${script_file}"
	echo "TOTAL_ACCOUNTS=${total}" >>"${import_script}"

	while IFS= read -r mailbox; do
		[[ -z "${mailbox}" ]] && continue
		((count++))
		cat <<EOF >>"${script_file}"
log_msg "Exporting Junk [${count}/${total}] ${mailbox}..."
if zmmailbox -z -m '${mailbox}' -t 0 getRestURL "//Junk?fmt=tgz" > '${export_path}/${mailbox}-Junk.tgz'; then
	((SUCCESS_COUNT++))
else
	log_msg "ERROR: Failed to export Junk for ${mailbox}"
	((FAIL_COUNT++))
fi
EOF

		cat <<EOF >>"${import_script}"
log_msg "Importing Junk [${count}/${total}] ${mailbox}..."
if [[ -f '${export_path}/${mailbox}-Junk.tgz' ]]; then
	if zmmailbox -z -m '${mailbox}' -t 0 postRestURL "//?fmt=tgz&resolve=skip" '${export_path}/${mailbox}-Junk.tgz'; then
		((SUCCESS_COUNT++))
	else
		log_msg "ERROR: Failed to import Junk for ${mailbox}"
		((FAIL_COUNT++))
	fi
else
	log_msg "WARNING: Archive not found: ${export_path}/${mailbox}-Junk.tgz"
	((FAIL_COUNT++))
fi
EOF
	done <<<"${mailbox_list}"

	cat <<'EOF' >>"${script_file}"
log_msg "Junk export completed. Total: ${TOTAL_ACCOUNTS}, Success: ${SUCCESS_COUNT}, Failed: ${FAIL_COUNT}"
EOF

	cat <<'EOF' >>"${import_script}"
log_msg "Junk import completed. Total: ${TOTAL_ACCOUNTS}, Success: ${SUCCESS_COUNT}, Failed: ${FAIL_COUNT}"
EOF

	chmod +x "${script_file}" "${import_script}"
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
