#!/bin/env zsh
0="${ZERO:-${${0:#$ZSH_ARGZERO}:-${(%):-%N}}}"
0="${ZERO:-${${${(M)${0::=${(%):-%x}}:#/*}:-$PWD/$0}:A}}"
local ZERO="$0"

if [[ ${zsh_loaded_plugins[-1]} != */zramdisk && -z ${fpath[(r)${0:h}]} ]] {
    fpath+=( "${0:h}" )
}

if [[ $PMSPEC != *f* ]] {
    fpath+=( "${0:h}/functions" )
}

source ${0:A:h}/zramdisk.zsh

