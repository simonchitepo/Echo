# Firewall & LAN Connectivity (Echo)

Echo's LAN mode uses **WebSockets over TCP** (default port: **4040**).  
Devices must be on the same LAN (same Wi‑Fi / Ethernet network), and the **host** must allow inbound TCP connections on the chosen port.

---

## Windows (Windows Defender Firewall)

### Option A — Allow the app (recommended if you run a Windows desktop build)
1. Open **Windows Security** → **Firewall & network protection**
2. Click **Allow an app through firewall**
3. Click **Change settings** → **Allow another app...**
4. Browse to your built desktop executable (for Flutter: `build\windows\x64\runner\Release\<yourapp>.exe`)
5. Add it and tick **Private** (and **Public** only if you really need it)

### Option B — Open a specific TCP port (e.g., 4040)
**GUI**
1. Open **Windows Defender Firewall with Advanced Security**
2. Click **Inbound Rules** → **New Rule...**
3. Select **Port** → **TCP**
4. **Specific local ports**: `4040` (or your configured port)
5. **Allow the connection**
6. Choose profiles: **Private** (recommended)
7. Name it: `Echo LAN WebSocket (4040)`

**Command line (Run PowerShell as Administrator)**
```powershell
New-NetFirewallRule -DisplayName "Echo LAN WebSocket 4040" -Direction Inbound -Protocol TCP -LocalPort 4040 -Action Allow -Profile Private
```

To remove it later:
```powershell
Remove-NetFirewallRule -DisplayName "Echo LAN WebSocket 4040"
```

---

## macOS
1. **System Settings** → **Network** → confirm you are on the same LAN
2. **System Settings** → **Privacy & Security** → **Firewall**
3. Turn Firewall **On**
4. Click **Options...** and add/allow your app, or temporarily disable firewall while testing

---

## Linux (UFW)
If you use UFW:
```bash
sudo ufw allow 4040/tcp
sudo ufw status
```

---

## Router / Wi‑Fi notes
- This is **LAN-only**. You do **not** need port forwarding on your router for devices on the same Wi‑Fi.
- Some guest Wi‑Fi networks isolate clients (no device-to-device traffic). Use the normal SSID, not “Guest”.
- If connecting from Web, use the host’s **LAN IP** (e.g., `ws://192.168.1.20:4040`).

---

## Troubleshooting checklist
- Confirm host IP: `ipconfig` (Windows) / `ifconfig` or `ip a` (Linux) / Network settings (macOS)
- Ensure the chosen port matches in both host and client settings
- Temporarily disable firewall to confirm it’s the blocker, then re-enable with a proper rule
- If using Web in Chrome, ensure you’re not blocked by mixed-content rules when hosted over HTTPS
