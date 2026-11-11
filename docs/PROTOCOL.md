# Earbud control protocol (OPPO / OnePlus / realme)

The control protocol these earbuds speak over Bluetooth Classic. Entries marked **[observed]**
were confirmed live against a OnePlus Nord Buds 3r from macOS (`tools/probe.swift`). Everything
else is documented behaviour that hasn't been exercised on hardware yet.

## Transport

* **Not BLE.** Control runs over **Bluetooth Classic RFCOMM (SPP)**. Find the channel through SDP.
* Service UUIDs:
  * `0000079A-D102-11E1-9B23-00025B00A5A5`: primary. **[observed]** SDP → RFCOMM channel 15 on Nord Buds 3r.
  * `00001107-D102-11E1-9B23-00025B00A5A5`: alternate SPP UUID on some models.
  * `0100079A-…`/`0200079A-…`: GATT variants ("SPP over GATT", used by LE-audio products).
* Device MTU reported over RFCOMM: 669. Frames are capped at 660 bytes.

## Framing

```
AA | varint(L) | flags | 00 | [fsn] | chunk
```
* `AA`: start of frame.
* `varint(L)`: little-endian base-128 (7 bits per byte, bit 7 = continuation). `L` = number of
  bytes after the varint (`flags` + `00` + optional `fsn` + `chunk`).
* `flags & 3`: 0 = complete packet, 1 = first fragment, 2 = middle, 3 = last.
* `fsn`: fragment sequence number, present only when `flags != 0`.
* The chunks of a fragmented packet concatenate into one inner packet.

## Inner packet

```
cmd:u16le | seq:u8 | len:u16le | payload[len]
```
* `seq` is a per-device counter (0…255, wraps). A response echoes the request's `seq`.
* Response `cmd` = request `cmd | 0x8000`. Payload byte 0 of a response is a **status** (0 = OK).
* Command groups (`cmd & 0x7F00`): `0x01xx` get, `0x02xx` notifications, `0x03xx` OTA,
  `0x04xx` set, `0x05xx` device→host requests/events, `0x0Fxx` debug.

Example **[observed]**: get battery, seq 2 → `AA 07 00 00 06 01 02 00 00`.

## Capability discovery: `0x0100`

The response is `status, bitmap…`. Bit *i* (LSB-first across bytes) enables the command group
`capabilityTable[i]` in `Sources/BudsKit/Capabilities.swift`. Commands
`0x0100-0x0104, 0x0106, 0x010B, 0x010D, 0x0F00, 0x0F03, 0x0F04` are always allowed.
**[observed]** Nord Buds 3r: `00 FF 74 D0 A3 05 14 00 06`.

## Commands used by the Mac app

| cmd | name | request payload | response payload (after status) |
|---|---|---|---|
| 0x0105 | get version | – | `n`, then ASCII CSV of `n` triples `type,kind,ver` **[observed]** `03` + `1,2,112,2,2,112,3,2,101` |
| 0x0106 | get battery | – | `n, (type, level)×n`; level bit7 = charging, bits0-6 = %; type 1=L 2=R 3=case. Neckbands report a single entry (type 1) **[observed]** |
| 0x0108 | get key functions | – | `n, (type, button, action, function)×n` **[observed]** 24 entries |
| 0x0109 | get ear status | – | `n, (type, flags)×n`; in-case = bit0 **clear**, in-ear = bit1, lid-closed = bit2 **clear** **[observed]** |
| 0x010D | get feature switches | `n, featureId×n` | `n, (featureId, on)×n` **[observed]** |
| 0x0112 | get multi-connect hosts | – | `n, entry×n`; entry = `mac[6], len, state, flags, nameLen, name…` (`len` counts the bytes after itself). See [Hosts](#hosts-0x0112--event-6) **[observed]** |
| 0x0401 | set key functions | `n, (type, button, action, function)×n` | – **[observed]** |
| 0x0403 | set feature switch | `featureId, on(0/1)` | – **[observed]** |
| 0x0200 | get notification events | – | `n, eventId×n` |
| 0x0205 | subscribe to events | `n, eventId×n` | – (fallback 0x0201 `eventId`, one per event) |
| 0x0204 | **device event** | – | `eventId, data…`: 1 = battery (as 0x0106), 2 = ear status (as 0x0109), 6 = hosts (as 0x0112), 0xF2 = pairing history. **[observed]** both test devices list event 6 |
| 0x0500 | **device asks UTC time** | – | host replies `0x8500` same seq: `00, epochSeconds:u32le` **[observed request]** |
| 0x0503 | **feature switch sync** | – | `n, (featureId, on)×n` |
| 0x0507 | **multi-connect changed** | – | re-read 0x0112 |

### Hosts (0x0112 / event 6)
The list holds **every host the device has paired with**, not just connected ones.
* `state`: Android connection state. 0 disconnected, 1 connecting, **2 connected**, 3 disconnecting.
* `flags`: bit0 = the host asking (this Mac), bit1 = main audio device, bit2 = audio active,
  bits3-5 = device type.
* MAC byte order **varies by model** **[observed]**: Nord Buds 3r sends it reversed, realme Buds
  Wireless 3 sends it as-is. Match the bit0 entry against the host's own address to pick the order.
* Names may be truncated by the device (e.g. 20 bytes on realme Buds Wireless 3).

### Feature IDs (0x010D / 0x0403)
4 wear detection · 6 game mode · 9 vocal enhance · 15 zen mode · **17 dual connection (multipoint)** ·
20 voice assistant · 22 safe remind · 23 long power mode · 24 hi-quality audio · 27 spatial sound ·
28 auto volume · 29 bass engine · 48 adaptive volume · 55 swift pair.
**[observed]** The Nord Buds 3r reports feature 17 = 1 (dual connection on). The earbuds echo
every requested ID, supported or not, so gate multipoint on capability command 0x0112 instead.
That isn't conclusive either: realme Buds Wireless 3 also reports 0x0112, accepts feature 17 and
reads it back. Whether a model really does multipoint isn't reported by the device.

### Key functions (gestures)
* `type`: 1 left, 2 right.
* `action`: 1 single tap, 2 double tap, 3 triple tap, 4 touch & hold, 5 slide, 6 long touch & hold,
  7 slide up, 8 slide down, 16/17/18 single/double/triple squeeze, 20 squeeze & hold.
* `button`: model-specific. **[observed]** Nord Buds 3r uses button 1 for the normal gesture set
  and button 6 for the in-call set (holds answer/reject functions).
* `function` codes: 0 none · 1 play/pause · 3 voice assistant · 5 previous · 6 next ·
  7 volume control · 8 ANC toggle · 9 play favourites · 10 switch track · 11 volume up ·
  12 volume down · 13 switch devices · 17 game mode · 18 zen mode · 22 add to favourites ·
  25 AI summary · 26 translation · 27 real-time translation · 28 reject call · 29 answer/hang up.
  **Exception:** on "OnePlus Buds" and "OnePlus Buds Z", previous = 4 and next = 5.
* The earbuds don't report which functions each slot accepts. The Mac app offers context-appropriate
  defaults, shows an error when the earbuds reject a value, and re-reads the slot after every set.

## Unknowns
* The allowed functions per slot, and human labels for `button`, on each model.
* The meaning of the `kind` field in version triples, and of the 0x0500 request payload bytes.
