#!/usr/bin/env python3
"""Install + launch an already-signed .app/.ipa over Wi-Fi via RemotePairing → Trusted Tunnel → RSD.

Requires Python 3.13+ (native TLS-PSK). Does not use usbmux Network.

Env:
  IOS_REMOTE_UDID   (default: first remote_* pair record / known Chatbot device)
  IOS_BUNDLE_ID     (optional override; else read from app Info.plist)
  IOS_NO_LAUNCH=1   skip CoreDevice launch after install
  IOS_EXPECT_VERSION / IOS_EXPECT_BUILD  optional strict post-install match
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import plistlib
import sys
import time
import traceback
from contextlib import AsyncExitStack
from pathlib import Path
from typing import Any, Optional

MIN_PY = (3, 13)


def die(msg: str, code: int = 1) -> None:
    print(f"FAIL: {msg}", file=sys.stderr, flush=True)
    raise SystemExit(code)


def log(msg: str) -> None:
    print(msg, flush=True)


def require_python() -> None:
    if sys.version_info < MIN_PY:
        die(
            f"Python {MIN_PY[0]}.{MIN_PY[1]}+ required for Wi-Fi Trusted Tunnel TLS-PSK "
            f"(got {sys.version.split()[0]}). Use scripts/ios/.deploy-venv."
        )


def read_app_info(app_path: Path) -> dict[str, Any]:
    if app_path.suffix.lower() == ".ipa":
        die("pass a signed .app directory (sign step must expand/sign before RSD install)")
    plist_path = app_path / "Info.plist"
    if not plist_path.is_file():
        die(f"Info.plist missing in {app_path}")
    data = plistlib.loads(plist_path.read_bytes())
    bid = data.get("CFBundleIdentifier")
    if not bid:
        die("CFBundleIdentifier missing in Info.plist")
    return {
        "bundle_id": str(bid),
        "version": data.get("CFBundleShortVersionString"),
        "build": data.get("CFBundleVersion"),
    }


def read_bundle_id(app_path: Path) -> str:
    return str(read_app_info(app_path)["bundle_id"])


def default_udid() -> str:
    import os

    env = os.environ.get("IOS_REMOTE_UDID", "").strip()
    if env:
        return env
    from pymobiledevice3.pair_records import iter_remote_paired_identifiers

    ids = list(iter_remote_paired_identifiers())
    if ids:
        return ids[0]
    return "00008110-000170222186401E"


async def discover_rp_endpoint(timeout: float = 8.0) -> tuple[str, int]:
    from pymobiledevice3.bonjour import browse_remotepairing

    answers = await browse_remotepairing(timeout=timeout)
    for ans in answers:
        for addr in ans.addresses:
            ip = str(addr.ip)
            if ip.startswith("fe80"):
                continue
            return ip, int(ans.port)
    die("RemotePairing Bonjour endpoint not found (same Wi-Fi? phone unlocked? RP paired?)")


async def launch_via_rsd(rsd, bundle_id: str) -> tuple[bool, Any]:
    """Prefer CoreDevice AppService; fall back to DVT ProcessControl (iOS 27 RSD)."""
    try:
        from pymobiledevice3.remote.core_device.app_service import AppServiceService

        app_svc = AppServiceService(rsd)
        await app_svc.connect()
        try:
            detail = await app_svc.launch_application(bundle_id)
            log("[wifi-rsd] launch OK (AppService)")
            return True, detail
        finally:
            await app_svc.close()
    except Exception as e:
        log(f"[wifi-rsd] AppService launch miss: {type(e).__name__}: {e}")

    try:
        from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
        from pymobiledevice3.services.dvt.instruments.process_control import ProcessControl

        async with DvtProvider(rsd) as dvt, ProcessControl(dvt) as pc:
            pid = await pc.launch(bundle_id=bundle_id, kill_existing=True)
            log(f"[wifi-rsd] launch OK (DVT ProcessControl) pid={pid}")
            return True, {"method": "dvt-processcontrol", "pid": pid}
    except Exception as e:
        log(f"[wifi-rsd] launch FAIL {type(e).__name__}: {e}")
        return False, {"error": f"{type(e).__name__}: {e}"}


async def run_install(
    app_path: Path,
    bundle_id: str,
    udid: str,
    launch: bool,
    retries: int,
    expect_version: Optional[str] = None,
    expect_build: Optional[str] = None,
    require_no_usb: bool = True,
) -> dict:
    from pymobiledevice3.remote import tunnel_service
    from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
    from pymobiledevice3.remote.tunnel_service import create_core_device_tunnel_service_using_remotepairing
    from pymobiledevice3.remote.userspace_tunnel import UserspaceDialPlane, UserspaceTun
    from pymobiledevice3.services.afc import AfcService
    from pymobiledevice3.services.installation_proxy import InstallationProxyService
    from pymobiledevice3.usbmux import list_devices

    app_info = read_app_info(app_path)
    if expect_version and str(app_info.get("version")) != str(expect_version):
        die(
            f"signed .app version mismatch: app={app_info.get('version')} expected={expect_version} "
            "(refusing stale signed-app fallback)"
        )
    if expect_build and str(app_info.get("build")) != str(expect_build):
        die(
            f"signed .app build mismatch: app={app_info.get('build')} expected={expect_build} "
            "(refusing stale signed-app fallback)"
        )

    try:
        usbmux = [(d.serial, str(d.connection_type)) for d in await list_devices()]
    except Exception:
        usbmux = []
    usb_present = any(str(t).lower() == "usb" for _, t in usbmux)
    if require_no_usb and usb_present:
        die(f"USB present during Wi-Fi deploy test — aborting (usbmux={usbmux})")

    last_err: Exception | None = None
    for attempt in range(1, retries + 1):
        t0 = time.time()
        tunnel_service.USE_USERSPACE_TUNNEL = True
        stack = AsyncExitStack()
        await stack.__aenter__()
        try:
            log(f"[wifi-rsd] attempt {attempt}/{retries}")
            host, port = await discover_rp_endpoint()
            log(f"[wifi-rsd] RemotePairing {host}:{port}")
            svc = await create_core_device_tunnel_service_using_remotepairing(
                udid, host, port, autopair=False
            )
            stack.push_async_callback(svc.close)
            log("[wifi-rsd] RP session OK")

            tun = await stack.enter_async_context(svc.start_tcp_tunnel())
            log(f"[wifi-rsd] Trusted Tunnel OK {tun.address}:{tun.port}")
            if isinstance(tun.client.tun, UserspaceTun):
                tun.client.tun.set_peer(tun.address)
            dial = await stack.enter_async_context(UserspaceDialPlane(tun.client.tun, tun.address))
            rsd = RemoteServiceDiscoveryService(
                (tun.address, tun.port),
                open_connection=dial.dial,
                auxiliary_metadata=getattr(tun, "auxiliary_metadata", None),
            )
            stack.push_async_callback(rsd.close)
            await rsd.connect()
            log(f"[wifi-rsd] RSD OK udid={rsd.udid} ios={rsd.product_version}")

            async with AfcService(rsd) as afc:
                await afc.listdir("/")
            log("[wifi-rsd] AFC OK")

            def progress(pct: int, *_a) -> None:
                if pct in (0, 50, 90, 100) or pct % 25 == 0:
                    log(f"[wifi-rsd] install {pct}%")

            t_inst = time.time()
            async with InstallationProxyService(lockdown=rsd) as proxy:
                await proxy.install_from_local(app_path, developer=True, handler=progress)
            install_s = time.time() - t_inst
            log(f"[wifi-rsd] install OK in {install_s:.1f}s")

            async with InstallationProxyService(lockdown=rsd) as proxy:
                apps = await proxy.get_apps(bundle_identifiers=[bundle_id])
                if not apps:
                    all_apps = await proxy.get_apps() or {}
                    apps = {k: v for k, v in all_apps.items() if k == bundle_id or bundle_id in k}
            if not apps:
                die(f"install reported OK but bundle not listed: {bundle_id}")
            info = next(iter(apps.values()))
            ver = info.get("CFBundleShortVersionString") if isinstance(info, dict) else None
            build = info.get("CFBundleVersion") if isinstance(info, dict) else None
            app_type = info.get("ApplicationType") if isinstance(info, dict) else None
            log(f"[wifi-rsd] verified {bundle_id} ver={ver} build={build} type={app_type}")

            if expect_version and str(ver) != str(expect_version):
                die(f"DEVICE VERSION MISMATCH: device={ver} expected={expect_version}")
            if expect_build and str(build) != str(expect_build):
                die(f"DEVICE BUILD MISMATCH: device={build} expected={expect_build}")

            launched = False
            launch_detail = None
            if launch:
                launched, launch_detail = await launch_via_rsd(rsd, bundle_id)

            result = {
                "ok": True,
                "transport": "remote-pairing-rsd",
                "usb_present": usb_present,
                "udid": rsd.udid,
                "bundle_id": bundle_id,
                "version": ver,
                "build": build,
                "application_type": app_type,
                "expect_version": expect_version,
                "expect_build": expect_build,
                "install_seconds": round(install_s, 2),
                "total_seconds": round(time.time() - t0, 2),
                "launched": launched,
                "launch": launch_detail,
            }
            print(json.dumps(result), flush=True)
            return result
        except SystemExit:
            raise
        except Exception as e:
            last_err = e
            log(f"[wifi-rsd] attempt failed: {type(e).__name__}: {e}")
            if attempt < retries:
                await asyncio.sleep(min(2 * attempt, 8))
        finally:
            try:
                await stack.__aexit__(None, None, None)
            except Exception:
                pass
            tunnel_service.USE_USERSPACE_TUNNEL = False

    die(f"Wi-Fi RSD deploy failed after {retries} attempts: {last_err}")


def main() -> None:
    require_python()
    p = argparse.ArgumentParser(description="Wi-Fi RSD install/launch (RemotePairing tunnel)")
    p.add_argument("app", type=Path, help="Signed .app directory")
    p.add_argument("--udid", default=None)
    p.add_argument("--bundle-id", default=None)
    p.add_argument("--no-launch", action="store_true")
    p.add_argument("--retries", type=int, default=3)
    p.add_argument("--expect-version", default=None)
    p.add_argument("--expect-build", default=None)
    p.add_argument("--allow-usb", action="store_true", help="Do not abort if USB is also present")
    args = p.parse_args()
    app = args.app.resolve()
    if not app.exists():
        die(f"path not found: {app}")
    bundle = args.bundle_id or read_bundle_id(app)
    udid = args.udid or default_udid()
    launch = not args.no_launch

    if os.environ.get("IOS_NO_LAUNCH", "").strip() in ("1", "true", "yes"):
        launch = False
    expect_version = args.expect_version or os.environ.get("IOS_EXPECT_VERSION", "").strip() or None
    expect_build = args.expect_build or os.environ.get("IOS_EXPECT_BUILD", "").strip() or None
    asyncio.run(
        run_install(
            app,
            bundle,
            udid,
            launch,
            max(1, args.retries),
            expect_version=expect_version,
            expect_build=expect_build,
            require_no_usb=not args.allow_usb,
        )
    )


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        traceback.print_exc()
        die("unexpected error")
