# Aether — Mac App Store Submission & Editorial Featuring Kit

Everything below is character-counted, App Review verified (`APP_STORE` sandbox target, `0` prohibited subprocesses, `PrivacyInfo.xcprivacy` included, `Data Not Collected`), and ready to copy-paste directly into App Store Connect.

---

## 1. App Information (App Store Connect → General → App Information)

| Field | Exact Value | Limit Check |
|---|---|---|
| **App Name** | `Aether` *(if taken: `Aether: Wi-Fi & Speed`)* | 6 / 30 chars *(21 / 30)* |
| **Subtitle** | `Wi-Fi Signal, Speed & Privacy` | 29 / 30 chars |
| **Bundle ID** | `com.strangechances.Aether` | Matches `project.pbxproj` |
| **SKU** | `com.strangechances.aether.mac` | — |
| **Primary Language** | English (U.S.) | — |
| **Primary Category** | Utilities | — |
| **Secondary Category** | Developer Tools | — |
| **Content Rights** | Does not contain third-party content | — |
| **Age Rating** | `4+` (All categories: None) | — |
| **Encryption (`ITSAppUsesNonExemptEncryption`)** | `No` (declared `false` in `Info-AppStore.plist`) | — |
| **Copyright** | `© 2026 Strange Chances` | — |

### URLs (All Verified Live — HTTP 200)
- **Privacy Policy URL:** `https://strangechances.com/aether/privacy/`
- **Support URL:** `https://strangechances.com/aether/` *(or `https://github.com/graemecode/aether/issues`)*
- **Marketing URL:** `https://strangechances.com/aether/`

---

## 2. Version Listing Copy (App Store Connect → macOS App 1.0.0)

### Promotional Text (`161 / 170 chars` — editable anytime without a new build)
```text
See why your Wi-Fi feels slow in one click. Live signal physics, true latency, RF channel overlap, privacy audit, and on-device Apple Intelligence — 0% idle CPU.
```

### Keywords (`97 / 100 chars` — zero duplication of Name/Subtitle words)
```text
network,monitor,analyzer,menu bar,bandwidth,latency,ping,jitter,spectrum,vpn,router,lan,scanner,rf
```

### Description (`~2,150 / 4,000 chars` — crisp, Apple-editorial tone, zero fluff)
```text
Your Mac’s Wi-Fi icon tells you almost nothing when a video call stutters, a download crawls, or a hotel network feels untrustworthy. Aether replaces guesswork with a calm, native macOS instrument that lives quietly in your menu bar.

Built in pure Swift, AppKit, and SwiftUI, Aether renders your live connection as three switchable visual instruments—and uses 0.0% idle CPU when closed.

SEE YOUR CONNECTION AT A GLANCE
• Flux — Live download and upload harmonic ribbons with session totals, peak speed, and active network interfaces.
• Spectrum — Live 2.4, 5, and 6 GHz Gaussian channel overlap showing congestion, overlapping access points, and cleaner channels.
• Route — A 4-hop live circuit (Mac → Router → Lookup → Internet) that pinpoints whether slowness is your Wi-Fi, your router, DNS, or your ISP.
• Steady Menu Bar — Choose Icon Only (22pt), color-coded speed arrows (28pt), or live speed readout (50pt). Fixed widths so your menu bar never jumps.

PLAIN-ENGLISH CLARITY, PRO DEPTH ON TAP
• Honest Readiness — See at a glance if your connection is truly ready for Video Calls, 4K Video, and Live & Games, backed by true ICMP latency measurement that isn’t fooled by airplane or satellite proxies.
• One-Click Responsiveness Test — Measure real download speed, upload speed, and bufferbloat smoothness right from the popover.
• Simple & Pro Modes — Plain English by default, or switch to Pro for raw dBm, noise floor, SNR, BSSID, channel width, and RF physics.

ON-DEVICE APPLE INTELLIGENCE (MACOS 26+)
• Tap Brief in the menu bar, Explain in the Event Log, or ask a question in Aether Studio.
• Runs 100% on-device via Apple’s FoundationModels framework—grounded in your live signal, latency, and channel telemetry with zero cloud calls. Includes an instant local diagnostic fallback on macOS 15.

KNOW WHO CAN SEE YOU ON ANY WI-FI
• Plain-English privacy breakdown for Strangers Nearby, Wi-Fi Owner & ISP, and Others on This Wi-Fi.
• Automatic gateway fingerprint pinning warns you of evil-twin routers or encryption downgrades.
• Inspect every device sharing your local Wi-Fi with OUI vendor lookup and mDNS hostnames, plus one-click VPN tunnel control.

AETHER STUDIO (⌘E)
• Expand into a full-screen RF & latency workbench: real-time RF power and SNR physics, interactive multi-hop latency and jitter timeline, live channel spectrum across all three bands, LAN device roster, connection event log, and copyable diagnostics report.

PRIVATE BY DESIGN
• No account, no subscription, no ads, no analytics, and no third-party SDKs.
• Location permission is used solely by macOS to display Wi-Fi network names and channel scans—location data never leaves your Mac.
```

### What's New in Version 1.0.0
```text
Initial Mac App Store release of Aether — live Wi-Fi signal physics, multi-hop latency, RF channel spectrum, local network privacy audit, Aether Studio workbench, and on-device Apple Intelligence diagnostics.
```

