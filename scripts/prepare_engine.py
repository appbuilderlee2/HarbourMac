"""Reproducible GUI hooks; upstream safety/deletion helpers stay unchanged."""
from pathlib import Path
import shutil, sys, subprocess, json
src=Path(sys.argv[1]).resolve()
dst=Path(__file__).resolve().parents[1]/'Sources/HarbourMac/Resources/Engine'
if dst.exists(): raise SystemExit('Engine already exists; use a clean checkout for regeneration')
dst.mkdir(parents=True)
for name in ['bin','lib','cmd','internal']:
 shutil.copytree(src/name,dst/name)
for name in ['mole','mo','LICENSE','go.mod','go.sum','install.sh']:
 shutil.copy2(src/name,dst/name)
sha=subprocess.check_output(['git','-C',str(src),'rev-parse','HEAD'],text=True).strip()
(dst/'UPSTREAM.json').write_text(json.dumps({'repository':'https://github.com/tw93/Mole','commit':sha,'version':'1.53.0','modifications':'GUI selection and confirmation hooks; see scripts/prepare_engine.py'},indent=2))
def replace(name,old,new,count=1):
 p=dst/name;s=p.read_text();assert s.count(old)==count,(name,s.count(old),old[:60]);p.write_text(s.replace(old,new))
# Enable definition-only imports, without setting test-mode or weakening guards.
for name in ['optimize','touchid']:
 replace('bin/'+name+'.sh','\nmain "$@"\n','\n[[ "${BASH_SOURCE[0]}" != "$0" ]] || main "$@"\n')
replace('bin/installer.sh','if [[ "${MOLE_TEST_MODE:-0}" != "1" ]]; then','if [[ "${BASH_SOURCE[0]}" == "$0" && "${MOLE_TEST_MODE:-0}" != "1" ]]; then')
replace('bin/purge.sh','\nmain "$@"\n','\n[[ "${BASH_SOURCE[0]}" != "$0" ]] || main "$@"\n')
# Insert native selection before terminal-only branches; exact scan arrays survive.
replace('lib/clean/project.sh','if [[ ! -t 0 && "${MOLE_DRY_RUN:-0}" != "1" && "${MOLE_PURGE_YES:-0}" != "1" ]]; then','if ! declare -F harbour_select_purge >/dev/null && [[ ! -t 0 && "${MOLE_DRY_RUN:-0}" != "1" && "${MOLE_PURGE_YES:-0}" != "1" ]]; then')
replace('lib/clean/project.sh','    if [[ -t 0 ]]; then\n        if ! select_purge_categories', '    if declare -F harbour_select_purge >/dev/null; then\n        harbour_select_purge || { PURGE_RUN_OUTCOME="cancelled"; return 1; }\n    elif [[ -t 0 ]]; then\n        if ! select_purge_categories')
replace('lib/clean/project.sh','    if [[ -t 0 ]]; then\n        if ! confirm_purge_cleanup','    if declare -F harbour_confirm >/dev/null; then\n        harbour_confirm "永久清除所選開發檔案（包括選取的雲端同步路徑）" || { PURGE_RUN_OUTCOME="cancelled"; return 1; }\n    elif [[ -t 0 ]]; then\n        if ! confirm_purge_cleanup')
# Native confirmation substitutes the terminal read only; auth and guards remain.
old='''    drain_pending_input # Clean up any pending input before confirmation
    IFS= read -r -s -n1 key || key=""
    drain_pending_input # Clean up any escape sequence remnants'''
new='''    if declare -F harbour_confirm >/dev/null; then
        harbour_confirm "移除以上 App 與相關資料；Homebrew zap 可能永久刪除設定" || return 2
        key=y
    else
'''+old+'''
    fi'''
replace('lib/uninstall/batch.sh',old,new)
replace('bin/installer.sh','    IFS= read -r -s -n1 confirm || confirm=""','    if declare -F harbour_confirm >/dev/null; then\n        harbour_confirm "永久刪除以上安裝檔" || return 1\n        confirm=""\n    else\n        IFS= read -r -s -n1 confirm || return 1\n    fi')
replace('lib/manage/remove.sh','    IFS= read -r -s -n1 key || key=""','    if declare -F harbour_confirm >/dev/null; then\n        harbour_confirm "移除電腦上 Mole CLI、設定及紀錄；Harbour 本身會保留" || return 1\n        key=""\n    else\n        IFS= read -r -s -n1 key || return 1\n    fi')
replace('bin/touchid.sh', '        read -rp "Continue anyway? [y/N] " confirm', '''        if declare -F harbour_confirm >/dev/null; then
            harbour_confirm "此 Mac 可能沒有 Touch ID；仍要修改 sudo 認證設定？" || return 1
            confirm=y
        else
            read -rp "Continue anyway? [y/N] " confirm
        fi''')
print(sha)
