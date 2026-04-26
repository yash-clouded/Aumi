<p align="center">
  <h1 align="center">Aumi</h1>
  <p align="center"><strong>Android Userface in Mac Integrated</strong></p>
  <p align="center">
    Answer phone calls on your Mac. Read and reply to SMS. Mirror your screen.<br/>
    All wirelessly, all encrypted, all free.
  </p>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Android-9%2B-3DDC84?logo=android&logoColor=white" alt="Android 9+"/>
  <img src="https://img.shields.io/badge/macOS-14%20Sonoma%2B-000000?logo=apple&logoColor=white" alt="macOS 14+"/>
  <img src="https://img.shields.io/badge/Encryption-AES--256--GCM-blue" alt="AES-256-GCM"/>
  <img src="https://img.shields.io/badge/Cost-%E2%82%B90%2Fmonth-brightgreen" alt="Free"/>
</p>

---

## What is Aumi?

Aumi brings Apple's seamless iPhone ↔ Mac experience to Android users. Pair your Android phone with your Mac once, and everything just works:

- 📞 **Phone calls on Mac** — Your Mac rings when your phone rings. Answer, decline, or let it go to voicemail — all from your laptop.
- 💬 **SMS from Mac** — Receive, reply, and compose new text messages without touching your phone.
- 📧 **Gmail notifications** — See emails and reply/archive directly from macOS notifications.
- 🖥️ **Screen mirroring** — Mirror your Android screen to your Mac at 60fps with ~40ms latency.
- 📋 **Clipboard sync** — Copy on one device, paste on the other.
- 📁 **File transfer** — Drag and drop files between devices.

## How It Works

```
┌─────────────────┐                              ┌──────────────────┐
│  Android Phone  │◄────── Same WiFi ──────────►│   MacBook        │
│  (Kotlin + C++) │   TCP (video + control)      │   (Swift/AppKit) │
│                 │   UDP (audio)                │                  │
│                 │   ~30-50ms latency           │                  │
└────────┬────────┘                              └────────┬─────────┘
         │                                                │
         │         ┌──────────────────┐                   │
         └────────►│  Relay Server    │◄──────────────────┘
                   │  (Oracle Cloud)  │
                   │  Mumbai, Free    │   ◄── Only when not on same WiFi
                   │  ~100-180ms      │
                   └──────────────────┘
```

**Same WiFi (LAN):** Direct connection. Raw H.264 video over TCP + Opus audio over UDP. No servers involved. Latency comparable to Apple Continuity.

**Different networks:** Automatic fallback through relay server (Mumbai). WebRTC handles NAT traversal. Still end-to-end encrypted.

## Features

### 📞 Phone Calls
| Feature | Status |
|---|---|
| Incoming call notification on Mac | ✅ |
| Mac rings with ringtone (like FaceTime) | ✅ |
| Answer / Decline from Mac | ✅ |
| Bidirectional call audio | ✅ (speakerphone bridge) |
| Missed call notification in Notification Center | ✅ |
| Caller name + photo from contacts | ✅ |

### 💬 SMS
| Feature | Status |
|---|---|
| Receive SMS as Mac notification | ✅ |
| Reply to SMS from notification | ✅ |
| Compose new SMS from Mac | ✅ |
| Delivery confirmation (Sent ✓ / Delivered ✓✓) | ✅ |
| Multi-part SMS (>160 chars) | ✅ |

### 📧 Gmail
| Feature | Status |
|---|---|
| Email notifications on Mac | ✅ |
| Reply to emails from Mac | ✅ |
| Archive emails from Mac | ✅ |

### 🖥️ Screen Mirroring
| Feature | Status |
|---|---|
| 60fps hardware-encoded H.264 | ✅ |
| ~40ms latency on LAN | ✅ |
| Resizable window with Metal rendering | ✅ |
| 720p / 1080p toggle | ✅ |

### 📋 Clipboard & 📁 Files
| Feature | Status |
|---|---|
| Text / URL / Image clipboard sync | ✅ |
| Drag-and-drop file transfer | ✅ |
| Resumable chunked transfer (up to 4GB) | ✅ |
| SHA-256 integrity verification | ✅ |

## Architecture

| Layer | Android | macOS |
|---|---|---|
| **Audio I/O** | Oboe/AAudio (C++) — 5ms latency | AVAudioEngine — 5ms latency |
| **Audio Codec** | Opus 10ms frames via libopus | Opus decode via libopus |
| **Video Encoder** | MediaCodec H.264 Baseline (hardware) | — |
| **Video Decoder** | — | VideoToolbox (hardware, <1ms) |
| **Video Render** | — | MTKView (Metal GPU) |
| **Call Handling** | InCallService | CallManager + floating NSWindow |
| **SMS** | BroadcastReceiver + SmsManager | UNUserNotificationCenter |
| **Notifications** | NotificationListenerService (Gmail) | UNUserNotificationCenter |
| **Discovery** | NsdManager (mDNS) | NWBrowser/NWListener |
| **Encryption** | AES-256-GCM (javax.crypto) | AES-256-GCM (CryptoKit) |
| **Key Exchange** | X25519 + HKDF-SHA256 | Curve25519 + HKDF (CryptoKit) |

## Project Structure

```
Aumi/
├── android/          # Kotlin + C++ (Oboe/Opus)
├── macos/            # Swift / AppKit
├── relay-server/     # Node.js WebSocket relay
└── shared/           # Protocol definitions
```

## Requirements

| Component | Requirement | Cost |
|---|---|---|
| Android phone | Android 9+ (any manufacturer) | — |
| Mac | macOS 14 Sonoma+, Apple Silicon | — |
| Relay server | Oracle Cloud Free Tier (Mumbai) | **₹0/month** |
| STUN server | Google public STUN | **Free** |

## Security

- **End-to-end encrypted** — AES-256-GCM on all data, including relay path
- **X25519 key exchange** — Keys derived via HKDF-SHA256, never transmitted
- **Key storage** — Android Keystore (hardware-backed) + macOS Keychain
- **Zero-knowledge relay** — Server forwards encrypted blobs, cannot read content
- **QR code pairing** — One-time scan, keys persist across sessions

## Latency Targets

| Metric | Same WiFi | Different Network |
|---|---|---|
| Call notification | <200ms | <500ms |
| Call audio | **<30ms** | <150ms |
| Screen mirroring | **<50ms @ 60fps** | <350ms @ 30fps |
| SMS notification | <200ms | <500ms |
| Clipboard sync | <500ms | <1.5s |
| File transfer | >20 MB/s | >2 MB/s |

## Getting Started

### 1. Set up the relay server (one-time)
```bash
# Sign up for Oracle Cloud Free Tier (Mumbai region)
# Create an Always Free ARM instance
# SSH in, then:

git clone https://github.com/YOUR_USERNAME/Aumi.git
cd Aumi/relay-server
npm install
npm start
```

### 2. Build the Mac app
```bash
cd Aumi/macos
open Aumi.xcodeproj
# Build and run (⌘R)
```

### 3. Build the Android app
```bash
cd Aumi/android
./gradlew assembleDebug
# Install APK on your phone
```

### 4. Pair
1. Open Aumi on Mac → QR code appears
2. Open Aumi on Android → Scan the QR code
3. Done. They'll auto-connect from now on.

## License

MIT

---

<p align="center">
  <sub>Built because Android users deserve Continuity too.</sub>
</p>
