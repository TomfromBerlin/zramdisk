##########################################################################
#                                                                        #
#     Everything below this line comes with no warranty of any kind.     #
#                 Use these file at your own risk!                       #
#                                                                        #
# project start: 2025-10 | first release: 2026-02 | last update: 2026-02 #
##########################################################################
#                                                                        #
# The MIT license applies to this and all related files.                 #
# If you want to modify, remix the code, or give it to your cat, this is #
# only possible under the terms of this license, and you must distribute #
# a copy of this license along with the remixed or modified code.        #
# Yes, even to your cat.                                                 #
#                                                                        #
# TomfromBerlin 2025-2026                                                #
##########################################################################
emulate -L zsh
setopt LOCALOPTIONS EXTENDED_GLOB TYPESET_SILENT RC_QUOTES no_auto_pushd
typeset -gA Plugins
Plugins[ZRAMDISK]="${0:h}"
typeset -g ZRAMDISK_PLUGIN_DIR="${0:A:h}"
typeset -g ZRAMDISK_FUNC_DIR="${ZRAMDISK_PLUGIN_DIR}/functions"
[[ -z $GIO_EXTRA_MODULES ]] && export GIO_EXTRA_MODULES=/usr/lib/x86_64-linux-gnu/gio/modules/

autoload -Uz is-at-least
if ! is-at-least 5.5; then
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_wrong_zsh_version" && zramdisk_wrong_zsh_version
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_plugin_unload" && zramdisk_plugin_unload
    return 1
fi

local cgroupfs2_exist
cgroupfs2_exist="$(stat -fc %T /sys/fs/cgroup)"
if  [[ "${cgroupfs2_exist}" != 'cgroup2fs' ]] ; then
    print -P '\n%F{red}╭─────────────────────────────────────────────╮%f' > /dev/tty
    print -P '%F{red}│%f ⚠️ zramdisk: Your kernel seems to be to old %F{red}│%f' > /dev/tty
    print -P '%F{red}│%f   %F{blue}cgroupfs2%f not available - Plugin disabled %F{red}│%f' > /dev/tty
    print -P '%F{red}╰─────────────────────────────────────────────╯%f\n' > /dev/tty
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_plugin_unload" && zramdisk_plugin_unload
    return 1
fi

local distro
if [[ -f /etc/os-release ]] ; then
    distro="$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr '[:upper:]' '[:lower:]')"

# Fallback lsb_release
elif [[ -z "${distro}" ]] && command -v lsb_release &>/dev/null ; then
    distro="$(lsb_release -si 2>/dev/null | tr '[:upper:]' '[:lower:]')"
fi

if [[  "${distro}" == Debian || "${distro}" == debian ]] ; then
    print -P '\n%F{red}╭─────────────────────────────────────────╮%f' > /dev/tty
    print -P '%F{red}│%f ⚠️ zramdisk: Not compatible with Debian %F{red}│%f' > /dev/tty
    print -P '%F{red}│%f %F{blue}zramctl%f not available - Plugin disabled %F{red}│%f' > /dev/tty
    print -P '%F{red}╰─────────────────────────────────────────╯%f\n' > /dev/tty
    unset distro
   {
        [[ -f "${ZRAMDISK_FUNC_DIR}/zramdisk_cleanup" ]] && source "${ZRAMDISK_FUNC_DIR}/zramdisk_cleanup"
        source "${ZRAMDISK_FUNC_DIR}/zramdisk_plugin_unload" && zramdisk_plugin_unload
    } 2>/dev/null 3>&2 2>&3 | cat > /dev/null  # Triple-redirect Voodoo

    return 1
fi

local emoji_font_paths=(
    /usr/share/fonts/noto-emoji/NotoColorEmoji.ttf
    /usr/share/fonts/noto/NotoColorEmoji.ttf
    /usr/share/fonts/google-noto-emoji-fonts
    /usr/share/fonts/truetype/noto/NotoColorEmoji.ttf
)

