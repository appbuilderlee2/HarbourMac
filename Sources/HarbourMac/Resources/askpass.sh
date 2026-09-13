#!/bin/bash
# sudo receives this output directly; Harbour never receives the password.
exec /usr/bin/osascript -e 'display dialog "Mole 需要管理員權限完成你選擇的操作。請輸入 Mac 登入密碼。" default answer "" with hidden answer with title "Harbour — Mole 授權" buttons {"取消", "授權"} default button "授權" cancel button "取消"' -e 'text returned of result'
