#!/bin/bash
# Claude Code の状態を PATLITE NH-FV シリーズ (NHP-FV1) に表示するフック用スクリプト。
#
# 使い方: claude-lamp.sh <state>
#   tool       stdin の PreToolUse JSON を見てツール種別ごとに色分け
#                Edit/Write/NotebookEdit → edit (青点滅)
#                WebFetch/WebSearch/Agent/Task → web (白点滅)
#                その他 → working (緑点滅)
#   working    緑点滅  (思考・読み取り中)
#   edit       青点滅  (ファイル編集中)
#   web        白点滅  (Web・サブエージェント)
#   compact    黄点灯  (コンテキスト圧縮中)
#   waiting    黄点滅  (入力待ちアイドル)
#   attention  赤点滅  (許可待ち・要対応)
#   fail       赤点灯  (ツール失敗。次のイベントで上書きされる)
#   done       白→青→緑ワイプして緑点灯 (応答完了)
#   hello      5色スイープして緑点灯 (セッション開始。source=compact は無視)
#   notify     stdin の Notification JSON を見て attention / waiting を自動選択
#   off        消灯
#   demo       全状態を順に実演して消灯 (手動確認用)
#
# オプション (環境変数):
#   CLAUDE_LAMP_BUZZER=1        attention でブザーパターン2も鳴らす
#   CLAUDE_LAMP_DONE_CHANNEL=n  done で MP3 チャンネル n を1回再生
#   PATLITE_HOST / PATLITE_PORT 接続先 (デフォルト 192.168.10.1:10000)
#
# ランプに届かなくても Claude Code を妨げないよう、送信は 1 秒タイムアウト・
# バックグラウンドで行い、常に exit 0 する。

HOST="${PATLITE_HOST:-192.168.10.1}"
PORT="${PATLITE_PORT:-10000}"
STATE_FILE="/tmp/claude-lamp.${USER:-nouser}.state"
LOG_FILE="/tmp/claude-lamp.${USER:-nouser}.log"

JQ=$(command -v jq || echo /opt/homebrew/bin/jq)

# 6桁パターン (赤黄緑青白ブザー) か "clear" を PNS コマンドで送る
pns_send() {
  local payload i c
  if [ "$1" = "clear" ]; then
    payload='\130\130\103\000\000\000'
  else
    payload='\130\130\123\000\000\006'
    for ((i = 0; i < 6; i++)); do
      c=${1:$i:1}
      payload+=$(printf '\\%03o' "$c")
    done
  fi
  printf "$payload" | nc -G 1 -w 1 "$HOST" "$PORT" >/dev/null 2>&1
}

# MP3 チャンネル $1 を1回再生
pns_play() {
  local n=$1
  [ "$n" -ge 1 ] 2>/dev/null && [ "$n" -le 70 ] || return
  local bcd=$(((n / 10 << 4) | n % 10))
  printf "\\130\\130\\126\\000\\000\\004\\001\\000\\000$(printf '\\%03o' "$bcd")" |
    nc -G 1 -w 1 "$HOST" "$PORT" >/dev/null 2>&1
}

# スイープ演出: 引数のパターン列を順に送る。途中で状態が変わったら中断
sweep() {
  local want=$1 p
  shift
  for p in "$@"; do
    pns_send "$p"
    sleep 0.15
    [ "$(cat "$STATE_FILE" 2>/dev/null)" = "$want" ] || exit 0
  done
}

state="$1"

case "$state" in
  tool)
    toolname=$("$JQ" -r '.tool_name // empty' 2>/dev/null)
    case "$toolname" in
      Edit | Write | NotebookEdit) state=edit ;;
      WebFetch | WebSearch | Agent | Task) state=web ;;
      *) state=working ;;
    esac
    ;;
  notify)
    msg=$(cat 2>/dev/null)
    case "$msg" in
      *ermission*) state=attention ;;
      *) state=waiting ;;
    esac
    ;;
  hello)
    src=$("$JQ" -r '.source // empty' 2>/dev/null)
    [ "$src" = "compact" ] && exit 0
    ;;
  demo)
    for p in 100000 010000 001000 000100 000010; do pns_send "$p"; sleep 0.15; done
    for p in 002000 000200 000020 010000 020000 200000 100000; do pns_send "$p"; sleep 1; done
    for p in 000010 000100 001000; do pns_send "$p"; sleep 0.15; done
    sleep 1
    pns_send clear
    exit 0
    ;;
esac

case "$state" in
  working)   pat=002000 ;;
  edit)      pat=000200 ;;
  web)       pat=000020 ;;
  compact)   pat=010000 ;;
  waiting)   pat=020000 ;;
  attention)
    pat=200000
    [ -n "$CLAUDE_LAMP_BUZZER" ] && pat=200002 ;;
  fail)      pat=100000 ;;
  done)      pat=sweep ;;
  hello)     pat=sweep ;;
  off)       pat=clear ;;
  *)
    echo "usage: claude-lamp.sh tool|working|edit|web|compact|waiting|attention|fail|done|hello|notify|off|demo" >&2
    exit 2
    ;;
esac

# 同じ状態の連続送信はスキップ (PreToolUse/PostToolUse が高頻度で呼ぶため)
last=$(cat "$STATE_FILE" 2>/dev/null)
[ "$last" = "$state" ] && exit 0
printf '%s' "$state" > "$STATE_FILE"
printf '%s %s\n' "$(date +%H:%M:%S)" "$state" >> "$LOG_FILE"

case "$state" in
  done)
    (
      sweep done 000010 000100 001000
      [ -n "$CLAUDE_LAMP_DONE_CHANNEL" ] && pns_play "$CLAUDE_LAMP_DONE_CHANNEL"
    ) >/dev/null 2>&1 &
    ;;
  hello)
    ( sweep hello 100000 010000 001000 000100 000010 001000 ) >/dev/null 2>&1 &
    ;;
  *)
    ( pns_send "$pat" ) >/dev/null 2>&1 &
    ;;
esac
exit 0