local found=0
for emoji_font in $emoji_font_paths; do
    if [[ -e $emoji_font ]]; then
        found=1
        break
    fi
done

if (( ! found )); then
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_font_missing" && zramdisk_font_missing
fi

if  ! command -v zramctl &>/dev/null ; then
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_zramctl_missing" && zramdisk_zramctl_missing
    unfunction -m zramdisk_zramctl_missing # Cleanup
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_plugin_unload" && zramdisk_plugin_unload
    return 1
else
    [[ -f "${ZRAMDISK_FUNC_DIR}/zramdisk_zram_available" ]] && source "${ZRAMDISK_FUNC_DIR}/zramdisk_zram_available" && zramdisk_zram_available
fi

# Check for other required tools
local -a missing_tools=()
local tools
for tools in awk chown date fstrim gdbus grep lsmod mkfs.ext4 mount umount readlink rm sed sleep sudo touch tput ; do
    if ! command -v "${tools}" &>/dev/null; then
        missing_tools+=("${tools}")
    fi
done

if (( ${#missing_tools[@]} > 0 )); then
    print -P "%F{red}Error: Missing required tools: ${missing_tools[*]}%f"
    unset missing_tools tools
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_plugin_unload" && zramdisk_plugin_unload
    return 1
fi

CG="/sys/fs/cgroup/user.slice/user-$UID.slice/user@$UID.service/zramdisk"
mkdir "$CG"
: ${XDG_STATE_HOME:=$HOME/.local/state}
STATEFILE="$XDG_STATE_HOME/zramdisk/state"
mkdir -p "${STATEFILE:h}"

RAM=$(awk '/MemTotal/ {print $2/1000/1000}' /proc/meminfo)
HIGH=$((RAM*40/100))
MAX=$((RAM/2))
echo $HIGH > "$CG/memory.high"
echo $MAX  > "$CG/memory.max"

TRAPWINCH() {
    zle && zle -R
}

typeset -g ZRAMDISK_LOADED=1

# Load UI helpers & default values
[[ -f "${ZRAMDISK_FUNC_DIR}/zramdisk_ui" ]] && source "${ZRAMDISK_FUNC_DIR}/zramdisk_ui"
[[ -f "${ZRAMDISK_FUNC_DIR}zramdisk_default_values" ]] && source "${ZRAMDISK_FUNC_DIR}/zramdisk_default_values"

# ────────────────────────────────────────────────────────────────
# Autoload core functions
# ────────────────────────────────────────────────────────────────
autoload -Uz zramdisk_ui zramdisk_menu zramdisk_zram_available zramdisk_default_values

# ────────────────────────────────────────────────────────────────
# Lazy-load (loading scripts on demand)
# ────────────────────────────────────────────────────────────────

zramdisk_animtex() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_animtex"
    zramdisk_animtex "$@"
}
zramdisk_benchmark() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_benchmark"
    zramdisk_benchmark "$@"
}
zramdisk_create() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_create"
    zramdisk_create "$@"
}
zramdisk_create_disk() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_create_disk"
    zramdisk_create_disk "$@"
}
zramdisk_current_choice() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_current_choice"
    zramdisk_current_choice "$@"
}
zramdisk_cleanup() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_cleanup"
    zramdisk_cleanup "$@"
}
zramdisk_config_found () {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_config_found"
    zramdisk_config_found "$@"
}
zramdisk_debug() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_debug"
    zramdisk_debug "$@"
}
zramdisk_determine_device() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_determine_device"
    zramdisk_determine_device "$@"
}
zramdisk_determine_mountpoint() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_determine_mountpoint"
    zramdisk_determine_mountpoint "$@"
}
zramdisk_diag() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_diag"
    zramdisk_diag "$@"
}
zramdisk_diagnose() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_diagnose"
    zramdisk_diagnose "$@"
}
zramdisk_error_list() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_error_list"
    zramdisk_error_list "$@"
}
zramdisk_find_unmounted_zram() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_find_unmounted_zram"
    zramdisk_find_unmounted_zram "$@"
}
zramdisk_prepare_mount() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_prepare_mount"
    zramdisk_prepare_mount "$@"
}
zramdisk_no_color() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_no_color"
    zramdisk_no_color "$@"
}
zramdisk_no_unit() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_size_func"
    zramdisk_no_unit "$@"
}
zramdisk_notify_me() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_notify_me"
    zramdisk_notify_me "$@"
}
zramdisk_parse_size_input() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_size_func"
    zramdisk_parse_size_input "$@"
}
zramdisk_perform_mount() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_perform_mount"
    zramdisk_perform_mount "$@"
}
zramdisk_plugin_unload() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_plugin_unload"
    zramdisk_plugin_unload "$@"
}
zramdisk_remove() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_remove"
    zramdisk_remove "$@"
}
zramdisk_restore_prompt() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_zramctl_missing"
    zramdisk_restore_prompt "$@"
}
zramdisk_select_alg() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_select_alg"
    zramdisk_select_alg "$@"
}
zramdisk_select_existing_device() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_select_existing_device"
    zramdisk_select_existing_device "$@"
}
zramdisk_setup() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_setup"
    zramdisk_setup "$@"
}
zramdisk_setup_success() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_setup_success"
    zramdisk_setup_success "$@"
}
zramdisk_size_func() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_size_func"
    zramdisk_size_func "$@"
}
zramdisk_troubleshooting() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_troubleshooting"
    zramdisk_troubleshooting "$@"
}
zramdisk_umount() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_umount"
    zramdisk_umount "$@"
}
zramdisk_validate_device() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_validate_device"
    zramdisk_validate_device "$@"
}
zramdisk_write_config() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_write_config"
    zramdisk_write_config "$@"
}
zramdisk_zramctl_missing() {
    source "${ZRAMDISK_FUNC_DIR}/zramdisk_zramctl_missing"
    zramdisk_zramctl_missing "$@"
}

