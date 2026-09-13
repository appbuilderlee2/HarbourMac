#!/bin/bash
# GUI transport only. No filesystem mutation helpers live here.
harbour_event() {
    local field
    printf '\n@@HARBOUR:%s\t%s' "$HARBOUR_TOKEN" "$1"
    shift
    for field in "$@"; do
        printf '\t'
        printf '%s' "$field" | /usr/bin/base64 | tr -d '\r\n'
    done
    printf '\n'
}
harbour_confirm() {
    local reply=""
    harbour_event confirm "$1"
    IFS= read -r reply || return 1
    [[ "$reply" == "CONFIRM" ]]
}
harbour_selection_reply() {
    local reply="" idx existing seen="," limit="$1"
    IFS= read -r reply || return 1
    [[ "$reply" =~ ^[0-9]+(,[0-9]+)*$ ]] || return 1
    local -a values=()
    IFS=',' read -r -a values <<< "$reply"
    for idx in "${values[@]}"; do
        [[ "$idx" == 0 || "$idx" != 0* ]] || return 1
        [[ ${#idx} -le 7 && "$idx" -lt "$limit" ]] || return 1
        [[ "$seen" != *",$idx,"* ]] || return 1
        seen="$seen$idx,"
    done
    HARBOUR_SELECTION="$reply"
}
harbour_select_purge() {
    local i
    harbour_event begin "選擇開發檔案" "只選擇可重建項目；最近使用及雲端項目預設不勾選"
    for ((i=0; i<${#item_paths[@]}; i++)); do
        local default=false
        [[ "${item_recent_flags[i]}" != true && "${item_cloud_flags[i]}" != true ]] && default=true
        harbour_event row "$i" "${menu_options[i]}" "${item_paths[i]}" "${item_sizes[i]} KB · ${item_age_labels[i]} · cloud:${item_cloud_flags[i]}" "$default"
    done
    harbour_event select
    harbour_selection_reply "${#item_paths[@]}" || return 1
    PURGE_SELECTION_RESULT="$HARBOUR_SELECTION"
}
