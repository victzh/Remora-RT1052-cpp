#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
configuration="${1:-Debug}"

case "$configuration" in
    Debug|Release) ;;
    *)
        echo "Usage: $0 [Debug|Release]" >&2
        exit 2
        ;;
esac

"$script_dir/configure-flash-layout.sh"

if [[ -z "${MCUXPRESSO_CLI:-}" ]]; then
    mcuxpresso_ide="${MCUXPRESSO_IDE:-/Applications/MCUXpressoIDE_25.6.136/ide}"
    MCUXPRESSO_CLI="$mcuxpresso_ide/MCUXpressoIDE.app/Contents/MacOS/mcuxpressoide"
fi
if [[ ! -x "$MCUXPRESSO_CLI" ]]; then
    echo "MCUXpresso executable not found: $MCUXPRESSO_CLI" >&2
    echo "Set MCUXPRESSO_CLI to the headless-capable IDE executable." >&2
    exit 1
fi

if [[ -n "${MCUXPRESSO_WORKSPACE:-}" ]]; then
    workspace_dir="$MCUXPRESSO_WORKSPACE"
    mkdir -p "$workspace_dir"
else
    workspace_dir="$(mktemp -d "${TMPDIR:-/tmp}/remora-mcux-workspace.XXXXXX")"
fi

import_args=()
workspace_project="$workspace_dir/.metadata/.plugins/org.eclipse.core.resources/.projects/remora-rt1052-cpp"
if [[ ! -d "$workspace_project" ]]; then
    import_args=(-import "$project_dir")
fi

printf 'MCUXpresso workspace: %s\n' "$workspace_dir"
"$MCUXPRESSO_CLI" \
    -nosplash \
    -application org.eclipse.cdt.managedbuilder.core.headlessbuild \
    -data "$workspace_dir" \
    "${import_args[@]}" \
    -cleanBuild "remora-rt1052-cpp/$configuration"