# ────────────────────────────────────────────────────────────────
# Typewriter effect - just for fun
# Usage tpwrtr "Text string in double quotes!" <delay in sec>
# delay = how fast the text string will be written and deleted
# ────────────────────────────────────────────────────────────────
tpwrtr() {
zramdisk_debug "${ZRAMDISK_COLOR_GREEN}zramdisk_zramdisk.zsh:${ZRAMDISK_COLOR_NC} Reached function 'tpwrtr'." >&2
    tput civis
    local text="${1}"
    local delay="${2:-.02}"
    local i
    # Display $text
    for i in $(seq 0 $(expr length "${text}")) ; do
        echo -n "${text:$i:1}"
        sleep ${delay}
    done
    # How long the text should be displayed (in sec)
    sleep 1.3
    # then delete $text
    for i in $(seq 0 $(expr length "${text}")) ; do
        echo -ne "\b \b"
        sleep ${delay}
    done
    tput cnorm
}
# ────────────────────────────────────────────────────────────────
# Help
# ────────────────────────────────────────────────────────────────
zramdisk_help() {
zramdisk_debug "${ZRAMDISK_COLOR_GREEN}zramdisk_zramdisk.zsh:${ZRAMDISK_COLOR_NC} Reached function 'help'." >&2
    local -a title body footer msg
    local plugin_enabled

zramdisk_debug "${ZRAMDISK_COLOR_GREEN}zramdisk_zramdisk.zsh:${ZRAMDISK_COLOR_NC} Reached title." >&2
title=("zRAM Disk Plugin - Help")
zramdisk_debug "${ZRAMDISK_COLOR_GREEN}zramdisk_zramdisk.zsh:${ZRAMDISK_COLOR_NC} Reached body." >&2
body=("${ZRAMDISK_COLOR_GREEN}Usage:${ZRAMDISK_COLOR_CYAN} zramdisk${ZRAMDISK_COLOR_BLUE} menu
                ${ZRAMDISK_COLOR_GREY}─────────────────────────────────────────────────────
                ${ZRAMDISK_COLOR_BLUE}setup${ZRAMDISK_COLOR_GREY} → create a zRAM device
                ${ZRAMDISK_COLOR_BLUE}remove${ZRAMDISK_COLOR_GREY} → remove a zRAM device
                ${ZRAMDISK_COLOR_GREY}─────────────────────────────────────────────────────
                ${ZRAMDISK_COLOR_BLUE}mount${ZRAMDISK_COLOR_NC} | ${ZRAMDISK_COLOR_BLUE}on${ZRAMDISK_COLOR_GREY} → mount an existing zRAM device
                ${ZRAMDISK_COLOR_BLUE}umount ${ZRAMDISK_COLOR_NC} | ${ZRAMDISK_COLOR_BLUE}unmount${ZRAMDISK_COLOR_NC} | ${ZRAMDISK_COLOR_BLUE}off${ZRAMDISK_COLOR_GREY} → unmount a zRAM device
                ${ZRAMDISK_COLOR_GREY}─────────────────────────────────────────────────────
                ${ZRAMDISK_COLOR_BLUE}bench${ZRAMDISK_COLOR_GREY} → show benchmark results
                ${ZRAMDISK_COLOR_GREY}        (benchmark not actually performed)
                ${ZRAMDISK_COLOR_BLUE}error${ZRAMDISK_COLOR_GREY} → list of possible errors
                ${ZRAMDISK_COLOR_BLUE}trouble${ZRAMDISK_COLOR_GREY} → verbose troubleshooting
                ${ZRAMDISK_COLOR_GREY}─────────────────────────────────────────────────────
                ${ZRAMDISK_COLOR_BLUE}diag${ZRAMDISK_COLOR_GREY} → perform a diagnosis and display results
                ${ZRAMDISK_COLOR_BLUE}diag --dmsg${ZRAMDISK_COLOR_GREY} → show kernel logs
                ${ZRAMDISK_COLOR_BLUE}diag --services${ZRAMDISK_COLOR_GREY} → show systemd services
                ${ZRAMDISK_COLOR_BLUE}status${ZRAMDISK_COLOR_GREY} → same as above
                ${ZRAMDISK_COLOR_BLUE}diagnose ${ZRAMDISK_COLOR_GREY} → verbose text output of diagnostic results
                ${ZRAMDISK_COLOR_GREY}─────────────────────────────────────────────────────
                ${ZRAMDISK_COLOR_BLUE}debug on/off${ZRAMDISK_COLOR_GREY} → turn on/off debug mode
                ${ZRAMDISK_COLOR_BLUE}help${ZRAMDISK_COLOR_GREY} → display help
                ${ZRAMDISK_COLOR_GREY}─────────────────────────────────────────────────────
                ${ZRAMDISK_COLOR_BLUE}restore-prompt${ZRAMDISK_COLOR_GREY} → restore original prompt
                ${ZRAMDISK_COLOR_GREY}─────────────────────────────────────────────────────
"
    )
zramdisk_debug "${ZRAMDISK_COLOR_GREEN}zramdisk_zramdisk.zsh:${ZRAMDISK_COLOR_NC} Reached footer." >&2
footer=(
"${ZRAMDISK_COLOR_YELLOW}Example: ${ZRAMDISK_COLOR_BLUE}zramdisk remove${ZRAMDISK_COLOR_NC}
Press any key..."
)
zramdisk_debug "${ZRAMDISK_COLOR_GREEN}zramdisk_zramdisk.zsh:${ZRAMDISK_COLOR_NC} Reached msg." >&2
# msg=()
zramdisk_debug "${ZRAMDISK_COLOR_GREEN}zramdisk_zramdisk.zsh:${ZRAMDISK_COLOR_NC} Reached zramdisk_print_box." >&2

    zramdisk_print_box \
    "${title[@]}" \
    "${body[@]}" \
    "${footer[@]}"

    read -sk 1

    zramdisk_menu
}

