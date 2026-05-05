#!/bin/bash
# SPDX-FileCopyrightText: Timothée Ravier <tim@siosm.fr>
# SPDX-License-Identifier: CC0-1.0

set -euxo pipefail

kver=$(cd "/usr/lib/modules" && echo *)

# Remove the initrd from the base image. We'll rebuilt it in a later stage for
# each GPU vendor target and include it in the UKI.
rm "/usr/lib/modules/$kver/initramfs.img"

# Remove the kernel from the base image as we made a copy in another stage. It
# will be included in the UKI in a later stage.
rm "/usr/lib/modules/$kver/vmlinuz"
