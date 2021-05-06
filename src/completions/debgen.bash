_debgen_comp ()
{
    if [ "$COMP_CWORD" != "1" ]; then
        COMPREPLY=($(compgen -f "${COMP_WORDS[$COMP_CWORD]}"))
    else
        COMPREPLY=($(compgen -W "help pc-debootstrap rpi-debootstrap chroot-exec chroot mklive-squashfs dump-default-pc-json dump-default-rpi-json dump-default-live-json pc-flash pc-flash-iso pc-flash-live rpi-flash rpi-flash-live" "${COMP_WORDS[$COMP_CWORD]}"))
    fi
}

complete -F _debgen_comp debgen
