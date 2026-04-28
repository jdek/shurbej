#!/bin/sh
# shurbej-admin — RPC into a running shurbej node from outside its unit.
#
# Sources the systemd EnvironmentFile (default /run/secrets/shurbej/env)
# so SHURBEJ_COOKIE matches the live node, and uses a private
# RELX_OUT_FILE_PATH so the eval invocation does not overwrite the
# running unit's vm.args / sys.config in /run/shurbej.

set -eu

usage() {
    cat <<EOF
Usage:
  shurbej-admin eval <erlang-expr>
  shurbej-admin list-users
  shurbej-admin create-user <username> <password> [user-id]
  shurbej-admin delete-user <username>
  shurbej-admin create-api-key <user-id> <name> [full|read_only|...]

Environment:
  SHURBEJ_ENV_FILE   Path to KEY=value file containing SHURBEJ_COOKIE
                     (default: /run/secrets/shurbej/env)
EOF
}

env_file=${SHURBEJ_ENV_FILE:-/run/secrets/shurbej/env}
if [ ! -r "$env_file" ]; then
    echo "shurbej-admin: cannot read env file $env_file" >&2
    exit 1
fi
set -a
# shellcheck disable=SC1090
. "$env_file"
set +a

RELX_OUT_FILE_PATH=$(mktemp -d -t shurbej-admin.XXXXXXXX)
export RELX_OUT_FILE_PATH
trap 'rm -rf "$RELX_OUT_FILE_PATH"' EXIT

# Encode a UTF-8 string as `base64:decode(<<"...">>)` so quotes,
# backslashes, or non-ascii bytes survive the eval round-trip without
# any shell-level escaping.
b() {
    enc=$(printf '%s' "$1" | base64 -w0)
    printf 'base64:decode(<<"%s">>)' "$enc"
}

launcher=$(dirname "$(readlink -f "$0")")/shurbej

cmd=${1:-}
[ $# -gt 0 ] && shift

case "$cmd" in
    eval)
        [ $# -eq 1 ] || { usage >&2; exit 2; }
        exec "$launcher" eval "$1"
        ;;
    list-users)
        [ $# -eq 0 ] || { usage >&2; exit 2; }
        exec "$launcher" eval 'shurbej_admin:list_users().'
        ;;
    create-user)
        case $# in
            2) exec "$launcher" eval "shurbej_admin:create_user($(b "$1"), $(b "$2"))." ;;
            3) exec "$launcher" eval "shurbej_admin:create_user($(b "$1"), $(b "$2"), $3)." ;;
            *) usage >&2; exit 2 ;;
        esac
        ;;
    delete-user)
        [ $# -eq 1 ] || { usage >&2; exit 2; }
        exec "$launcher" eval "shurbej_admin:delete_user($(b "$1"))."
        ;;
    create-api-key)
        case $# in
            2) exec "$launcher" eval "shurbej_admin:create_api_key($1, $(b "$2"))." ;;
            3) exec "$launcher" eval "shurbej_admin:create_api_key($1, $(b "$2"), $3)." ;;
            *) usage >&2; exit 2 ;;
        esac
        ;;
    -h|--help|help)
        usage
        ;;
    "")
        usage >&2
        exit 2
        ;;
    *)
        echo "shurbej-admin: unknown command: $cmd" >&2
        usage >&2
        exit 2
        ;;
esac
