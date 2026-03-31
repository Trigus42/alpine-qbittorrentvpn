#!/bin/bash
# shellcheck shell=bash

CUSTOM_INIT_DIR="/custom-init"
CUSTOM_SERVICES_DIR="/custom-services"
S6_RC_DIR="/etc/s6-overlay/s6-rc.d"

process_components() {
    local source_dir=$1
    local bundle=$2

    if [[ -d "${source_dir}" ]] && [[ -n "$(/bin/ls -A "${source_dir}" 2>/dev/null)" ]]; then
        echo "[custom-s6] Processing components from ${source_dir}..."
        for component in "${source_dir}"/*; do
            if [[ -d "${component}" ]]; then
                local original_name
                original_name="$(basename "${component}")"
                local name="custom-${original_name}"
                local target="${S6_RC_DIR}/${name}"
                
                echo "[custom-s6] copying ${original_name} to s6-rc.d as ${name}..."
                cp -r "${component}" "${target}"
                
                # Auto-add executable permissions just in case
                [[ -f "${target}/run" ]] && chmod +x "${target}/run"
                [[ -f "${target}/up" ]] && chmod +x "${target}/up"
                [[ -f "${target}/down" ]] && chmod +x "${target}/down"
                
                # If it's a oneshot, s6-rc expects `up` to be an execline script.
                # If the user provided a bash/shell script with a shebang to `run`, we use it
                if [[ -f "${target}/type" ]] && [[ "$(cat "${target}/type")" == "oneshot" ]]; then
                    if [[ ! -f "${target}/up" ]] && [[ -f "${target}/run" ]]; then
                        echo "[custom-s6] Creating up wrapper for ${name} using run script..."
                        echo -e "/etc/s6-overlay/s6-rc.d/${name}/run" > "${target}/up"
                        chmod +x "${target}/up"
                    fi
                fi
                
                # Add it to the requested bundle
                mkdir -p "${S6_RC_DIR}/${bundle}/contents.d"
                touch "${S6_RC_DIR}/${bundle}/contents.d/${name}"
                echo "[custom-s6] ${name} added to ${bundle} bundle."
            fi
        done
    fi
}

process_components "${CUSTOM_INIT_DIR}" "init"
process_components "${CUSTOM_SERVICES_DIR}" "user"