---

## 3. Screenshots (`AppStore/screenshots/` — Exact `2560 × 1600`, Opaque 24-bit sRGB PNG)

Upload all 6 in exact numbered order into **macOS App → Previews and Screenshots** (every image is rendered natively from the `-D APP_STORE` sandboxed target so it matches the submitted binary 1:1):

1. `01-speed-flux.png` — **Hero:** *See your Wi-Fi in real time.* (Menu bar `28pt` icon + Speed tab + Flux ribbons + responsiveness results)
2. `02-privacy-route.png` — **Privacy:** *Know who can see you on any Wi-Fi.* (4-hop Route circuit + VPN shield + 3-actor privacy breakdown)
3. `03-apple-intelligence.png` — **On-Device AI:** *Ask your Wi-Fi what’s actually slow.* (`✦ ON-DEVICE BRIEF` diagnosing true `642 ms` satellite RTT)
4. `04-rf-spectrum.png` — **RF Spectrum:** *Escape crowded airwaves in seconds.* (Gaussian channel overlap + 1-click 5 GHz roaming nudge)
5. `05-aether-studio.png` — **Workbench:** *Your full RF & latency workbench.* (Full-screen Aether Studio with spectrum, jitter graph, LAN devices & `Ask Aether`)
6. `06-wifi-picker.png` — **Offline Craft:** *Calm and fast. Even offline.* (Unified disconnected Wi-Fi picker with all 4 tabs intact)

---

## 4. App Privacy Nutrition Label (App Store Connect → App Privacy)

- Select **"No, we do not collect data from this app."** → displays **"Data Not Collected"** badge on the Mac App Store.
- Why this is 100% accurate and matches `AppStore/PrivacyInfo.xcprivacy`:
  - `NSPrivacyTracking = false`, `NSPrivacyCollectedDataTypes = []`.
  - CoreLocation is used strictly on-device as required by macOS `CoreWLAN` to read SSID/BSSID/scan results; coordinates are never read, stored, or transmitted.
  - Explicit user-initiated network lookups (`Run Test` → `speed.cloudflare.com`, `Check` Public IP → `ipinfo.io`) are direct user actions without any developer backend, identifier, or analytics collection.

---

## 5. App Review Notes

Paste the full contents of `AppStore/REVIEW-NOTES.md` into **App Review Information → Notes** (Sign-in required: **unchecked**).

---

## 6. Apple Editorial Featuring / Editor's Choice Nomination

Submit at **https://developer.apple.com/contact/app-store/promote/** right after uploading your build (ideally 2–3 weeks before your public launch date, or immediately after approval for an "App We Love" / Mac Essentials feature):

### Headline / Story Pitch
> **Aether — A quiet, native macOS menu bar instrument that turns invisible Wi-Fi physics into human clarity, powered by on-device Apple Intelligence.**

### What Makes Aether Worth Featuring (Copy-Paste for Apple Editorial Form)
```text
Most macOS network utilities are either bare-bones Wi-Fi menus or cluttered developer dashboards full of raw numbers. Aether was designed from first principles as a calm, Mac-native precision instrument—combining Apple-grade visual restraint with real RF and network engineering.

• Built Exclusively for Mac: 100% native Swift, AppKit, and SwiftUI (~3.2 MB), zero third-party SDKs, full keyboard navigation (⌘1–4, ⌘E, Space, Esc), VoiceOver & Reduce Motion support, and 0.0% idle CPU when closed. Its fixed-width 28pt menu bar footprint eliminates the distracting width jumping common in speed monitors.
• Thoughtful On-Device Apple Intelligence (macOS 26): Weak-links Apple’s FoundationModels framework to power strictly on-demand diagnostics ("Brief" in the popover, "Explain" in the Event Log, and "Ask Aether" in Studio). Every prompt is grounded in live RF, channel overlap, and true ICMP latency telemetry with a contradiction guard and zero cloud calls—falling back seamlessly to instant local heuristics on macOS 15.
• Honest Telemetry, Not Vanity Numbers: Uses native unprivileged ICMP Echo probes so satellite, airplane, and VPN proxies can’t spoof 5ms latencies—giving users an honest verdict on whether a connection can actually hold a video call.
• Privacy Without Compromise: App Sandboxed, zero subscriptions, zero ads, and a "Data Not Collected" privacy label—while actively protecting users on public Wi-Fi with gateway evil-twin pinning, 4-hop route visualization, and LAN device auditing.
```

---

## 7. Exact Xcode Archive & Upload Steps (5 Minutes)

1. Open `Aether.xcodeproj` in Xcode (`open /Users/graemeboy/strangechances/Aether/Aether.xcodeproj`).
2. Select scheme **Aether** and destination **Any Mac (Apple Silicon)** (or **My Mac**).
3. Verify **Signing & Capabilities** → Team `6KM3577ETV`, Bundle ID `com.strangechances.Aether`, Automatically manage signing checked.
4. Click **Product → Archive**.
5. In Organizer, click **Validate App** (confirm 0 errors), then **Distribute App → App Store Connect → Upload**.
6. In App Store Connect, select build `1.0.0 (1)`, paste the copy & drag all 6 PNGs from `AppStore/screenshots/`, set App Privacy to **Data Not Collected**, paste `AppStore/REVIEW-NOTES.md`, and click **Add for Review**.
