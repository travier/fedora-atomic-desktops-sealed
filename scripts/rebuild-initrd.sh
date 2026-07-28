#!/bin/bash
# SPDX-FileCopyrightText: Timothée Ravier <tim@siosm.fr>
# SPDX-License-Identifier: CC0-1.0

set -euxo pipefail

kver=$(cd "/usr/lib/modules" && echo *)

# Workaround for secureblue
mkdir -p "/var/tmp"

dracut -vf --install "/etc/passwd /etc/group" "/initramfs" "$kver"
