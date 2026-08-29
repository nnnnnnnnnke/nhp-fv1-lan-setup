#!/bin/bash
# Claude Code の状態を PATLITE NH-FV シリーズ (NHP-FV1) に表示するフック用スクリプト。
#
# 使い方: claude-lamp.sh <state>
#   working    緑点滅  (Claude が作業中)
#   attention  赤点滅  (許可待ち・要対応)  ※CLAUDE_LAMP_BUZZER=1 でブザーパターン2も鳴らす
#   waiting    黄点滅  (入力待ちアイドル通知)
#   done       緑点灯  (応答完了)
#   off        消灯    (PNS クリアコマンド)
#   notify     stdin の Notification フック JSON を見て attention / waiting を自動選択
#
# 接続先は PATLITE_HOST / PATLITE_PORT で上書き可 (デフォルト 192.168.10.1:10000)。
# ランプに届かなくても Claude Code を妨げないよう、送信は 1 秒タイムアウト・
# バックグラウンドで行い、常に exit 0 する。

HOST="${PATLITE_HOST:-192.168.10.1}"
PORT="${PATLITE_PORT:-10000}"
STATE_FILE="/tmp/claude-lamp.${USER:-nouser}.state"

state="$1"

if [ "$state" = "notify" ]; then
  # Notification フックの JSON メッセージで種別を判定
  msg=$(cat 2>/dev/null)
  case "$msg" in
    *ermission*) state="attention" ;;
    *)           state="waiting" ;;
  esac
fi

# PNS コマンド (octal エスケープ)。S=表示灯制御(赤黄緑青白ブザー)、C=クリア
case "$state" in
  working)   payload='\130\130\123\000\000\006\000\000\002\000\000\000' ;;
  waiting)   payload='\130\130\123\000\000\006\000\002\000\000\000\000' ;;
  attention)
    buz='\000'
    [ -n "$CLAUDE_LAMP_BUZZER" ] && buz='\002'
    payload="\130\130\123\000\000\006\002\000\000\000\000${buz}" ;;
  done)      payload='\130\130\123\000\000\006\000\000\001\000\000\000' ;;
  off)       payload='\130\130\103\000\000\000' ;;
  *)
    echo "usage: claude-lamp.sh working|waiting|attention|done|off|notify" >&2
    exit 2 ;;
esac

# 同じ状態の連続送信はスキップ (PreToolUse/PostToolUse が高頻度で呼ぶため)
last=$(cat "$STATE_FILE" 2>/dev/null)
[ "$last" = "$state" ] && exit 0
printf '%s' "$state" > "$STATE_FILE"

( printf "$payload" | nc -G 1 -w 1 "$HOST" "$PORT" >/dev/null 2>&1 & )
exit 0
