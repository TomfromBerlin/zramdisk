#!/bin/env zsh
0="${ZERO:-${${0:#$ZSH_ARGZERO}:-${(%):-%N}}}"
0="${ZERO:-${${${(M)${0::=${(%):-%x}}:#/*}:-$PWD/$0}:A}}"

if [[ ${zsh_loaded_plugins[-1]} != */zramdisk && -z ${fpath[(r)${0:h}]} ]] {
    fpath+=( "${0:h}" )
}

if [[ $PMSPEC != *f* ]] {
    fpath+=( "${0:h}/functions" )
}
typeset -gA Plugins

Plugins[ZRAMDISK]="${0:h}"
typeset -g ZRAMDISK_PLUGIN_DIR="${0:A:h}"
typeset -g ZRAMDISK_FUNC_DIR="${ZRAMDISK_PLUGIN_DIR}/functions"

source ${0:A:h}/zramdisk.zsh
