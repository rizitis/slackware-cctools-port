#!/bin/bash

sbo_txt_url="https://slackbuilds.org/slackbuilds/15.0/SLACKBUILDS.TXT"
sbo_txt_cache="/tmp/SLACKBUILDS.TXT"

SBSCRIPT="$(find "${BUILDDIR}" -maxdepth 1 -name '*.SlackBuild' | head -1)"
JUST_NAME=$(basename "$SBSCRIPT" .SlackBuild)
DEPS_FILE="$JUST_NAME".dep
LOCAL_DEPS="$DEPS_FILE"_local

build_local() {
echo "DEBUG: LOCAL_DEPS='$LOCAL_DEPS'"
    echo "DEBUG: test -f result: $(test -f "$LOCAL_DEPS" && echo EXISTS || echo NOT_FOUND)"
    echo "DEBUG: PWD=$(pwd)"
    cat "$LOCAL_DEPS"
    if [ ! -f "$LOCAL_DEPS" ]; then
        _log "no local deps found for $JUST_NAME"
    else
        while IFS= read -r local_dep_name || [ -n "$local_dep_name" ]; do
            tmp=$(mktemp -d)
            mkdir -p "$tmp/repo"
            cp "${local_dep_name}/${local_dep_name}.info" "${local_dep_name}/${local_dep_name}.SlackBuild" "$tmp/repo/"
            pushd "$tmp/repo" || exit 1
            source "${local_dep_name}.info"
            _log "Downloading source for ${local_dep_name}..."
            for url in $DOWNLOAD $DOWNLOAD_x86_64; do
                [ -z "$url" ] && continue
                curl -L "$url" -o "$(basename "$url")" \
                    || _err "Failed to download source for ${local_dep_name}: $url"
            done
            bash "${local_dep_name}.SlackBuild" || _err "${local_dep_name} build failed"
            _log "${local_dep_name} Build succeeded."
            _log "Installing ${local_dep_name}..."
            upgradepkg --install-new --reinstall /tmp/$PRGNAM-$VERSION-*.t?z
            ldconfig
            rm /tmp/$PRGNAM-$VERSION-*.t?z
            info_vars=$(grep -v '^#' "${local_dep_name}.info" | cut -d= -f1)
            popd || exit 1
            unset $info_vars
            rm -rf "$tmp"
            _log "All Done: ${local_dep_name}"
        done < "$LOCAL_DEPS"
    fi
}

fetch_sbo_txt() {
    if [[ ! -f "$sbo_txt_cache" ]]; then
        _log "Fetching SLACKBUILDS.TXT..."
        curl -sL "$sbo_txt_url" -o "$sbo_txt_cache"
    fi
}

if [ ! -f "$DEPS_FILE" ]; then
    _log "no deps found for $JUST_NAME"
    build_local
else
    build_local
    fetch_sbo_txt
    while IFS= read -r dep_name || [ -n "$dep_name" ]; do
        [ -z "$dep_name" ] && continue
        _log "Looking up '${dep_name}' in SBo..."
        location=$(grep -A5 "^SLACKBUILD NAME: ${dep_name}$" "$sbo_txt_cache" \
            | grep "^SLACKBUILD LOCATION:" | head -1 \
            | awk '{print $3}' | sed 's|^\./||')

        if [[ -z "$location" ]]; then
            _err "'${dep_name}' not found in SLACKBUILDS.TXT"
            _slk_detect_version
            if [[ "$SLK_VERSION" == "current" ]]; then
                _log "====== CHECK THIS LOG ======="
                _log " Maybe '${dep_name}' already in your current image?"
                _log " If not then should be mentioned on build_deps: in .yml file for installation"
                _log " We dont kill the build for now as it might be installed or run time dep,"
                _log " else it will kill it self soon..."
                _log "====== CHECK THIS LOG ======="
            fi
        fi

        _log "Found: ${location}"

        tmp=$(mktemp -d)
        git clone --depth=1 --filter=blob:none --sparse \
            https://github.com/Ponce/slackbuilds.git -b current "$tmp/repo" -q
        cd "$tmp/repo"
        git sparse-checkout set "$location"
        tar czf "${OLDPWD}/${dep_name}.tar.gz" -C "$tmp/repo/$location/.." "$dep_name"
        cd "$OLDPWD"
        rm -rf "$tmp"

        tar xf "${dep_name}.tar.gz" || true
        if [ ! -d "${dep_name}" ]; then
            continue
        fi
        pushd "${dep_name}" || exit 1
        unset PKG OUTPUT
        source "${dep_name}.info"
        _log "Downloading source for ${dep_name}..."
        for url in $DOWNLOAD $DOWNLOAD_x86_64; do
            [ -z "$url" ] && continue
            curl -L "$url" -o "$(basename "$url")" \
                || _err "Failed to download source for ${dep_name}: $url"
        done
        chmod +x "${dep_name}.SlackBuild"
        bash "${dep_name}.SlackBuild" || _err "${dep_name} build failed"
        _log "${dep_name} Build succeeded."
        _log "Installing ${dep_name}..."
        upgradepkg --install-new --reinstall /tmp/$PRGNAM-$VERSION-*.t?z
        rm /tmp/$PRGNAM-$VERSION-*.t?z
        info_vars=$(grep -v '^#' "${dep_name}.info" | cut -d= -f1)
        popd || exit 1
        unset $info_vars
        _log "All Done: ${dep_name}"
    done < "$DEPS_FILE"
fi
