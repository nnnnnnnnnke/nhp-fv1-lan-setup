#!/usr/bin/env python3
"""PATLITE NH-FV シリーズ (NHP-FV1 等) を PNS コマンドで制御する CLI。

ソケット通信 (工場出荷時: TCP ポート 10000) で表示灯・ブザー・MP3 チャンネルを制御する。

使用例:
    ./pns.py status              # 表示灯とブザーの状態を取得
    ./pns.py set 100000          # 赤だけ点灯、他は消灯、ブザー停止
    ./pns.py set 199990          # 赤を点灯、他は現状維持、ブザー停止
    ./pns.py clear               # 通常状態に戻す(表示灯消灯・再生停止)
    ./pns.py channel 32 -r 3     # チャンネル32を3回再生
    ./pns.py stop                # チャンネル再生停止

set の6桁: [赤][黄][緑][青][白][ブザー]
    表示灯:  0=消灯 1=点灯 2=点滅パターン1 3=点滅パターン2 9=状態維持
    ブザー:  0=停止 1〜4=ブザーパターン1〜4 9=状態維持

接続先は --host か環境変数 PATLITE_HOST で指定 (デフォルト 192.168.10.1)。
"""
import argparse
import os
import socket
import sys

ACK = b"\x06"
NAK = b"\x15"

LIGHT_STATE = {0: "消灯", 1: "点灯", 2: "点滅1", 3: "点滅2"}
BUZZER_STATE = {0: "停止", 1: "パターン1", 2: "パターン2", 3: "パターン3", 4: "パターン4"}


def send(host: str, port: int, payload: bytes) -> bytes:
    with socket.create_connection((host, port), timeout=5) as s:
        s.sendall(payload)
        return s.recv(64)


def check_ack(resp: bytes) -> None:
    if resp == ACK:
        print("OK (ACK)")
    elif resp == NAK:
        sys.exit("NG (NAK): 本体がコマンドを拒否しました")
    else:
        sys.exit(f"NG: 想定外の応答 {resp.hex(' ')}")


def bcd(n: int) -> int:
    """10進のチャンネル番号(1-70)をBCD 1バイトへ (例: 32 -> 0x32)。"""
    if not 1 <= n <= 70:
        sys.exit("チャンネル番号は 1〜70 で指定してください")
    return (n // 10) << 4 | (n % 10)


def cmd_status(args) -> None:
    resp = send(args.host, args.port, bytes([0x58, 0x58, 0x47, 0x00, 0x00, 0x00]))
    if len(resp) != 6:
        sys.exit(f"NG: 想定外の応答 {resp.hex(' ')}")
    names = ["赤", "黄", "緑", "青", "白"]
    for name, v in zip(names, resp[:5]):
        print(f"{name}: {LIGHT_STATE.get(v, f'不明({v:02X})')}")
    print(f"ブザー: {BUZZER_STATE.get(resp[5], f'不明({resp[5]:02X})')}")


def cmd_set(args) -> None:
    digits = args.pattern
    if len(digits) != 6 or not digits.isdigit():
        sys.exit("パターンは6桁の数字で指定してください (例: 100000)")
    data = [int(c) for c in digits]
    for v in data[:5]:
        if v not in (0, 1, 2, 3, 9):
            sys.exit("表示灯は 0/1/2/3/9 のいずれかで指定してください")
    if data[5] not in (0, 1, 2, 3, 4, 9):
        sys.exit("ブザーは 0〜4/9 のいずれかで指定してください")
    payload = bytes([0x58, 0x58, 0x53, 0x00, 0x00, 0x06, *data])
    check_ack(send(args.host, args.port, payload))


def cmd_clear(args) -> None:
    check_ack(send(args.host, args.port, bytes([0x58, 0x58, 0x43, 0x00, 0x00, 0x00])))


def cmd_channel(args) -> None:
    repeat = args.repeat
    if not 0 <= repeat <= 255:
        sys.exit("リピート回数は 0〜255 で指定してください (0=ワンショット, 255=エンドレス)")
    payload = bytes([0x58, 0x58, 0x56, 0x00, 0x00, 0x04, 0x01, repeat, 0x00, bcd(args.number)])
    check_ack(send(args.host, args.port, payload))


def cmd_stop(args) -> None:
    payload = bytes([0x58, 0x58, 0x56, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x01])
    check_ack(send(args.host, args.port, payload))


def main() -> None:
    p = argparse.ArgumentParser(description="PATLITE NH-FV series PNS command CLI")
    p.add_argument("--host", default=os.environ.get("PATLITE_HOST", "192.168.10.1"))
    p.add_argument("--port", type=int, default=int(os.environ.get("PATLITE_PORT", "10000")))
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status", help="表示灯とブザーの状態を取得").set_defaults(func=cmd_status)

    sp = sub.add_parser("set", help="表示灯とブザーを制御 (6桁: 赤黄緑青白ブザー)")
    sp.add_argument("pattern")
    sp.set_defaults(func=cmd_set)

    sub.add_parser("clear", help="通常状態へ戻す").set_defaults(func=cmd_clear)

    cp = sub.add_parser("channel", help="MP3チャンネルを再生 (1〜70)")
    cp.add_argument("number", type=int)
    cp.add_argument("-r", "--repeat", type=int, default=0, help="リピート回数 0〜255")
    cp.set_defaults(func=cmd_channel)

    sub.add_parser("stop", help="チャンネル再生を停止").set_defaults(func=cmd_stop)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
