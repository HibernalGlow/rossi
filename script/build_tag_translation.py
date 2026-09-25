"""生成宿主内置的 EhTagTranslation 精简字典（英文 tag ↔ 中文译名）。

与 Breeze-plugin-ehentai 的 init.js 同源：取 EhTagTranslation/Database
最新 release 的 `db.text.json`，压成 `{namespace: {tag: 译名}}` 后 gzip
落到 asset/tag_translation/etht.json.gz。插件端与宿主端用同一张表，
「插件显示什么译名，宿主就能反推回什么原词」才不会对不上。

用法：
    python script/build_tag_translation.py            # 走系统代理设置
    GITHUB_TOKEN=ghp_xxx python script/build_tag_translation.py   # 撞限流时

产物要随代码提交（构建期不再拉网络）。
"""

import gzip
import json
import os
import sys
import urllib.request

API = "https://api.github.com/repos/EhTagTranslation/Database/releases/latest"
ASSET_NAME = "db.text.json"
OUT_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "asset",
    "tag_translation",
    "etht.json.gz",
)


def fetch(url: str, attempts: int = 5) -> bytes:
    headers = {"User-Agent": "rossi-build-tag-translation"}
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"token {token}"
    last_error: Exception | None = None
    for attempt in range(attempts):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=180) as resp:
                return resp.read()
        except Exception as e:  # GitHub 资产下载常整段断流，重试比断言「不存在」可靠
            last_error = e
            print(f"  第 {attempt + 1}/{attempts} 次失败: {e}", file=sys.stderr)
    raise last_error  # type: ignore[misc]


def main() -> int:
    release = json.loads(fetch(API))
    asset = next(
        (a for a in release.get("assets", []) if a["name"] == ASSET_NAME), None
    )
    if asset is None:
        print(f"release {release.get('tag_name')} 里没有 {ASSET_NAME}", file=sys.stderr)
        return 1

    db = json.loads(fetch(asset["browser_download_url"]))
    compact: dict[str, dict[str, str]] = {}
    total = 0
    for entry in db.get("data", []):
        namespace = (entry.get("namespace") or "").strip().lower()
        # rows 那一节是命名空间自己的译名，tag 匹配用不到。
        if not namespace or namespace == "rows":
            continue
        tags = {}
        for tag, value in (entry.get("data") or {}).items():
            name = str((value or {}).get("name") or "").strip()
            tag = str(tag).strip()
            if tag and name:
                tags[tag] = name
        if tags:
            compact[namespace] = tags
            total += len(tags)

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    payload = json.dumps(compact, ensure_ascii=False, separators=(",", ":"))
    with gzip.open(OUT_PATH, "wb", compresslevel=9) as f:
        f.write(payload.encode("utf-8"))

    size = os.path.getsize(OUT_PATH)
    print(
        f"head={db.get('head', {}).get('sha', '?')[:12]} "
        f"namespaces={len(compact)} tags={total} "
        f"json={len(payload) / 1024 / 1024:.2f}MB gz={size / 1024:.0f}KB -> {OUT_PATH}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
