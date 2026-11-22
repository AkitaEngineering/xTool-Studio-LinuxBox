#!/usr/bin/env fish
# Copyright (c) 2026 Akita Engineering
# SPDX-License-Identifier: GPL-3.0-only
# Portions copyright (c) 2026 Sascha Schüller, MIT. See LICENSES/MIT.txt.

set script_dir (dirname (status filename))
set bash_script "$script_dir/install.sh"

if not type -q bash
    echo "ERROR: bash is required to run xTool Studio LinuxBox."
    exit 1
end

if not test -f "$bash_script"
    echo "ERROR: install.sh was not found next to this Fish wrapper."
    exit 1
end

exec bash "$bash_script" $argv
