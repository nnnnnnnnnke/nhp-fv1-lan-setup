#!/bin/bash
# PATLITE NH-FV シリーズを Zabbix の通知で制御するアラートスクリプト
#
# Zabbix のスクリプト型メディアタイプから呼び出す想定:
#   patlite_alert.sh <パトライトのIPアドレス> <件名>
#
# 件名には "{EVENT.VALUE}:{EVENT.NSEVERITY}" を渡す
#   {EVENT.VALUE}    : 1=障害発生, 0=復旧
#   {EVENT.NSEVERITY}: 0=未分類 1=情報 2=警告 3=軽度の障害 4=重度の障害 5=致命的な障害
#
# 動作: 障害発生時は深刻度に応じた色を点灯/点滅(他の色は消灯)、復旧時はクリア。
# 複数障害の優先度制御はしない(最後に届いた通知が勝つ)。
#
# 必要コマンド: snmpset (net-snmp)。SETコミュニティは環境変数 PATLITE_COMMUNITY で変更可。

set -eu

HOST="${1:?usage: patlite_alert.sh <host> <event_value>:<nseverity>}"
SUBJECT="${2:?usage: patlite_alert.sh <host> <event_value>:<nseverity>}"
COMMUNITY="${PATLITE_COMMUNITY:-private}"

BASE="1.3.6.1.4.1.20440.4.1.5.1.2.1"   # controlLightTable
CLEAR_OID="1.3.6.1.4.1.20440.4.1.5.1.3.0"

EVENT_VALUE="${SUBJECT%%:*}"
NSEVERITY="${SUBJECT##*:}"

if [ "$EVENT_VALUE" = "0" ]; then
    # 復旧: クリア動作(全消灯・再生停止・監視状態へ復帰)
    exec snmpset -v2c -c "$COMMUNITY" -t 3 -r 1 "$HOST" "$CLEAR_OID" i 1
fi

# 深刻度 → 対象色(1=赤 2=黄 3=緑 4=青 5=白) と状態(1=消灯 2=点灯 3=点滅パターン1 5=点滅パターン2)
case "$NSEVERITY" in
    5) COLOR=1; STATE=3 ;;  # 致命的な障害: 赤 点滅
    4) COLOR=1; STATE=2 ;;  # 重度の障害:   赤 点灯
    3) COLOR=2; STATE=3 ;;  # 軽度の障害:   黄 点滅
    2) COLOR=2; STATE=2 ;;  # 警告:        黄 点灯
    1) COLOR=3; STATE=2 ;;  # 情報:        緑 点灯
    *) COLOR=5; STATE=2 ;;  # 未分類:      白 点灯
esac

# 対象色を指定状態に、他の4色とブザー(6)は消灯/停止に、1回のSET PDUでまとめて設定
VARBINDS=()
for i in 1 2 3 4 5 6; do
    if [ "$i" -eq "$COLOR" ]; then
        VARBINDS+=("$BASE.2.$i" i "$STATE")
    else
        VARBINDS+=("$BASE.2.$i" i 1)
    fi
    VARBINDS+=("$BASE.3.$i" i 0)   # リストアタイマ0 = 即時実行・自動復旧なし
done

exec snmpset -v2c -c "$COMMUNITY" -t 3 -r 1 "$HOST" "${VARBINDS[@]}"
