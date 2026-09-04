#!/usr/bin/env python3
"""MCP chatbot-ios-qa — wrappers réels autour de scripts/ios/qa.mjs + pymobiledevice3.

Chaque outil appelle une commande réelle. HID renvoie BLOCKED_BY_OS sur iOS < 27
au lieu de faux PASS.
"""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

from mcp.server.fastmcp import FastMCP

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "artifacts" / "ios"
QA_JS = ROOT / "scripts" / "ios" / "qa.mjs"

mcp = FastMCP(
    "chatbot-ios-qa",
    instructions=(
        "PHYSICAL DEVICE via pymobiledevice3 on Windows. "
        "Prefer ios_deploy for Fast QA (build+install+launch+screenshot). "
        "Always distinguish PHYSICAL DEVICE vs SIMULATOR. "
        "After capture_ios_screen / ios_deploy, READ artifacts/ios/latest.png for vision. "
        "HID tap/swipe/type require iOS 27+ media stream — expect BLOCKED_BY_OS on iOS 26."
    ),
)


def _py() -> list[str]:
    candidates = []
    env = os.environ.get("PYTHON_IOS_QA")
    if env:
        candidates.append(env)
    local = Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Python" / "Python312" / "python.exe"
    if local.exists():
        candidates.append(str(local))
    candidates += ["py", "python3", "python"]
    for c in candidates:
        if c == "py":
            r = subprocess.run([c, "-3", "-c", "import pymobiledevice3"], capture_output=True)
            if r.returncode == 0:
                return [c, "-3"]
        else:
            r = subprocess.run([c, "-c", "import pymobiledevice3"], capture_output=True)
            if r.returncode == 0:
                return [c]
    raise RuntimeError("pymobiledevice3 introuvable — pip install -r requirements-ios-qa.txt")


def _node_qa(args: list[str], *, allow_fail: bool = False) -> str:
    node = shutil.which("node") or "node"
    r = subprocess.run([node, str(QA_JS), *args], capture_output=True, text=True, cwd=str(ROOT))
    out = ((r.stdout or "") + (r.stderr or "")).strip()
    if r.returncode != 0 and not allow_fail:
        raise RuntimeError(out or f"qa.mjs exit {r.returncode}")
    return out or f"(exit {r.returncode})"


@mcp.tool()
def ios_versions() -> str:
    """Versions host: node, python, pymobiledevice3, mcp."""
    return _node_qa(["versions"])


@mcp.tool()
def ios_capabilities() -> str:
    """Matrice PHYSICAL DEVICE vs SIMULATOR (honnête)."""
    return _node_qa(["capabilities"])


@mcp.tool()
def ios_device_info() -> str:
    """Info iPhone USB: iOS version, UDID, bundle SideStore, hidExpected."""
    return _node_qa(["device-info"], allow_fail=True)


@mcp.tool()
def ios_mount() -> str:
    """Monte Developer Disk Image (PHYSICAL DEVICE)."""
    return _node_qa(["mount"])


@mcp.tool()
def ios_media_support() -> str:
    """get-media-support-info — supportedFeatures==0 => HID BLOCKED_BY_OS."""
    return _node_qa(["media-support"], allow_fail=True)


@mcp.tool()
def ios_launch() -> str:
    """Lance ChatbotNative (bundle SideStore). Face ID peut bloquer l'UI."""
    return _node_qa(["launch"])


@mcp.tool()
def ios_screenshot(label: str = "screen") -> str:
    """
    Screenshot PHYSICAL DEVICE → artifacts/ios/<label>.png + latest.png.
    Après appel: LIRE le PNG avec l'outil Read pour analyse visuelle.
    """
    return _node_qa(["screenshot", label])


@mcp.tool()
def ios_open_deep_link(path: str) -> str:
    """
    Deep link QA (PHYSICAL DEVICE). Ex: qa/mail, qa/files/documents,
    qa/assistant/mail, qa/chat, qa/composer. Ne contourne PAS l'auth.
    """
    return _node_qa(["open", path])


@mcp.tool()
def ios_hid_tap(x: int = 32768, y: int = 32768) -> str:
    """
    HID tap coords normalisées 0..65535 (PHYSICAL DEVICE).
    Sur iOS < 27: retourne BLOCKED_BY_OS (pas un faux PASS).
    """
    return _node_qa(["tap", str(x), str(y)], allow_fail=True)


