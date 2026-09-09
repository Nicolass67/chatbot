# SideStore iOS 27 lockdown transport fallback

Overlay applied on top of:

- SideStore `610f3b16` (0.7.0 nightly)
- minimuxer submodule `2e72b199`

## What this changes

SideStore 0.7.0 classifies a hybrid iLoader pairing file as `.rppairing` because RP keys are present, then times out on TCP 49152. This overlay:

1. Probes TCP 49152 and 62078
2. Prefers RemotePairing only if 49152 is reachable
3. Falls back to lockdown 62078 for compatible operations (UDID, AFC, instproxy, misagent, heartbeat)
4. Returns `requiresRemotePairing` for JIT / iOS 17+ debug instead of faking a 62078 debug proxy
5. Serializes lockdown/misagent sessions and retries BrokenPipe with a fresh connection (max 3 attempts)
6. Does not leave minimuxer stuck in `inprogress` if the fake usbmuxd fails; lockdown TCP 62078 is enough to start

Pairing files, LocalDevVPN, and Device IP are not modified by this overlay.

## Build

GitHub Actions: `.github/workflows/sidestore-ipa-flash.yml`
