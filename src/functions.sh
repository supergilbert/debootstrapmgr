echo_error ()
{
    echo "\033[31m$@\033[0m" >&2
}

echo_die ()
{
    EXIT_NUM=$1
    shift
    echo_error "$@"
    exit "$EXIT_NUM"
}

echo_notify ()
{
    echo "\033[1m$@\033[0m" >&2
}

cleanup ()
{
    echo "No cleanup function"
}

TRAP_LIST="INT TERM EXIT"

unset_trap ()
{
    trap - $TRAP_LIST
}

set_trap ()
{
    trap "set +e; echo_error 'Signal trapped'; unset_trap; $1; exit 1" $TRAP_LIST
}