# ────────────────────────────────────────────────────────────────
# Interactive Menu
# ────────────────────────────────────────────────────────────────
zramdisk_menu() {
zramdisk_debug "${ZRAMDISK_COLOR_GREEN}zramdisk_zramdisk.zsh:${ZRAMDISK_COLOR_NC} Reached function 'menu'." >&2
    local variables="{g,r,y,b,c,m,w,n,toggle}"
    local -a title body msg footer choice n_setting status_debug plugin_enabled zramdisk_color_{g,r,y,b,c,m,w,n,toggle}

    if [[ "${zramdisk_debug}" = 1 && -f "${ZRAMDISK_PLUGIN_DIR}/no_color" ]] ; then
        status_debug="${ZRAMDISK_COLOR_WHITE_FLASH}⚪${ZRAMDISK_COLOR_NC}"
    elif [[ "${zramdisk_debug}" = 1 && ! -f "${ZRAMDISK_PLUGIN_DIR}/no_color" ]] ; then
        status_debug="${ZRAMDISK_COLOR_WHITE_FLASH}🟢${ZRAMDISK_COLOR_NC}"
    elif
        [[ "${zramdisk_debug}" = 0 && -f "${ZRAMDISK_PLUGIN_DIR}/no_color" ]] ; then
        status_debug="⚫"
    elif
        [[ "${zramdisk_debug}" = 0  && ! -f "${ZRAMDISK_PLUGIN_DIR}/no_color" ]] ; then
        status_debug="🔴"
    fi
    
    if lsmod | grep -q '^zram'; then
        status_kernel="${ZRAMDISK_COLOR_GREEN}zram module loaded${ZRAMDISK_COLOR_NC}"
        menu_options="${ZRAMDISK_COLOR_YELLOW}Create / Setup zRAM${ZRAMDISK_COLOR_NC}"
    else
        status_kernel="zram kernel module ${ZRAMDISK_COLOR_RED}not${ZRAMDISK_COLOR_NC} loaded - press${ZRAMDISK_COLOR_BLUE} 1 ${ZRAMDISK_COLOR_NC} to load it"
        menu_options="${ZRAMDISK_COLOR_YELLOW}Load zram kernel module ${ZRAMDISK_COLOR_NC}with ${ZRAMDISK_COLOR_BLUE}sudo modprobe zram ${ZRAMDISK_COLOR_NC}"
    fi

    if [[ ! -f "${ZRAMDISK_PLUGIN_DIR}/no_color" ]]; then
        zramdisk_color_toggle="${ZRAMDISK_COLOR_YELLOW}Toggle${ZRAMDISK_COLOR_NC} Black & White"
    else
        zramdisk_color_g=$'\e[0;32m'
        zramdisk_color_r=$'\e[0;31m'
        zramdisk_color_y=$'\e[1;33m'
        zramdisk_color_b=$'\e[0;34m'
        zramdisk_color_c=$'\e[0;36m'
        zramdisk_color_m=$'\e[0;35m'
        zramdisk_color_n=$'\e[0m'
        zramdisk_color_toggle="Toggle ${zramdisk_color_y}c${zramdisk_color_b}o${zramdisk_color_g}l${zramdisk_color_r}o${zramdisk_color_m}r${zramdisk_color_c}s${zramdisk_color_n}"
    fi

    if [[ -f "${ZRAMDISK_PLUGIN_DIR}/zramdisk_notify_d" ]] ; then
        n_setting=$(echo "${ZRAMDISK_COLOR_GREEN}Desktop notification is on${ZRAMDISK_COLOR_NC}")
    elif [[ -f "${ZRAMDISK_PLUGIN_DIR}/zramdisk_notify_p" ]] ; then
        n_setting=$(echo "${ZRAMDISK_COLOR_GREEN}Prompt notification is on${ZRAMDISK_COLOR_NC}")
    else
        n_setting=$(echo "${ZRAMDISK_COLOR_GREY}Notification is off${ZRAMDISK_COLOR_NC}")
    fi

    if [[ ${zsh_loaded_plugins[-1]} != */zramdisk && -z ${fpath[(r)${0:h}]} && -f "${ZRAMDISK_PLUGIN_DIR}/no_color" ]]; then
        plugin_enabled="⚪"
    elif
        [[ ${zsh_loaded_plugins[-1]} != */zramdisk && -z ${fpath[(r)${0:h}]} && ! -f "${ZRAMDISK_PLUGIN_DIR}/no_color" ]] ; then
        plugin_enabled="🟢"
    elif
        [[ ${zsh_loaded_plugins[-1]} == */zramdisk && -z ${fpath[(r)${0:h}]} && -f "${ZRAMDISK_PLUGIN_DIR}/no_color" ]]; then
        plugin_enabled="⚫"
    elif
        [[ ${zsh_loaded_plugins[-1]} == */zramdisk && -z ${fpath[(r)${0:h}]} && ! -f "${ZRAMDISK_PLUGIN_DIR}/no_color" ]] ; then
        plugin_enabled="🔴"
    fi

title=(
"zRAM Disk Menu"
)

body=("
${ZRAMDISK_COLOR_CYAN} 1) ${menu_options}
${ZRAMDISK_COLOR_CYAN} 2) ${ZRAMDISK_COLOR_YELLOW}Remove zRAM disk(s)${ZRAMDISK_COLOR_NC}
${ZRAMDISK_COLOR_CYAN} 3) ${ZRAMDISK_COLOR_YELLOW}Mount zRAM device${ZRAMDISK_COLOR_NC}
${ZRAMDISK_COLOR_CYAN} 4) ${ZRAMDISK_COLOR_YELLOW}Unmount zRAM device${ZRAMDISK_COLOR_NC}
${ZRAMDISK_COLOR_CYAN} 5) ${ZRAMDISK_COLOR_YELLOW}Show plugin status & diagnostics${ZRAMDISK_COLOR_NC}
${ZRAMDISK_COLOR_CYAN} 6) ${ZRAMDISK_COLOR_YELLOW}Show some benchmark results${ZRAMDISK_COLOR_NC}
${ZRAMDISK_COLOR_GREY}    (benchmark not actually performed)${ZRAMDISK_COLOR_NC}
${ZRAMDISK_COLOR_CYAN} 7) ${ZRAMDISK_COLOR_YELLOW}Unload plugin${ZRAMDISK_COLOR_NC}
${ZRAMDISK_COLOR_CYAN} 8) ${ZRAMDISK_COLOR_YELLOW}Help${ZRAMDISK_COLOR_NC}
${ZRAMDISK_COLOR_CYAN} 0) ${ZRAMDISK_COLOR_YELLOW}Exit${ZRAMDISK_COLOR_NC}
${ZRAMDISK_COLOR_CYAN} c) ${zramdisk_color_toggle}
${ZRAMDISK_COLOR_CYAN} d) ${ZRAMDISK_COLOR_YELLOW}Debug On/Off ${ZRAMDISK_COLOR_NC}(Status: ${status_debug}${ZRAMDISK_COLOR_NC})
${ZRAMDISK_COLOR_CYAN} n) ${ZRAMDISK_COLOR_YELLOW}Notification settings ${ZRAMDISK_COLOR_NC}(${n_setting})${ZRAMDISK_COLOR_NC}
"
)