@mcp.tool()
def ios_hid_swipe(x1: int = 32768, y1: int = 5000, x2: int = 32768, y2: int = 60000) -> str:
    """HID drag/swipe. iOS < 27 => BLOCKED_BY_OS."""
    return _node_qa(["swipe", str(x1), str(y1), str(x2), str(y2)], allow_fail=True)


@mcp.tool()
def ios_hid_type(text: str) -> str:
    """HID typing ASCII. iOS < 27 => BLOCKED_BY_OS."""
    return _node_qa(["type", text], allow_fail=True)


@mcp.tool()
def ios_autonomous(label: str = "autonomous") -> str:
    """
    Campagne PHYSICAL DEVICE: connection, DDI, media, launch, screenshot, HID.
    Produit artifacts/ios/qa-report-*.json. Lire latest.png ensuite.
    """
    return _node_qa(["autonomous", "--label", label], allow_fail=True)


@mcp.tool()
def ios_ui_test_simulator(watch: bool = True) -> str:
    """
    SIMULATOR ONLY — Fast Simulator (ios:sim): GHA macos-26 XCUITest + PNG download.
    Prefer watch=True. N'est PAS équivalent à PHYSICAL DEVICE VERIFIED.
    """
    if watch:
        return _node_qa(["test-sim", "--watch"], allow_fail=True)
    return _node_qa(["test-sim"], allow_fail=True)


@mcp.tool()
def ios_build(watch: bool = False) -> str:
    """Build IPA + tests via GitHub Actions ios-native (SIMULATOR/CI)."""
    args = ["build"]
    if watch:
        args.append("--watch")
    return _node_qa(args)


@mcp.tool()
def ios_install_prep(trigger_build: bool = False) -> str:
    """Télécharge IPA GHA Full CI + ouvre iloader (legacy). Préférer ios_deploy."""
    args = ["install-prep"]
    if trigger_build:
        args.append("--trigger")
    return _node_qa(args)


def _node_deploy(args: list[str], *, allow_fail: bool = False) -> str:
    node = shutil.which("node") or "node"
    deploy = ROOT / "scripts" / "ios" / "deploy.mjs"
    r = subprocess.run([node, str(deploy), *args], capture_output=True, text=True, cwd=str(ROOT))
    out = ((r.stdout or "") + (r.stderr or "")).strip()
    if r.returncode != 0 and not allow_fail:
        raise RuntimeError(out or f"deploy.mjs exit {r.returncode}")
    if r.returncode == 2:
        return out or "INSTALL_HUMAN_REQUIRED"
    return out or f"(exit {r.returncode})"


@mcp.tool()
def ios_build_qa(watch: bool = True) -> str:
    """
    Fast QA: déclenche ios-native-qa.yml pour le SHA courant, attend, download artifact.
    Sans unit/UI tests. Voir docs/IOS-FAST-CI.md.
    """
    # watch is always on for fast-build (script watches until success)
    _ = watch
    return _node_deploy(["fast-build"])


@mcp.tool()
def ios_download_artifact(sha: str = "") -> str:
    """Download artifact Fast QA lié au commit (jamais 'latest' global)."""
    args = ["download"]
    if sha.strip():
        args += ["--sha", sha.strip()]
    return _node_deploy(args)


@mcp.tool()
def ios_install(ipa_path: str = "") -> str:
    """
    Install IPA via isideload (creds env/vault) ou fallback iLoader GUI.
    Exit 2 / INSTALL_HUMAN_REQUIRED si 2FA ou CLI absente.
    """
    args = ["install"]
    if ipa_path.strip():
        args.append(ipa_path.strip())
    return _node_deploy(args, allow_fail=True)


@mcp.tool()
def ios_deploy(skip_build: bool = False, no_launch: bool = False) -> str:
    """
    Compose Fast QA: build → download SHA-bound → install → launch → screenshot smoke.
    PHYSICAL DEVICE. Lire artifacts/ios/latest.png ensuite.
    """
    args = ["deploy"]
    if skip_build:
        args.append("--skip-build")
    if no_launch:
        args.append("--no-launch")
    return _node_deploy(args, allow_fail=True)


@mcp.tool()
def ios_latest_screenshot_path() -> str:
    """Chemin absolu artifacts/ios/latest.png pour vision."""
    latest = ARTIFACTS / "latest.png"
    if not latest.exists():
        return "MISSING — appeler ios_screenshot d'abord"
    return str(latest.resolve())


if __name__ == "__main__":
    mcp.run()
