# Flashing the R8000 as a Repeater

Turn the unused Netgear R8000 into a Wi-Fi repeater that rebroadcasts the Eero Pro 6E
signal from the bedroom into the office, to beat the current 15–20 Mbps there.
Firmware: DD-WRT, latest beta build for the R8000.

## What is in this repo

| File | Runs on | Part |
|---|---|---|
| `scripts/fetch-firmware.sh` | laptop | A – downloads and verifies the newest R8000 beta `.chk` + `.bin` into `firmware/` |
| `config.env.example` | laptop | C – copy to `config.env` (git-ignored) and fill in SSIDs, passwords, IPs |
| `scripts/push-config.sh` | laptop | C – copies `config.env` to the router and runs the bridge script over SSH |
| `scripts/repeater-bridge.sh` | router | C – verifies nvram key names, prints the plan, applies with `--commit` |
| `scripts/link-stats.sh` | router | D – RSSI / rate / client list for comparing positions |
| `scripts/diagnose.sh` | router | troubleshooting – dumps wireless config, scans for the Eero, checks gateway |

Router-side scripts are POSIX `sh` (DD-WRT's BusyBox ash). They are streamed over SSH
and never stored on the router's flash. Nothing in this repo should ever contain a
real password: `config.env` and `firmware/` are git-ignored.

## How to use this guide

This is written so you can run it yourself or hand chunks to Claude Code. Most of the
flashing is clicking through the DD-WRT web interface and can't be scripted. The part
worth routing to Claude Code is Part C — configuring the repeater bridge over SSH with
`nvram` commands instead of the flaky GUI, which is where this setup usually goes wrong.

**Two things that can brick the router — read before anything else:**

1. **Never do a 30-30-30 reset on the R8000.** It's a Broadcom ARM router and the
   30-30-30 reset can brick it. Use only the reset methods in these steps.
2. **Let every flash and every reset fully complete.** Don't touch power or unplug
   mid-process — give each step a few minutes even if it looks done. Most R8000
   bricking stories come from interrupting it.

## The physical setup (how it's wired)

Everything up to the final placement is done wired, on a bench or desk with the R8000
sitting next to your laptop. Wireless comes in only at the very end, when the R8000 is
positioned and bridging to the Eero.

1. Plug the R8000 into power. Use the power button on the back; wait for it to fully
   boot (lights settle, ~1–2 minutes).
2. Run an Ethernet cable from your laptop to one of the R8000's four LAN ports — the
   yellow ports, not the Internet/WAN port. The WAN port stays empty for this whole process.
3. That wired link is how you reach the router for everything: the browser flashing
   (Part B) and the SSH config (Part C) both go over this same cable. Your laptop talks
   to the R8000 directly — the Eero isn't involved yet.
4. Set your laptop's Wi-Fi off (or ignore it) so the browser and SSH definitely use the
   Ethernet link, not your house network.

How you push to the device:

* **Flashing firmware (Part B):** through the web interface in a browser — you upload
  the firmware file to the router. No command line.
* **Configuring the bridge (Part C):** over SSH across that same Ethernet cable —
  `ssh root@192.168.1.1` (the DD-WRT default), password is the admin password you set.
  That's the session you hand to Claude Code, or run `scripts/push-config.sh`.
* **Final placement (Part D):** only now does it go wireless — unplug it from the
  laptop, move it to the bedroom, power it there, and it bridges to the Eero over Wi-Fi.
  If you need to reconfigure after that, you can still SSH to it at its new LAN IP
  (192.168.4.2).

## Part A — Gather before you start

1. A laptop with an Ethernet cable. Do all of this wired, not over Wi-Fi.
2. The latest R8000 beta build from
   <https://download1.dd-wrt.com/dd-wrtv2/downloads/betas/>. You need two files: the
   factory-to-DD-WRT `.chk` (flashed from stock Netgear) and the webflash `.bin`
   (flashed later from inside DD-WRT). Either browse there (newest dated folder, then
   the R8000 folder) or run:

   ```sh
   scripts/fetch-firmware.sh
   ```

   It walks back from the newest dated folder until it finds one with an R8000 build,
   downloads both files into `firmware/`, and refuses to keep them unless the `.chk`
   carries the R8000 board ID (`U12H315T00`) and the `.bin` has a valid TRX header.
   It writes `firmware/SHA256SUMS` so you can tell later exactly which build went on.
3. Your Eero network's Wi-Fi name (SSID) and password, exactly as written.
4. Your Eero's gateway IP address — usually 192.168.4.1; confirm in the Eero app under
   the gateway's details.

## Part B — Flash DD-WRT (web interface, do it yourself)

This part is point-and-click in the browser; it isn't scriptable. Do it wired.

1. Power on the R8000 alone. Connect the laptop to one of its LAN ports by Ethernet.
2. Browse to 192.168.1.1 (or routerlogin.net) and log into the stock Netgear interface.
3. Factory reset the stock firmware first (Advanced > Administration > Backup Settings >
   Erase, or the recessed reset button per Netgear's method). Let it finish and reboot.
4. Go to Advanced > Administration > Router Update / Firmware Upgrade.
5. Upload the DD-WRT `.chk` (factory-to-DD-WRT) file and start the flash. Wait — don't
   touch anything until it fully completes and reboots (several minutes).
6. Browse to 192.168.1.1 again — you should see DD-WRT. Set a username and password
   when prompted.
7. Reset to factory defaults from inside DD-WRT: Administration > Factory Defaults >
   Restore. Let it reboot.
8. (Recommended) From inside DD-WRT, Administration > Firmware Upgrade, flash the
   `.bin` (webflash) build to land on the clean full build. Let it complete, then do one
   more factory-defaults reset from the GUI.

You now have a clean DD-WRT on the R8000. Good checkpoint.

## Part C — Configure as a repeater bridge (route this to Claude Code)

This is the part that usually goes wrong in the GUI. Once DD-WRT is on and you can
reach it, enable SSH (Services > Services > Secure Shell > SSHd = Enable, Save + Apply).

The target config:

* **Bridge radio:** a 5 GHz radio (`wl1`), set to Repeater Bridge mode (`apstawet`).
* **Bridged SSID:** exactly matches the Eero SSID (same spelling, same case).
* **Bridged security:** same mode (WPA2/WPA3) and same password as the Eero.
* **Virtual interface:** a second SSID on that radio, new and unique (`Office-Ext`) —
  the network your office devices join. Its own security.
* **Local IP:** a free address on the Eero subnet, 192.168.4.2 (must not collide with
  the Eero's DHCP range).
* **Subnet mask:** 255.255.255.0. **Gateway** and **local DNS:** the Eero's IP, 192.168.4.1.
* **WAN:** disabled (repeater bridge has no separate WAN). DHCP server off, SPI firewall off.

### Scripted

```sh
cp config.env.example config.env     # fill in SSIDs, passwords, IPs
scripts/push-config.sh               # dry run: checks this build's nvram keys, prints every nvram set
scripts/push-config.sh --commit      # apply + nvram commit
```

The dry run first lists the radios on the build and confirms each nvram variable name
exists in the current defaults; it refuses to commit if any expected key is missing,
since DD-WRT variable names vary slightly by revision. Passwords are masked in the
printed plan. After `--commit`, power-cycle the R8000 (off ~30 seconds, back on — a
normal power cycle, NOT a 30-30-30 reset). Add `--reboot` to have it reboot itself instead.

After the change the router answers on 192.168.4.2 and no longer runs a DHCP server, so
to reach it over the bench cable again give the laptop a static address such as
192.168.4.50/24.

### Hand-off brief for Claude Code (if doing it interactively instead)

> SSH into a DD-WRT R8000 at [its IP]. Configure wl1 (5 GHz) as a repeater bridge onto
> SSID [Eero SSID] with WPA2 password [pw]. Add a virtual AP with SSID Office-Ext. Set
> LAN IP 192.168.4.2/24, gateway and DNS 192.168.4.1, disable WAN. Use nvram set/commit
> and reboot. Confirm the variable names against this build's defaults first, and show me
> the full command list before committing.

The nvram plan it should arrive at is the one in `scripts/repeater-bridge.sh`.

## Part D — Test and position

1. Before placing it in the bedroom, confirm the bridge works near the Eero: join the
   new Office-Ext SSID and check you have internet.
2. Baseline the spot: stand where you plan to put the R8000 (bedroom), phone on the Eero
   network, run a speed test. That's what the repeater has to work with. Avoid spots near
   the boiler and plumbing.
3. Place the R8000 there, then go to the office and speed-test on Office-Ext — the office
   is what counts, not next to the repeater.
4. Try 2–3 bedroom positions and keep the best office number. Even a modest result should
   crush 15–20 Mbps.

Compare signal and negotiated rate at each position, not bars:

```sh
ssh root@192.168.4.2 'sh -s' < scripts/link-stats.sh              # one snapshot
ssh root@192.168.4.2 'sh -s -- --watch 5' < scripts/link-stats.sh # live, every 5 s
```

RSSI closer to 0 is better: around −60 dBm is good, −70 is fine, −80 is poor.

## If the bridge won't connect (common on R8000)

```sh
ssh root@<router-ip> 'sh -s' < scripts/diagnose.sh                 # default radio wl1
ssh root@<router-ip> 'sh -s -- --radio wl2' < scripts/diagnose.sh
```

This dumps the radio's nvram config (passwords masked), scans and reports whether the
R8000 even sees the Eero SSID on that radio, and pings the gateway and the internet.

* Double-check the bridged SSID and password exactly match the Eero (case-sensitive).
* Make sure the R8000's local IP is on the same subnet as the Eero and isn't a duplicate.
* Try the other 5 GHz radio (`RADIO="wl2"` in `config.env`), or fall back to 2.4 GHz
  (`wl0`) for the bridge link — slower but connects through walls more reliably, which
  is fine given the goal. Re-run `push-config.sh --commit` after changing it.
* If the Eero is in WPA3 transition mode and the bridge refuses to associate, set
  `EERO_SEC="psk2 psk3"`; otherwise leave it at `psk2`.
* Redo wireless security after any SSID change — it often resets.
* If it gets wedged, do a GUI factory-defaults reset and redo Part C. (Never 30-30-30.)

Note: the R8000 is end-of-service from Netgear, so there's nothing to lose by flashing
it. To revert, flash stock Netgear firmware from the DD-WRT GUI and factory-reset.
