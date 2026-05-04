#!/bin/bash
# SPDX-FileCopyrightText: Timothée Ravier <tim@siosm.fr>
# SPDX-License-Identifier: CC0-1.0

# The sections inside the if conditionals are intentionally not properly
# indented to make the heredoc blocks easier to read.

set -euxo pipefail

if [[ "${GPU_FAMILY}" == "generic" ]]; then
# Generic case, keep the defaults
exit 0
fi

if [[ "${GPU_FAMILY}" != "amd" ]]; then
cat > "/usr/lib/dracut/dracut.conf.d/20-omit-amd-gpu.conf" << 'EOF'
# Exclude AMD drivers
omit_drivers+=" amdgpu amdxcp radeon "
# Exclude AMD firmwares
remove_items+=" /usr/lib/firmware/amdgpu /usr/lib/firmware/radeon "
EOF
fi

if [[ "${GPU_FAMILY}" != "intel" ]]; then
cat > "/usr/lib/dracut/dracut.conf.d/20-omit-intel-gpu.conf" << 'EOF'
# Exclude Intel drivers
omit_drivers+=" gma500 i915 xe "
# Exclude Intel firmwares
remove_items+=" /usr/lib/firmware/i915 /usr/lib/firmware/xe "
EOF
fi

if [[ "${GPU_FAMILY}" != "nvidia" ]]; then
cat > "/usr/lib/dracut/dracut.conf.d/20-omit-nvidia-gpu.conf" << 'EOF'
# Exclude NVIDIA drivers
omit_drivers+=" nouveau "
# Exclude NVIDIA firmwares
remove_items+=" /usr/lib/firmware/nvidia "
EOF
fi

cat > "/usr/lib/dracut/dracut.conf.d/20-omit-misc-gpu.conf" << 'EOF'
# Exclude misc GPU drivers
omit_drivers+=" ast gud hyperv_drm mgag200 st7571-i2c st7586 st7735r ssd130x vboxvideo vkms vmwgfx "
EOF

cat > "/usr/lib/dracut/dracut.conf.d/20-virt-modules.conf" << 'EOF'
# Exclude virtualization support
omit_dracutmodules+=" qemu virtiofs "
EOF
