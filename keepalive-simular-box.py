#!/usr/bin/env python3
"""
Simular box 保活脚本（免费额度内使用）
=====================================
原理：box 连续睡 14 天会被删除。任何一次 MCP 连接都会唤醒它，
唤醒后断开，它会重新入睡，14 天计时重置。

用法：
  1. 先在 https://box.simular.ai/access 创建一个 personal key
     （只用于 MCP 连接，不要把 key 写进本文件、不要发到聊天里）
  2. 设置环境变量：
       export SIMULAR_BOX_KEY='你的 personal key'
  3. 手动跑一次：
       python3 keepalive-simular-box.py
  4. 定时跑（建议每周一次，远早于 14 天删除线）：
       crontab -e
       0 10 * * 0 SIMULAR_BOX_KEY='你的 personal key' python3 /path/to/keepalive-simular-box.py >> /path/to/keepalive.log 2>&1

成本说明：
  - 只做一次 MCP initialize + tools/list 就断开，box 只醒几秒到几十秒
  - 免费 box 约 100 credits/小时，醒 1 分钟约 2 credits
  - 每周一次，一年约 100 credits；免费额度共 5,000 credits，有效期 90 天
  - 注意：5,000 免费 credits 本身 90 天后过期，保活只能防 14 天删除，
    不能延长 credits 有效期；90 天内没用完也会过期
  - Uppcoder Spark 不需要保活：它是常驻在线、没有时间限制的免费计划
"""
import json
import os
import sys
import urllib.request
import uuid

MCP_URL = "https://mcp.box.simular.ai/mcp"
LOG_PREFIX = "[simular-keepalive]"


def mcp_call(key: str, method: str, params: dict | None = None) -> dict:
    body = json.dumps(
        {
            "jsonrpc": "2.0",
            "id": str(uuid.uuid4()),
            "method": method,
            "params": params or {},
        }
    ).encode()
    req = urllib.request.Request(
        MCP_URL,
        data=body,
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            "Authorization": f"Bearer {key}",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = resp.read().decode("utf-8", "replace")
    # Streamable HTTP 可能返回 SSE（data: {...}），只取第一条 JSON
    for line in raw.splitlines():
        line = line.strip()
        if line.startswith("data:"):
            line = line[5:].strip()
        if line.startswith("{"):
            return json.loads(line)
    return json.loads(raw)


def main() -> int:
    key = os.environ.get("SIMULAR_BOX_KEY", "").strip()
    if not key:
        print(f"{LOG_PREFIX} 未设置 SIMULAR_BOX_KEY，先去 box.simular.ai/access 创建 personal key", file=sys.stderr)
        return 2
    try:
        init = mcp_call(
            key,
            "initialize",
            {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "simular-keepalive", "version": "1.0"},
            },
        )
        print(f"{LOG_PREFIX} MCP 已连接，box 已唤醒：{init.get('result', {}).get('serverInfo', {})}")
        tools = mcp_call(key, "tools/list")
        names = [t.get("name") for t in tools.get("result", {}).get("tools", [])]
        print(f"{LOG_PREFIX} 工具列表已取回（{len(names)} 个），断开连接，box 将重新入睡：{names[:5]}")
        print(f"{LOG_PREFIX} 保活成功")
        return 0
    except Exception as e:  # noqa: BLE001 - 保活脚本只记录失败，不抛错中断 cron
        print(f"{LOG_PREFIX} 保活失败：{e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
