#!/usr/bin/env bash
################################################################################
# Z2Z - Pre-Flight DNS Diagnostic Utility
# Maintained by alsyundawy
# Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy
#
# Description:
#   Performs a comprehensive DNS health check for every active Zimbra domain
#   before migration. Validates:
#     - MX record existence and value
#     - SPF TXT record presence and softfail/hardfail policy
#     - DKIM public key TXT record (selector read from zmdkimkeyutil)
#     - DMARC _dmarc. TXT record presence and policy level
#     - Local resolver reachability (/etc/resolv.conf nameservers)
#   Outputs a color-coded summary report. Requires only dig and standard
#   Zimbra CLI tools. No external dependencies.
#
#   Compatible with ZCS 7.x through 10.1 and Carbonio CE.
#   Run as the zimbra user on either the source or destination server.
#
# Usage:
#   bash util/dns_diagnostic.sh [domain1 domain2 ...]
#   Without arguments: checks all domains known to Zimbra (zmprov gad).
#
# Version: 1.0.6
# License: CC BY-NC-SA / GPL
################################################################################

set -Eeuo pipefail

export LC_ALL='en_US.UTF-8'

# ============================================================================
# PATH setup
# ============================================================================

for _p in /opt/zimbra/bin /opt/zimbra/common/bin /opt/zimbra/common/sbin \
	/opt/zimbra/openldap/bin /opt/zimbra/postfix/sbin /opt/zimbra/mysql/bin; do
	if [[ -d "${_p}" ]] && [[ ":${PATH}:" != *":${_p}:"* ]]; then
		PATH="${_p}:${PATH}"
	fi
done
export PATH

# ============================================================================
# Color output helpers
# ============================================================================

readonly COLOR_BLUE='\e[1;34m'
readonly COLOR_RED='\e[1;31m'
readonly COLOR_YELLOW='\e[1;33m'
readonly COLOR_GREEN='\e[1;32m'
readonly COLOR_CYAN='\e[1;36m'
readonly COLOR_RESET='\e[0m'

print_header() { printf "%b%s%b\n" "${COLOR_CYAN}"   "$*" "${COLOR_RESET}"; }
print_normal() { printf "%b%s%b\n" "${COLOR_BLUE}"   "$*" "${COLOR_RESET}"; }
print_error()  { printf "%b%s%b\n" "${COLOR_RED}"    "$*" "${COLOR_RESET}" >&2; }
print_info()   { printf "%b%s%b\n" "${COLOR_YELLOW}" "$*" "${COLOR_RESET}"; }
print_ok()     { printf "%b%s%b\n" "${COLOR_GREEN}"  "$*" "${COLOR_RESET}"; }

separator()      { echo "+++++++++++++++++++++++++++++++++++++++++++++++++"; }
separator_thin() { echo "-------------------------------------------------"; }

# ============================================================================
# Pre-flight: user and dependency checks
# ============================================================================

current_user="$(whoami 2>/dev/null || id -un)"
if [[ "${current_user}" != "zimbra" ]]; then
	print_error "ERROR: Must be run as the zimbra user."
	exit 1
fi

if ! type dig &>/dev/null; then
	print_error "ERROR: 'dig' command not found. Install bind-utils (RHEL/Rocky/Alma) or bind9-dnsutils/dnsutils (Debian/Ubuntu)."
	exit 1
fi

if [[ -f /opt/zimbra/bin/zmshutil ]]; then
	# shellcheck source=/dev/null
	source /opt/zimbra/bin/zmshutil
	zmsetvars
elif [[ -f ~/bin/zmshutil ]]; then
	# shellcheck source=/dev/null
	source ~/bin/zmshutil
	zmsetvars
else
	print_error "ERROR: Cannot source Zimbra environment (zmshutil not found)."
	exit 1
fi

# ============================================================================
# Domain list: from arguments or from Zimbra
# ============================================================================

print_header "Z2Z — Pre-Flight DNS Diagnostic"
separator

