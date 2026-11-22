#!/usr/bin/env python3
"""
Qdrant Cloud 免费集群保活脚本（免费额度内使用）
=============================================
原理：免费集群 1 周不用会被暂停（suspend），4 周不用会被删除。
每周对集群本身发一次真实请求，就算一次使用，计时重置。

前置条件（今天先做完这两步，脚本才能跑）：
  1. 在 Qdrant Cloud 控制台建一个免费集群：Clusters -> Create -> Free
     （按用户说的今天建；昨天注册时按用户要求没建集群，所以目前是 0 个集群）
  2. 建好后在集群页 API Keys -> Create 拿 key（只显示一次，别粘贴到聊天里，
     走和 Simular key 一样的安全页面交给我；key 默认 90 天过期，留空则不过期）

用法：
  1. 设置环境变量（key 和地址都不要写进本文件）：
       export QDRANT_URL='https://你的集群.cloud.qdrant.io'
       export QDRANT_API_KEY='你的 API key'
  2. 手动跑一次：
       python3 keepalive-qdrant-cloud.py
  3. 定时跑（建议每周一次，远早于 1 周暂停线）：
       crontab -e
       0 10 * * 0 QDRANT_URL='https://你的集群.cloud.qdrant.io' QDRANT_API_KEY='你的 key' python3 /path/to/keepalive-qdrant-cloud.py >> /path/to/keepalive-qdrant.log 2>&1

成本说明：
  - 只做一次 GET /collections 读请求，不建集合、不写向量、不产生费用
  - 免费集群本来就是 $0 永久免费，无需信用卡；保活只是防暂停/删除
  - 注意：如果集群已被暂停，第一次请求可能先把它唤醒；若已被删除，
    脚本会报错，届时需要在控制台重新建一个免费集群并换新的 key 和地址

参考：Qdrant 官方文档 "Free clusters are suspended after 1 week without
use and deleted after 4 weeks of inactivity."
（https://qdrant.tech/documentation/cloud-getting-started/）
"""
import json
import os
import sys
import urllib.request

LOG_PREFIX = "[qdrant-keepalive]"


def main() -> int:
    url = os.environ.get("QDRANT_URL", "").strip().rstrip("/")
    key = os.environ.get("QDRANT_API_KEY", "").strip()
    if not url or not key:
        print(
            f"{LOG_PREFIX} 未设置 QDRANT_URL 或 QDRANT_API_KEY：先在控制台建免费集群并取 key",
            file=sys.stderr,
        )
        return 2
    try:
        req = urllib.request.Request(
            f"{url}/collections",
            headers={"api-key": key},
            method="GET",
        )
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode("utf-8", "replace"))
        collections = data.get("result", {}).get("collections", [])
        print(f"{LOG_PREFIX} 集群有响应，共 {len(collections)} 个集合：{[c.get('name') for c in collections]}")
        print(f"{LOG_PREFIX} 保活成功（本次使用已计入，1 周暂停计时重置）")
        return 0
    except Exception as e:  # noqa: BLE001 - 保活脚本只记录失败，不抛错中断 cron
        print(f"{LOG_PREFIX} 保活失败：{e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
