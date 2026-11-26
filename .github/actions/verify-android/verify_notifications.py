"""Check notification resources and the merged manifest in an Android APK."""

import re
import subprocess
import sys
import zipfile


ANDROID = "http://schemas.android.com/apk/res/android:"
PLUGIN = "com.dexterous.flutterlocalnotifications."


def dump(aapt2, apk, command, *args):
    return subprocess.check_output([aapt2, "dump", command, apk, *args], text=True, encoding="utf-8")


def manifest_elements(xml):
    nodes = []
    parents = []
    for line in xml.splitlines():
        content = line.lstrip()
        depth = len(line) - len(content)
        if content.startswith("E: "):
            while parents and parents[-1][0] >= depth:
                parents.pop()
            node = (content[3:].split()[0], {}, [])
            (parents[-1][1][2] if parents else nodes).append(node)
            parents.append((depth, node))
        elif content.startswith(f"A: {ANDROID}"):
            attribute, value = content[len(f"A: {ANDROID}"):].split("=", 1)
            quoted = re.match(r'"([^"]*)"', value)
            parents[-1][1][1][attribute.split("(", 1)[0]] = quoted[1] if quoted else value
    return nodes


def names(nodes, tag):
    return {attributes.get("name") for name, attributes, _ in nodes if name == tag}


def verify(aapt2, apk):
    resources = dump(aapt2, apk, "resources")
    icon = re.search(
        r"(?m)^\s+resource 0x[\da-f]+ drawable/ic_stat_course\s*\n"
        r"[^\n]*\(file\) (\S+) type=XML\b", resources,
    )
    with zipfile.ZipFile(apk) as archive:
        if icon is None or icon[1] not in archive.namelist():
            raise ValueError("通知图标 drawable/ic_stat_course 缺失")

    [manifest] = manifest_elements(dump(aapt2, apk, "xmltree", "--file", "AndroidManifest.xml"))
    permissions = names(manifest[2], "uses-permission")
    expected = {f"android.permission.{name}" for name in (
        "POST_NOTIFICATIONS", "RECEIVE_BOOT_COMPLETED", "SCHEDULE_EXACT_ALARM",
    )}
    if expected - permissions or "android.permission.USE_EXACT_ALARM" in permissions:
        raise ValueError(f"通知或精确闹钟权限配置有误，缺少 {expected - permissions}")

    [application] = [node for node in manifest[2] if node[0] == "application"]
    receivers = {attrs.get("name"): (attrs, children)
                 for tag, attrs, children in application[2] if tag == "receiver"}
    for receiver in ("ScheduledNotificationReceiver", "ScheduledNotificationBootReceiver"):
        attributes, _ = receivers.get(PLUGIN + receiver, ({}, []))
        if attributes.get("exported") not in {"false", "0x0", "0x00000000"}:
            raise ValueError(f"{receiver} 缺失或可被外部应用调用")
    _, children = receivers[PLUGIN + "ScheduledNotificationBootReceiver"]
    actions = set().union(*(names(nodes, "action") for tag, _, nodes in children if tag == "intent-filter"))
    expected = {"android.intent.action.BOOT_COMPLETED", "android.intent.action.MY_PACKAGE_REPLACED",
                "android.intent.action.QUICKBOOT_POWERON", "com.htc.intent.action.QUICKBOOT_POWERON"}
    if expected - actions:
        raise ValueError(f"通知恢复接收器缺少 {expected - actions}")
    print(f"通知图标、权限与接收器检查通过：{apk}")


if __name__ == "__main__":
    verify(*sys.argv[1:])
