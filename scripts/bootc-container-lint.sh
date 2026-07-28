#!/bin/bash
# SPDX-FileCopyrightText: Timothée Ravier <tim@siosm.fr>
# SPDX-License-Identifier: CC0-1.0

set -euxo pipefail

source /etc/os-release

declare -a args=()

if [[ "${NAME}" == "secureblue" ]]; then
    args+=(
        "--skip" "etc-usretc"
        "--skip" "nonempty-boot"
        "--skip" "nonempty-run-tmp"
    )
fi

if [[ "${NAME}" == "Bazzite" ]]; then
    args+=(
        "--skip" "nonempty-boot"
        "--skip" "sysusers"
    )
fi

bootc container lint --fatal-warnings --no-truncate "${args[@]}"
