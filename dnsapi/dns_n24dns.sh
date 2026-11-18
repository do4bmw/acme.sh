#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_n24dns_info='N24DNS.de
Site: n24dns.de
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_n24dns
Options:
 N24DNS_Token API Token
Issues: github.com/acmesh-official/acme.sh/issues/XXXX
Author: Benjamin Kaulfuss <support@n24dns.de>
'

N24DNS_API="https://n24dns.de/api/v1"

########  Public functions #####################

#Usage: dns_n24dns_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_n24dns_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Using N24DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _n24dns_load_token; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _n24dns_get_root "$fulldomain"; then
    _err "No matching zone found for $fulldomain in your N24DNS account."
    return 1
  fi
  _debug _zone_id "$_zone_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding TXT record"
  _data="{\"name\":\"$fulldomain\",\"type\":\"TXT\",\"content\":\"$txtvalue\",\"ttl\":300}"
  if ! _n24dns_rest POST "zones/$_zone_id/records" "$_data"; then
    _err "Could not add TXT record."
    return 1
  fi

  if _contains "$response" "\"id\":\""; then
    _info "TXT record added."
    return 0
  fi

  _err "Unexpected response while adding TXT record."
  _debug response "$response"
  return 1
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_n24dns_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Using N24DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _n24dns_load_token; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _n24dns_get_root "$fulldomain"; then
    _err "No matching zone found for $fulldomain in your N24DNS account."
    return 1
  fi
  _debug _zone_id "$_zone_id"

  if ! _n24dns_rest GET "zones/$_zone_id/records"; then
    _err "Could not list records."
    return 1
  fi

  _record_id=$(printf "%s" "$response" | _egrep_o "\{[^{}]*\}" | grep "\"name\":\"$fulldomain\"" | grep "\"type\":\"TXT\"" | grep -- "$txtvalue" | _egrep_o "\"id\":\"[^\"]*\"" | _head_n 1 | cut -d '"' -f 4)
  _debug _record_id "$_record_id"

  if [ -z "$_record_id" ]; then
    _info "TXT record not found, nothing to remove."
    return 0
  fi

  if ! _n24dns_rest DELETE "zones/$_zone_id/records/$_record_id"; then
    _err "Could not remove TXT record."
    return 1
  fi

  _info "TXT record removed."
  return 0
}

####################  Private functions below ##################################

_n24dns_load_token() {
  N24DNS_Token="${N24DNS_Token:-$(_readaccountconf_mutable N24DNS_Token)}"
  if [ -z "$N24DNS_Token" ]; then
    N24DNS_Token=""
    _err "You didn't specify a N24DNS API token yet."
    _err "Create one in the N24DNS customer portal (API-Tokens) and export N24DNS_Token."
    return 1
  fi
  _saveaccountconf_mutable N24DNS_Token "$N24DNS_Token"
  return 0
}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _zone_id=3f2b...
_n24dns_get_root() {
  domain=$1
  i=1
  p=1

  if ! _n24dns_rest GET "zones"; then
    return 1
  fi
  _zones="$response"

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    _zone=$(printf "%s" "$_zones" | _egrep_o "\{[^{}]*\"name\":\"$h\"[^{}]*\}")
    if [ "$_zone" ]; then
      _zone_id=$(printf "%s" "$_zone" | _egrep_o "\"id\":\"[^\"]*\"" | _head_n 1 | cut -d '"' -f 4)
      if [ -z "$_zone_id" ]; then
        return 1
      fi
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      _domain=$h
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

#Usage: method endpoint [data]
_n24dns_rest() {
  m=$1
  ep=$2
  data=$3
  _debug "$m" "$ep"

  export _H1="Authorization: Bearer $N24DNS_Token"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$N24DNS_API/$ep" "" "$m")"
  else
    response="$(_get "$N24DNS_API/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "Error calling $m $ep"
    return 1
  fi

  response="$(printf "%s" "$response" | _normalizeJson)"
  _debug2 response "$response"

  if _contains "$response" "\"error\":\"" || _contains "$response" "\"detail\":"; then
    _err "N24DNS API error: $response"
    return 1
  fi
  return 0
}
