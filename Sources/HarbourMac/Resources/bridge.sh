#!/bin/bash
set -euo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$BASE/Engine"
[[ "$EUID" -ne 0 ]] || { echo '請以正常使用者開啟 Harbour。' >&2; exit 1; }
[[ "${HARBOUR_TOKEN:-}" =~ ^[A-Za-z0-9-]+$ ]] || exit 1
# Drop inherited switches that could change deletion mode, guards, config roots,
# dry-run or test behaviour. All action arguments are assigned below.
while IFS= read -r var; do
    case "$var" in MOLE_*|MO_*|BASH_ENV|ENV|CDPATH|XDG_CACHE_HOME) unset "$var" ;; esac
done < <(compgen -e)
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export TERM=dumb
export SUDO_ASKPASS="$BASE/askpass.sh"
source "$BASE/protocol.sh"
command_name="${1:-}"
shift || true
mode="${1:-preview}"
[[ "$mode" == preview || "$mode" == apply ]] || exit 2
shift || true
[[ "$mode" != preview ]] || export MOLE_DRY_RUN=1
setup_auth() {
    # Delegate password entry directly to sudo's native-dialog askpass process.
    request_sudo_access() { /usr/bin/sudo -A -v; }
}
case "$command_name" in
    clean|external)
        source "$ENGINE/bin/clean.sh"
        setup_auth
        if [[ "$command_name" == clean && "$mode" == preview ]]; then
            harbour_clean_preview_hook() { emit_harbour_clean_preview "$1"; }
        fi
        args=()
        [[ "$mode" != preview ]] || args+=(--dry-run)
        if [[ "$command_name" == external ]]; then
            [[ $# -eq 1 ]] || exit 2
            args+=(--external "$1")
        elif [[ "${HARBOUR_ADMIN:-0}" == 1 ]]; then
            ensure_sudo_session '系統清理' || { echo '未獲管理員授權；操作已取消。' >&2; exit 1; }
        fi
        if [[ "$mode" == apply ]]; then
            harbour_confirm '執行清理；Mole 會按目前狀態重新驗證目標，快取及垃圾桶內容可能永久刪除' || exit 130
        fi
        main "${args[@]+"${args[@]}"}"
        ;;
    optimize)
        source "$ENGINE/bin/optimize.sh"; setup_auth
        if [[ "$mode" == apply ]]; then
            harbour_confirm '執行系統維護；可能重新整理 Finder、DNS 及系統服務' || exit 130
            main
        else main --dry-run; fi
        ;;
    uninstall)
        source "$ENGINE/bin/uninstall.sh"; setup_auth
        export MOLE_CURRENT_COMMAND=uninstall MOLE_DELETE_MODE=trash
        log_operation_session_start uninstall
        inventory="$(scan_applications)" || exit 1
        load_applications "$inventory" || exit 1
        harbour_event begin '選擇 App' '由同一次掃描的精確路徑選取；不使用模糊名稱匹配'
        for ((i=0; i<${#apps_data[@]}; i++)); do
            IFS='|' read -r epoch path name bundle size last rest <<< "${apps_data[i]}"
            harbour_event row "$i" "$name" "$path" "$size · $bundle" false
        done
        harbour_event select
        harbour_selection_reply "${#apps_data[@]}" || exit 130
        selected_apps=()
        IFS=',' read -r -a indices <<< "$HARBOUR_SELECTION"
        for i in "${indices[@]}"; do selected_apps+=("${apps_data[i]}"); done
        batch_uninstall_applications
        ;;
    installer)
        source "$ENGINE/bin/installer.sh"; setup_auth
        show_installer_menu() {
            harbour_event begin '選擇安裝檔' '永久刪除所選 DMG、PKG、ISO、XIP 或安裝 ZIP'
            local i
            for ((i=0; i<${#INSTALLER_PATHS[@]}; i++)); do
                harbour_event row "$i" "${INSTALLER_PATHS[i]##*/}" "${INSTALLER_PATHS[i]}" "${INSTALLER_SIZES[i]} bytes · ${INSTALLER_SOURCES[i]}" false
            done
            harbour_event select
            harbour_selection_reply "${#INSTALLER_PATHS[@]}" || return 1
            MOLE_SELECTION_RESULT="$HARBOUR_SELECTION"
        }
        if [[ "$mode" == preview ]]; then main --dry-run; else main; fi
        ;;
    purge)
        source "$ENGINE/bin/purge.sh"; setup_auth
        if [[ "$mode" == preview ]]; then main --dry-run; else main; fi
        ;;
    touchid)
        [[ $# -eq 1 && ( "$1" == enable || "$1" == disable || "$1" == status ) ]] || exit 2
        source "$ENGINE/bin/touchid.sh"; setup_auth
        if [[ "$mode" == apply && "$1" != status ]]; then harbour_confirm '修改 Touch ID sudo 設定；只適用配備 Touch ID 的 Mac' || exit 130; fi
        main "$1"
        ;;
    remove)
        source "$ENGINE/lib/core/common.sh"; setup_auth
        source "$ENGINE/lib/manage/remove.sh"
        if [[ "$mode" == preview ]]; then remove_mole true; else remove_mole false; fi
        ;;
    whitelist)
        [[ $# -ge 1 && ( "$1" == clean || "$1" == optimize ) ]] || exit 2
        kind="$1"; shift
        source "$ENGINE/lib/manage/whitelist.sh"
        if [[ "$mode" == preview ]]; then
            load_whitelist "$kind"
            text="$(printf '%s\n' "${CURRENT_WHITELIST_PATTERNS[@]+"${CURRENT_WHITELIST_PATTERNS[@]}"}")"
            harbour_event config "$text"
        else
            save_whitelist_patterns "$kind" "$@"
            echo '白名單已儲存。'
        fi
        ;;
    purgepaths)
        source "$ENGINE/lib/core/common.sh"
        source "$ENGINE/lib/clean/project.sh"
        if [[ "$mode" == preview ]]; then
            text=""
            [[ ! -f "$PURGE_CONFIG_FILE" ]] || text="$(cat "$PURGE_CONFIG_FILE")"
            harbour_event config "$text"
        else
            write_purge_config '# Harbour custom project scan directories' "$@"
            echo '掃描路徑已儲存。'
        fi
        ;;
    trash)
        [[ $# -gt 0 ]] || exit 2
        source "$ENGINE/lib/core/common.sh"
        export MOLE_DELETE_MODE=trash MOLE_CURRENT_COMMAND=analyze
        load_mole_whitelist
        ids=()
        for path in "$@"; do
            validate_path_for_deletion "$path" || exit 1
            identity="$(mole_path_identity "$path")"
            [[ -n "$identity" ]] || exit 1
            ids+=("$identity")
            printf '%s\n' "$path"
        done
        harbour_confirm '將以上精確路徑移到垃圾桶；系統受保護項目會被拒絕' || exit 130
        i=0; rc=0
        for path in "$@"; do
            mole_delete "$path" false "${ids[i]}" || rc=1
            i=$((i+1))
        done
        exit "$rc"
        ;;
    install)
        harbour_confirm '從 Mole 官方來源下載並安裝最新穩定 CLI 到 ~/.local/bin；Harbour 內置引擎版本不會被覆寫' || exit 130
        unset MOLE_DRY_RUN
        exec /bin/bash "$ENGINE/install.sh" --prefix "$HOME/.local/bin"
        ;;
    completion)
        [[ $# -eq 1 && ( "$1" == zsh || "$1" == bash || "$1" == fish ) ]] || exit 2
        exec /bin/bash "$ENGINE/mole" completion "$1"
        ;;
    *) echo '不支援的操作。' >&2; exit 2 ;;
esac
