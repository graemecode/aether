# App Store Connect — Notes for Review (Aether)

## Overview
Aether is a native macOS menu bar utility (`LSUIElement = true`) that visualizes live Wi-Fi signal physics, throughput, multi-hop latency/jitter, local network privacy posture, and nearby Wi-Fi channel spectrum. No user account, login, subscription, or third-party SDK is used.

## How to Test
1. Launch **Aether** — its geometric Wi-Fi icon appears in the top-right macOS menu bar (and opens automatically on first launch).
2. **Connected state:** Click the menu bar icon to inspect:
   - **Hero Stage:** Tap the visualization or hover to switch between **Flux** (live throughput), **Spectrum** (RF channel overlap), and **Route** (4-hop circuit).
   - **Tabs:** `SPEED` (activity readiness, live RF insights, and `Run Test` responsiveness check), `PRIVACY` (local network exposure, trust zone, and discovered LAN devices), `WI-FI` (nearby networks and system VPN toggle), and `MORE` (Simple/Pro view, menu bar style, on-demand Public IP lookup, Privacy Policy).
   - **Studio Window:** Click the top-right expand arrow (or press `⌘E`) to open Aether Studio.
3. **Disconnected state:** Turn Wi-Fi off or disconnect from a network, then click Aether in the menu bar — the popover focuses directly on the Wi-Fi network picker.

## Permissions & Entitlements
- **Location Services (`com.apple.security.personal-information.location`):** Required by macOS `CoreWLAN` to read the current Wi-Fi SSID/BSSID and display nearby network names during scans. Aether works gracefully without Location access (showing signal metrics, speed, and known profiles) and never transmits location data off the Mac.
- **Outbound Network (`com.apple.security.network.client`):** Used for local gateway ICMP ping, DNS/TCP latency probes (`one.one.one.one:443`), captive portal checks (`http://captive.apple.com/hotspot-detect.html`), and explicit user-triggered actions (`Run Test` via `speed.cloudflare.com` and `Check` Public IP via `https://ipinfo.io/json`).
- **ATS Single-Domain Exception (`captive.apple.com`):** Cleartext HTTP is scoped exclusively to Apple's `captive.apple.com` probe host so hotel/airport captive portal redirects can be detected before TLS is available. All other connections enforce ATS/HTTPS.
- **Not a VPN Provider:** Aether does not create, bundle, or route traffic through a VPN service. It only displays the connection state of VPN configurations already installed by the user via `SCNetworkConnection` and lets the user toggle them.
- **Launch at Login:** Disabled by default (`SMAppService.mainApp`), enabled only when the user explicitly toggles `LOGIN: ON`.