if (($# > 0)); then
	DOMAIN_LIST=("$@")
else
	mapfile -t DOMAIN_LIST < <(zmprov gad 2>/dev/null | sort || true)
fi

TOTAL_DOMAINS="${#DOMAIN_LIST[@]}"
print_info "Domains to check : ${TOTAL_DOMAINS}"
separator

# ============================================================================
# Local resolver reachability check
# ============================================================================

print_header "[ Local Resolver Check ]"
separator_thin

if [[ -f /etc/resolv.conf ]]; then
	while IFS= read -r RESOLVER_LINE; do
		if [[ "${RESOLVER_LINE}" =~ ^nameserver[[:space:]]+(.*) ]]; then
			NS_IP="${BASH_REMATCH[1]}"
			if dig "@${NS_IP}" +time=2 +tries=1 +noall +answer . NS &>/dev/null; then
				print_ok "  Resolver ${NS_IP} : REACHABLE"
			else
				print_error "  Resolver ${NS_IP} : UNREACHABLE"
			fi
		fi
	done < /etc/resolv.conf
else
	print_info "  /etc/resolv.conf not found — skipping resolver check."
fi
separator

# ============================================================================
# Per-domain check
# ============================================================================

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

for DOMAIN in "${DOMAIN_LIST[@]}"; do
	[[ -z "${DOMAIN}" ]] && continue

	print_header "[ ${DOMAIN} ]"
	separator_thin

	DOMAIN_PASS=0
	DOMAIN_WARN=0
	DOMAIN_FAIL=0

	# ---- MX record ----
	MX_DIRECT="$(dig "${DOMAIN}" MX +short 2>/dev/null | head -n 3 || true)"
	if [[ -n "${MX_DIRECT}" ]]; then
		print_ok   "  MX       : FOUND"
		print_info "             ${MX_DIRECT}"
		((DOMAIN_PASS++)) || true
	else
		print_error "  MX       : NOT FOUND"
		((DOMAIN_FAIL++)) || true
	fi

	# ---- SPF record ----
	SPF_RESULT="$(dig TXT "${DOMAIN}" +short 2>/dev/null | grep 'v=spf1' | head -n 1 | tr -d '"' || true)"
	if [[ -n "${SPF_RESULT}" ]]; then
		if echo "${SPF_RESULT}" | grep -q '\-all'; then
			print_ok   "  SPF      : FOUND (hard fail -all)"
		elif echo "${SPF_RESULT}" | grep -q '~all'; then
			print_ok   "  SPF      : FOUND (soft fail ~all)"
		else
			print_info "  SPF      : FOUND (no explicit fail policy)"
			((DOMAIN_WARN++)) || true
		fi
		print_info "             ${SPF_RESULT}"
		((DOMAIN_PASS++)) || true
	else
		print_error "  SPF      : NOT FOUND"
		((DOMAIN_FAIL++)) || true
	fi

	# ---- DKIM record ----
	# Try to read selector from zmdkimkeyutil; fall back gracefully.
	DKIM_SELECTOR=""
	DKIM_KEYUTIL="/opt/zimbra/libexec/zmdkimkeyutil"
	if [[ -x "${DKIM_KEYUTIL}" ]]; then
		DKIM_SELECTOR="$(
			"${DKIM_KEYUTIL}" -q -d "${DOMAIN}" 2>/dev/null |
				grep -i 'selector' |
				head -n 1 |
				awk '{print $NF}' || true
		)"
	fi

	if [[ -n "${DKIM_SELECTOR}" ]]; then
		DKIM_RECORD="${DKIM_SELECTOR}._domainkey.${DOMAIN}"
		DKIM_RESULT="$(dig TXT "${DKIM_RECORD}" +short 2>/dev/null | head -n 1 | tr -d '"' || true)"
		if [[ -n "${DKIM_RESULT}" ]]; then
			print_ok   "  DKIM     : FOUND (selector=${DKIM_SELECTOR})"
			((DOMAIN_PASS++)) || true
		else
			print_error "  DKIM     : KEY NOT IN DNS (selector=${DKIM_SELECTOR})"
			((DOMAIN_FAIL++)) || true
		fi
	else
		print_info "  DKIM     : Selector unknown (zmdkimkeyutil returned nothing or not configured)"
		((DOMAIN_WARN++)) || true
	fi

	# ---- DMARC record ----
	DMARC_RESULT="$(dig TXT "_dmarc.${DOMAIN}" +short 2>/dev/null | head -n 1 | tr -d '"' || true)"
	if [[ -n "${DMARC_RESULT}" ]]; then
		if echo "${DMARC_RESULT}" | grep -q 'p=reject'; then
			print_ok   "  DMARC    : FOUND (p=reject)"
		elif echo "${DMARC_RESULT}" | grep -q 'p=quarantine'; then
			print_ok   "  DMARC    : FOUND (p=quarantine)"
		else
			print_info "  DMARC    : FOUND (p=none — monitoring only)"
			((DOMAIN_WARN++)) || true
		fi
		print_info "             ${DMARC_RESULT}"
		((DOMAIN_PASS++)) || true
	else
		print_error "  DMARC    : NOT FOUND"
		((DOMAIN_FAIL++)) || true
	fi

	((PASS_COUNT += DOMAIN_PASS)) || true
	((WARN_COUNT += DOMAIN_WARN)) || true
	((FAIL_COUNT += DOMAIN_FAIL)) || true

	separator
done

# ============================================================================
# Final summary report
# ============================================================================

print_header "[ DNS Diagnostic Summary ]"
separator_thin
print_info   "Domains checked : ${TOTAL_DOMAINS}"
print_ok     "Checks passed   : ${PASS_COUNT}"
print_info   "Warnings        : ${WARN_COUNT}"
print_error  "Checks failed   : ${FAIL_COUNT}"
separator

if ((FAIL_COUNT > 0)); then
	print_error "ACTION REQUIRED: Fix the failed DNS checks before migrating."
	print_info  "Missing DNS records will cause mail delivery failures after cutover."
else
	print_ok    "All critical DNS checks passed. Proceed with migration."
fi

separator
