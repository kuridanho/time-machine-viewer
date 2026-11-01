#!/bin/zsh
# 指定したタブを開いた状態でアプリを起動し、ウィンドウを撮る。
# 使い方: scripts/screenshot.sh <tab> <出力.png>   (tab: overview, directories, trends, diagnostics, log)
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -f 'Time Machine Viewer.app' || true
sleep 1
defaults write com.kuridanho.TimeMachineViewer selectedTab -string "$1"
open "build/Time Machine Viewer.app"
sleep "${WAIT:-8}"
WID=$(swift -e 'import CoreGraphics; let l = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as! [[String: Any]]; for w in l where (w["kCGWindowOwnerName"] as? String) == "Time Machine Viewer" { let b = w["kCGWindowBounds"] as! [String: Any]; if (b["Height"] as! Double) > 200 { print(w["kCGWindowNumber"]!); break } }' 2>/dev/null)
screencapture -l"$WID" -o "$2"
