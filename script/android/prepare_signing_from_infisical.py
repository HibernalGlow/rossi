#!/usr/bin/env python3
"""从 Infisical 注入的环境变量准备 Android release 签名文件。

CI  : Infisical/secrets-action 把 secret 注入为环境变量后调用本脚本。
本机: infisical run --env=prod -- python3 script/android/prepare_signing_from_infisical.py

产物 android/Breeze-key.keystore 与 android/key.properties 已在 .gitignore 中，
由每次构建现场生成；本机与 CI 取同一份 Infisical secret，签名不会漂移。
"""
import base64
import os
import sys
from pathlib import Path

ANDROID = Path(__file__).resolve().parents[2] / "android"

REQUIRED = (
    "ANDROID_KEYSTORE_B64",
    "ANDROID_KEY_ALIAS",
    "ANDROID_KEY_PASSWORD",
    "ANDROID_STORE_PASSWORD",
)


def main() -> int:
    missing = [name for name in REQUIRED if not os.environ.get(name)]
    if missing:
        print(f"[signing] 缺少 Infisical secret: {', '.join(missing)}", file=sys.stderr)
        return 1

    # 从 UI 粘贴时可能带换行/空白，先归一化再解码
    encoded = "".join(os.environ["ANDROID_KEYSTORE_B64"].split())
    keystore_bytes = base64.b64decode(encoded, validate=True)
    if not keystore_bytes:
        print("[signing] ANDROID_KEYSTORE_B64 解码后为空", file=sys.stderr)
        return 1

    keystore = ANDROID / "Breeze-key.keystore"
    keystore.write_bytes(keystore_bytes)
    keystore.chmod(0o644)

    props = ANDROID / "key.properties"
    props.write_text(
        "keyAlias={alias}\n"
        "keyPassword={key}\n"
        "storeFile=../Breeze-key.keystore\n"
        "storePassword={store}\n".format(
            alias=os.environ["ANDROID_KEY_ALIAS"],
            key=os.environ["ANDROID_KEY_PASSWORD"],
            store=os.environ["ANDROID_STORE_PASSWORD"],
        ),
        encoding="utf-8",
    )
    props.chmod(0o644)

    print("[signing] key.properties 已写入 ⇒ release 用发布 key 签名")
    return 0


if __name__ == "__main__":
    sys.exit(main())