footer=("${ZRAMDISK_COLOR_GREEN}Info: ${ZRAMDISK_COLOR_YELLOW} [zramdisk]${ZRAMDISK_COLOR_NC} Plugin loaded: ${plugin_enabled}${ZRAMDISK_COLOR_NC}
${status_kernel}")

msg=(
"${ZRAMDISK_COLOR_NC}Select an option [0-8] or [d], [n], [c]${ZRAMDISK_COLOR_NC}"
)
zramdisk_print_box \
"${title[@]}" \
"${body[@]}" \
"${footer[@]}" \
"ask" \
"${msg[@]}"

    read -sk choice
    case "$choice" in
        1) if lsmod | grep -q '^zram'; then
              zramdisk_setup
           else
               sudo modprobe zram
               clear
               zramdisk_menu
           fi
           ;;
        2) zramdisk_remove ;;
        3) zramdisk_prepare_mount ;;
        4) zramdisk_umount ;;
        5) zramdisk_diag ;;
        6) zramdisk_benchmark ;;
        7) zramdisk_plugin_unload ;;
        8) zramdisk_help ;;
        0) tpwrtr "Hasta la vista, baby." .02 && return 0 ;;
        c) zramdisk_no_color ;;
        d)
            if (( zramdisk_debug )); then
                typeset -g zramdisk_debug=0
                clear
                zramdisk_menu
            else
                typeset -g zramdisk_debug=1
                clear
                zramdisk_menu
            fi
            ;;
        n) zramdisk_notify_me ;;

        *) tpwrtr "Invalid choice. Menu closed." .02 && return 0 ;;

    esac
}

