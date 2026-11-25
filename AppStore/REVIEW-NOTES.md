# App Store Connect — Notes for Review (Aether)

## Overview
Aether is a native macOS menu bar utility (`LSUIElement = true`) that visualizes live Wi-Fi signal physics, throughput, multi-hop latency/jitter, local network privacy posture, and nearby Wi-Fi channel spectrum. No user account, login, subscription, or third-party SDK is used.

## How to Test
1. Launch **Aether** — its geometric Wi-Fi icon appears in the top-right macOS menu bar (and opens automatically on first launch).
2. **Connected state:** Click the menu bar icon to inspect:
   - **Hero Stage:** Tap the visualization or hover to switch between **Flux** (live throughput), **Spectrum** (RF channel overlap), and **Route** (4-hop circuit).
   - **Tabs:** `Speed` (live Download/Upload, Received/Sent/Peak totals, active network interfaces, activity readiness, on-demand `✦ Brief` diagnosis, and `Run Test` responsiveness check), `Privacy` (local network exposure, trust zone, and discovered LAN devices), `Wi-Fi` (nearby networks and read-only macOS VPN status with Settings shortcut), and `More` (Simple/Pro view, fixed-width menu bar style, on-demand Public IP lookup, Privacy Policy).
   - **Studio Window:** Click the top-right expand arrow (or press `⌘E`) to open Aether Studio (RF physics, channel spectrum, latency/jitter timeline, LAN devices, event log with `✦ Explain`, and on-device `Ask Aether` command bar).
3. **Disconnected state:** Turn Wi-Fi off or disconnect from a network, then click Aether in the menu bar — the popover focuses directly on the Wi-Fi network picker.

## Permissions & Entitlements
- **Location Services (`com.apple.security.personal-information.location`):** Required by macOS `CoreWLAN` to read the current Wi-Fi SSID/BSSID and display nearby network names during scans. Aether works gracefully without Location access (showing signal metrics, speed, and known profiles) and never transmits location data off the Mac.
- **Outbound Network (`com.apple.security.network.client`):** Used for local gateway ICMP ping, DNS/TCP latency probes (`one.one.one.one:443`), captive portal checks (`http://captive.apple.com/hotspot-detect.html`), and explicit user-triggered actions (`Run Test` via `speed.cloudflare.com` and `Check` Public IP via `https://ipinfo.io/json`).
- **ATS Single-Domain Exception (`captive.apple.com`):** Cleartext HTTP is scoped exclusively to Apple's `captive.apple.com` probe host so hotel/airport captive portal redirects can be detected before TLS is available. All other connections enforce ATS/HTTPS.
- **Not a VPN Provider (Guideline 2.1 / 5.4 Clarification):**
  - Aether is **not** a VPN provider and does **not** create, configure, bundle, proxy, intercept, start, stop, or route network traffic through a VPN. The Mac App Store build does not link `NetworkExtension.framework`, holds no VPN or packet-tunnel entitlements, and does not invoke `SCNetworkConnectionStart` or `SCNetworkConnectionStop`.
  - **What information Aether collects through a VPN:** None. Aether does not inspect, intercept, log, or collect any VPN traffic, browsing activity, VPN credentials, tunnel payloads, or server addresses. It only reads the local display name and Connected/Disconnected state of existing macOS VPN services in memory via read-only `SystemConfiguration` APIs (`SCNetworkServiceCopyAll` and `SCNetworkConnectionGetStatus`).
  - **How Aether uses that information:** Strictly on-device, in memory, to display whether an existing macOS VPN is currently active in the UI (for example, showing a shield indicator on public Wi-Fi) and offering a shortcut to macOS System Settings → VPN.
  - **Whether Aether shares or stores that information:** No. Nothing is stored to disk, persisted across launches, transmitted off the Mac, or shared with any first- or third-party server. Aether has no developer backend, analytics, or third-party SDKs, matching `Data Not Collected` and `PrivacyInfo.xcprivacy`.
- **On-Device Intelligence (`FoundationModels`, weak-linked for macOS 26+):** Optional `✦ Brief`, `✦ Explain`, and `Ask Aether` features run strictly on-demand via Apple’s built-in on-device `SystemLanguageModel.default` with zero cloud calls, zero external AI APIs, and an instant deterministic local fallback on macOS 15 or when Apple Intelligence is unavailable.
- **Launch at Login:** Disabled by default (`SMAppService.mainApp`), enabled only when the user explicitly toggles `LOGIN: ON`.