# Dispatcher
zramdisk() {
zramdisk_debug "${ZRAMDISK_COLOR_GREEN}zramdisk_zramdisk.zsh:${ZRAMDISK_COLOR_NC} Reached function 'zramdisk'." >&2
    local cmd="${1:-}"
    (( $# )) && shift

    case "$cmd" in
        setup)                zramdisk_setup "$@" ;;
        remove)               zramdisk_remove "$@";;
        status)               zramdisk_diag "$@" ;;
        bench)                zramdisk_benchmark "$@" ;;
        on|mount)             zramdisk_prepare_mount "$@" ;;
        off|unmount|umount)   zramdisk_umount "$@" ;;
        debug)
            if [[ "$1" == "on" ]]; then
                typeset -g zramdisk_debug=1
                echo -e "${ZRAMDISK_COLOR_GREEN}[zramdisk]${ZRAMDISK_COLOR_WHITE_FLASH} Debug mode enabled${ZRAMDISK_COLOR_NC}"
            else
                typeset -g zramdisk_debug=0
                echo -e "${ZRAMDISK_COLOR_GREEN}[zramdisk]${ZRAMDISK_COLOR_NC} Debug mode disabled"
            fi
            ;;
        unload)               zramdisk_plugin_unload "$@" ;;
        help|--help)          zramdisk_help "$@" ;;
        menu)                 zramdisk_menu "$@" ;;
        error)                zramdisk_error_list "$@" ;;
        trouble)              zramdisk_troubleshooting "$@" ;;
        diag)                 zramdisk_diag "$@" ;;
        diagnose)             zramdisk_diagnose "$@" ;;
        restore-prompt)       zramdisk_restore_prompt "$@" && exec zsh ;;
        "")                   zramdisk_help ;;
    esac
}
#zramdisk_debug "${ZRAMDISK_COLOR_CYAN}zramdisk_zramdisk.zsh:${ZRAMDISK_COLOR_NC} Reached autocompletion" >&2

# (TODO|FIXME)\b Make the Autocompletion work
# ────────────────────────────────────────────────────────────────
# Autocompletion currently doesn't work.
# Any ideas? Leave a comment or pr at Github.
# ────────────────────────────────────────────────────────────────
# zramdisk_completion() {
#     local -a actions vars
#     actions=(on off status help setup menu mount unmount remove unload)
#     vars=(debug)
#     if (( CURRENT == 2 )); then
#         compadd -a actions
#     elif [[ ${words[2]} == debug ]]; then
#         compadd -a vars
#     fi
# }
# compdef zramdisk_completion zramdisk
# ZRAMDISK_SCRIPT
