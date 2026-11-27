# Pokit Meter / Pokit Pro BLE protocol reference

A byte-level reference for the Pokit Bluetooth protocol, compiled from the sources below.
`PokitKit` implements the Status, Multimeter, oscilloscope (DSO) and data logger parts.
Nothing in this file was verified against a device by this project: where the sources
disagree or are silent, it says so.

Citation key:

- `dokit:path:line` = [dokit](https://github.com/pcolby/dokit) by Paul Colby (C++/Qt, v0.6.x,
  commit `a497b11`); paths are relative to that repository.
- `PDF p.N` = Pokit's "Bluetooth API Definition", document D0005250 rev 0.02 (2 Jan 2019,
  status Draft, "API version 1.0" per p.5). It documents the Pokit Meter only.
- `JS:line` = the earlier Bangle.js client, `apps/pokitmeter/app.js` on branch
  `app/pokitcontroller` of [DionHo/BangleApps](https://github.com/DionHo/BangleApps).
- `TEST:line` = `dokit:test/unit/lib/*.cpp` (byte vectors captured from real devices, quoted
  where they confirm layouts).

Conventions: all multi-byte integers are **little-endian**; "float" = IEEE-754 binary32, little-endian (`dokit:src/lib/multimeterservice.cpp:311`, `...:288`). Offsets are 0-based byte offsets inside the characteristic value.
Where a fact is an inference rather than a source statement, it is marked **[inference]**.

---

## 1. Discovery and product detection

| Topic | Finding | Source |
|---|---|---|
| Scan type | BLE only (LowEnergyMethod). | `dokit:src/lib/pokitdiscoveryagent.cpp:85-93` |
| Detection rule | A device is a Pokit if its advertised service UUID list contains the Pokit Status service UUID (Meter or Pro variant). Nothing else (name, manufacturer data, MAC) is used. | `dokit:src/lib/pokitproducts.cpp:75-79`, `...:51-54`, `pokitdiscoveryagent.cpp:170-177` |
| Meter vs Pro | Status service UUID `57d3a771-267c-4394-8872-78223e92aec4` => **Pokit Meter**. `57d3a771-267c-4394-8872-78223e92aec5` => **Pokit Pro**. Checked Meter first, then Pro. If neither, dokit falls back to "Meter" with a warning. | `dokit:src/lib/pokitproducts.cpp:103-114`, `dokit:include/qtpokit/statusservice.h:30,33` |
| Same detection post-connect | `controller.services()` is checked the same way after service discovery; StatusService picks its UUID from whichever of the two is discovered. | `dokit:src/lib/pokitproducts.cpp:90-93,124-127`, `dokit:src/lib/statusservice.cpp:715-725` |
| JS client | Filters the scan on the Status UUID (Meter or Pro chosen by the user; two hard-coded constants). So advertised-UUID filtering is confirmed to work on a second platform. | `JS:1-2,164` |
| Product enum | `PokitMeter = 0`, `PokitPro = 1` (dokit-internal, NOT a wire value). A `PokitClamp = 3` is commented out. | `dokit:include/qtpokit/pokitproducts.h:21-25` |
| Device names | No name-based detection. The name is user-settable (<= 11 bytes). Example names in dokit README: `PokitMeter` (device name); README says to rename with `set-name --device Pokit --new-name PokitMeter`, implying the factory name begins with `Pokit` (a substring/prefix; the exact factory name is **not found in sources**). | `dokit:README.md:62,88,113-116` |
| dokit device selection | By exact name, MAC (`QBluetoothAddress`), or macOS CBPeripheral UUID. | `dokit:src/cli/devicecommand.cpp:349-351` |
| Pairing / bonding / encryption | **Not found in sources.** dokit never calls any pairing/bonding API and just does `createCentral(deviceInfo)` + `connectToDevice()`; a grep of dokit `src`/`include` for pair/bond/encrypt/secur finds nothing relevant. The PDF does not mention security. The JS client simply `gatt.connect()`s. Empirically, unbonded connection works for the three clients, but no source states "no bonding required" explicitly. | `dokit:src/cli/devicecommand.cpp:357-379`, `JS:164-168` |
| Connect/discover order (dokit) | scan -> match -> create controller -> `setPokitProduct()` **before** `connectToDevice()` -> on `connected` call `discoverServices()` -> on matching `serviceDiscovered` create service object -> `discoverDetails()` -> when state == RemoteServiceDiscovered, emit "details discovered" (characteristics are valid and cached from then on). | `dokit:src/cli/devicecommand.cpp:357-379`, `dokit:src/lib/abstractpokitservice.cpp:197-254,443-456,501-507,517-555`, `dokit:src/lib/abstractpokitservice.cpp:99-109` (doc comment) |

Note: PDF p.5 says "Pokit consists of 6 GATT services in total" (MM, DSO, Data Logger, Pokit Status, Device Info, Generic Access); it lists no Calibration service, no OTA service, and only the Meter Status UUID.

---

## 2. Services and characteristics (UUIDs and properties)

"Props" = as stated by the source. dokit comment text is quoted where it is the only source.

### 2.1 Pokit Status service
Service UUID: Meter `57d3a771-267c-4394-8872-78223e92aec4`, Pro `57d3a771-267c-4394-8872-78223e92aec5` (`dokit:include/qtpokit/statusservice.h:30,33`; erratum `dokit:src/lib/statusservice.cpp:27-29`; PDF p.15 gives only `...aec4`).

| Characteristic | UUID | Props (source) | Notes |
|---|---|---|---|
| Device Characteristics | `6974f5e5-0e54-45c3-97dd-29e4b5fb0849` | Read (PDF p.15; `statusservice.h:151`) | 20 bytes |
| Status | `3dba36e1-6120-4706-8dfd-ed9c16e569b6` | Meter: Read. Pro: Read + Notify (`statusservice.h:154`). PDF p.15: Read | 5 (Meter) to 8 (Pro) bytes |
| Device Name | `7f0375de-077e-4555-8f78-800494509cc3` | Read/Write (`statusservice.h:159`; PDF p.16) | UTF-8, <= 11 bytes |
| Flash LED | `ec9bb1f3-05a9-4277-8dd0-60a7896f0d6e` | Meter: Write only. Pro "claims read/write, but fails" (`statusservice.h:163`); Pro gives ATT error `0x80` on write (`statusservice.cpp:363-365`). PDF p.16: Write | 1 byte |
| Torch (undocumented) | `aaf3f6d5-43d4-4a83-9510-dff3d858d4cc` | Pro only: Read/Write/Notify (`statusservice.h:166`; `statusservice.cpp:410`) | 1 byte |
| Button Press (undocumented) | `8fe5b5a9-b5b4-4a7b-8ff2-87224b970f89` | Pro only: Read/Write/Notify (`statusservice.h:172`) | 2 bytes |
| unknown (Pro) | `a59f052e-c2a1-46b6-8025-64e485c00162` | read/write (`statusservice.h:60`) | purpose unknown |
| unknown (Pro) | `f89e4130-4347-45ef-b092-4f29e6f3a608` | write only (`statusservice.h:61`) | purpose unknown |

dokit only reads the Torch and Button Press characteristics if they exist on the device (`statusservice.cpp:151-154`), so absence on Meter is handled by checking for the characteristic.

### 2.2 Multimeter (MM) service
Service UUID `e7481d2f-5781-442e-bb9a-fd4e3441dadc` (`dokit:include/qtpokit/multimeterservice.h:28`; PDF p.5; JS:3). Same for Meter and Pro.

| Characteristic | UUID | Props | Size |
|---|---|---|---|
| Settings | `53dc9a7a-bc19-4280-b76b-002d0e23b078` | Write (`multimeterservice.h:33,91`; PDF p.5) | 6 bytes |
| Reading | `047d3559-8bee-423a-b229-4417fa603b90` | Read + Notify (`multimeterservice.h:36,94`; PDF p.7) | 7 bytes |

### 2.3 DSO service
Service UUID `1569801e-1425-4a7a-b617-a4f4ed719de6` (`dokit:include/qtpokit/dsoservice.h:29`; PDF p.8).

| Characteristic | UUID | Props | Size |
|---|---|---|---|
| Settings | `a81af1b6-b8b3-4244-8859-3da368d2be39` | Write (PDF p.8; `dsoservice.cpp:412-416`) | 13 bytes |
| Metadata | `970f00ba-f46f-4825-96a8-153a5cd0cda9` | Read + Notify (PDF p.10) | 17 bytes |
| Reading | `98e14f8e-536e-4f24-b4f4-1debfed0a99e` | Notify only (PDF p.11; `dsoservice.cpp:424-428`) | up to 20 bytes per notification |
(`dsoservice.h:34,37,40`)

### 2.4 Data Logger service
Service UUID `a5ff3566-1fd8-4e10-8362-590a578a4121` (`dokit:include/qtpokit/dataloggerservice.h:28`; PDF p.11).

| Characteristic | UUID | Props | Size |
|---|---|---|---|
| Settings | `5f97c62b-a83b-46c6-b9cd-cac59e130a78` | Write (PDF p.12) | 11 bytes (Meter, PDF); 13 bytes (Pro, dokit) |
| Metadata | `9acada2e-3936-430b-a8f7-da407d97ca6e` | Read + Notify (PDF p.13) | 15 bytes (Meter); 23 bytes (Pro) |
| Reading | `3c669dab-fc86-411c-9498-4f9415049cc0` | Notify only (PDF p.14; `dokit:src/lib/dataloggerservice.cpp:463-467`) | up to 20 bytes per notification (Pro: dokit saw 176-byte values, see 3.14) |
(`dataloggerservice.h:33,36,39`)

### 2.5 Calibration service (undocumented in PDF)
Service UUID `6f53be2f-780b-49b8-a7c3-e8a052b3ae2c` (`dokit:include/qtpokit/calibrationservice.h:28`). Characteristics (`...h:34,37,40`):
- Temperature `0cd0f713-f5aa-4572-9e23-f8049f6bcaaa`: write-only; value = ambient temperature as float32 LE (4 bytes) (`dokit:src/lib/calibrationservice.cpp:64-84,111-117`; "BLE write only" `calibrationservice.h:47`, `calibrationservice.cpp:48,53`). Unit is not stated in the library (CLI takes a plain float: `calibratecommand.cpp:56-62`); presumably degrees Celsius **[inference]**.
- Get Param `b6728f91-409c-4d6c-864e-272a6a7a0204` (undocumented, `\todo`, not implemented).
- Set Param `5588e47b-cb81-4f7b-acc4-6029a3f39f72` (undocumented, not implemented).
The whole service is "write-only" per dokit (`calibrationservice.cpp` readCharacteristics comment).

### 2.6 Device Information service (standard, 0x180A)
Service `0x180A` (`dokit:include/qtpokit/deviceinfoservice.h:22-24`; PDF p.16). All read-only UTF-8 strings.

| Char | UUID | PDF size / value |
|---|---|---|
| Manufacturer Name | 0x2A29 | 16 bytes, "Ingenuity Design" (PDF p.17) |
| Model Number | 0x2A24 | 5 bytes "XX.XX" (p.17) |
| Firmware Revision | 0x2A26 | 5 bytes "XX.XX" (p.17) |
| Software Revision | 0x2A28 | 5 bytes; PDF says this holds the **API version** string (p.17-18) |
| Hardware Revision | 0x2A27 | 5 bytes "XX.XX" (p.18) |
| Serial Number | 0x2A25 | not in PDF. dokit reads it if present (`deviceinfoservice.cpp:52`). Pokit (Pro) devices append a trailing NUL byte; dokit strips it (`deviceinfoservice.cpp:237-243`). |
(`deviceinfoservice.h:27-47`)

### 2.7 Generic Access (0x1800) and Generic Attribute (0x1801)
- Generic Access 0x1800 (PDF p.18): Device Name 0x2A00 Read/Write, up to 11 bytes, 1-11 alphanumeric chars; Appearance 0x2A01 Read, uint16, value 0 ("Unknown Appearance"). dokit lists 0x1800/0x1801 only for debug strings (`dokit:src/lib/pokitdevice.cpp:207-210`).
- Whether 0x2A00 and the Status-service Device Name characteristic are the same storage: **not found in sources**.

### 2.8 OTA / other (undocumented)
- OTA firmware update service `1d14d6ee-fd63-4fa1-bfa4-8f47b42119f0`, with OTA Control `f7bf3564-fb6d-4e53-88a4-5e37e0326063` and OTA Data Transfer `984227f3-34fc-4045-a5d0-2c581f81a153` (names only; `dokit:src/lib/pokitdevice.cpp:211,261-262`). dokit notes: "appears to be a Silicon Labs (formerly BlueGiga) OTA Service" on both Meter and Pro (`dokit:doc/src/internal/notes.md:8-12`). Not to be used by an app.
- Meter-only unknown service `831d0001-e98e-1fed-e73e-4bb7596f776e` (`notes.md:14-17`).
- Pro-only unknown services (added between firmware v1.8.1 and v2.0.2): `3852ae6e-a1e6-4132-87f7-8929f6117338`, `ae97e4b0-9c1c-4507-bf7b-eff703c6a85c` (`notes.md:19-22`).
- Other UUIDs referenced in the Pokit Android app (may or may not be services): `581a9e6a-d2f6-4d7b-b0d0-5bc3ed9b842e`, `5f330a08-8e76-4d5a-97fb-22e1807b1888`, `6e7a7953-3b41-4be5-8052-c93129fa1f35`, `b4a19bce-96cf-4915-9ba4-a19f4a042c8e`, `c999d155-c00a-4e8f-a056-cd9523ce39de`, `ef1b0821-b107-4cae-b17c-df1e99b1667a`, `f2259466-ac2a-40a9-bf23-f47666ae2b15` (`notes.md:24-30`).

### 2.9 Enabling notifications (CCCD)
dokit writes the Client Characteristic Configuration descriptor (0x2902) with `01 00` to enable and `00 00` to disable (`dokit:src/lib/abstractpokitservice.cpp:341-355,376-390`). If a characteristic has no CCCD, dokit fails (`...:344-347`).

---

## 3. Byte layouts

### 3.1 Multimeter Settings (write, 6 bytes)

| Off | Size | Type | Field | Meaning |
|---|---|---|---|---|
| 0 | 1 | uint8 | Mode | enum in 4.1 |
| 1 | 1 | uint8 | Range | per-product range index (4.2), `0xFF` = auto-range; ignored/N-A for Idle, Diode, Continuity, Temperature (PDF p.6) |
| 2 | 4 | uint32 LE | Update interval | **milliseconds** (PDF p.6 "in milliseconds"; `multimeterservice.h:64` "in milliseconds") |

Source: `dokit:src/lib/multimeterservice.cpp:279-293` (asserts 6 bytes), PDF p.5-6. Real vectors (`TEST:testmultimeterservice.cpp:196-217`):
- AC voltage, Meter range idx 2 (6 V), 1000 ms -> `02 02 E8 03 00 00`
- Diode, range 0xFF, 5000 ms -> `06 FF 88 13 00 00`
- Resistance, range 0xFF, 60000 ms -> `05 FF 60 EA 00 00`
- JS example: DataView `setUint8(0,mode); setUint8(1,255); setUint32(2,100,true)` -> 100 ms (`JS:155-157`).
PDF p.5: "In case of receiving invalid values on any attribute, a NAK will be replied and Pokit will be set to IDLE mode." The precise ATT-level form of ACK/NAK is **not found in sources**.

### 3.2 Multimeter Reading (read/notify, 7 bytes)

| Off | Size | Type | Field | Meaning |
|---|---|---|---|---|
| 0 | 1 | uint8 | Status | **an enum, not a bitfield**; meaning depends on Mode (4.3) |
| 1 | 4 | float LE | Value | last acquired value, in base SI units: V, A, Ω, °C, F (units from the CLI: `dokit:src/cli/metercommand.cpp:239-252`; PDF gives no units) |
| 5 | 1 | uint8 | Mode | enum in 4.1 (the *current* mode; JS reads it from here, `JS:117`) |
| 6 | 1 | uint8 | Range | current range index; PDF p.7 lists `255` as possible |

Source: `dokit:src/lib/multimeterservice.cpp:298-315` (min 7 bytes required, longer tolerated: `checkSize(..., 7, 7)` with `failOnMax=false`, `abstractpokitservice_p.h:50-51`; test with 10 bytes parsed OK, `TEST:testmultimeterservice.cpp:262-268`); PDF p.7-8.
Real vectors:
- Meter, idle-ish: `00 00 00 00 00 01 03` = status 0 (auto-range off), value 0.0, mode 1 (DC V), range 3 (12 V) (`TEST:...:247`).
- Pro: `00 94 89 fa 3b 02 00` = status 0, value 0.007645795 V, mode 2 (AC V), range 0 (250 mV on Pro; the test mislabels it `PokitMeter::VoltageRange::_300mV` which has the same numeric value) (`TEST:...:255-258`).
Reading starts after settings are written (see 5). On parse failure dokit returns status Error/value NaN (`multimeterservice.cpp:300-308`).

### 3.3 Status service: Device Characteristics (read, 20 bytes)

| Off | Size | Type | Field |
|---|---|---|---|
| 0 | 1 | uint8 | Firmware major |
| 1 | 1 | uint8 | Firmware minor |
| 2 | 2 | uint16 | Max input voltage (V) |
| 4 | 2 | uint16 | Max input current (A) |
| 6 | 2 | uint16 | Max input resistance (kOhm per PDF "1000 (KΩ)") |
| 8 | 2 | uint16 | Max sampling rate (kHz per PDF "1000 (KHz)") |
| 10 | 2 | uint16 | Sampling buffer size (samples) |
| 12 | 2 | uint16 | Capability mask (reserved; 0 on both devices in tests) |
| 14 | 6 | uint8[6] | MAC address, bytes in display (MSB-first) order |

Source: `dokit:src/lib/statusservice.cpp:580-615` (exactly 20 bytes; `checkSize(...,20,20)`), MAC handling `...:601-602` (big-endian of `00 00 + 6 bytes`, i.e. bytes are already MSB-first), PDF p.15. Real vectors (`TEST:teststatusservice.cpp:351-365`):
- Meter: `01 04 3c 00 02 00 e8 03 e8 03 00 20 00 00 84 2e 14 2c 03 a8` = fw 1.4, 60 V, 2 A, 1000, 1000, 8192, 0, MAC 84:2E:14:2C:03:A8.
- Pro: `01 03 52 03 0a 00 b8 0b e8 03 00 40 00 00 5c 02 72 09 aa 25` = fw 1.3, 850 V, 10 A, 3000, 1000, 16384, 0, MAC 5C:02:72:09:AA:25.
Units are from PDF p.15 (V, A, KΩ, KHz) only for the Meter; the Pro's 850 for "voltage" (spec says 600 V CAT; Pro range table tops at 600 V) shows these numbers are device-defined, do not hard-code. 

### 3.4 Status service: Status (Meter read; Pro read/notify)

Known lengths: **5, 6, 8** (7 is accepted by the parser but never seen in sources). `checkSize(...,5,8)`: <5 bytes = failure, >8 bytes = warn and extra bytes ignored (`dokit:src/lib/statusservice.cpp:633-641`; `TEST:teststatusservice.cpp:538-542`).

| Off | Size | Type | Field | Present in lengths |
|---|---|---|---|---|
| 0 | 1 | uint8 | Device status (enum 4.4) | 5, 6, 7, 8 |
| 1 | 4 | float LE | Battery voltage (volts) | 5+ |
| 5 | 1 | uint8 | Battery status (enum 4.5) | 6+ |
| 6 | 1 | uint8 | Switch position (enum 4.6) -- Pro physical mode switch, undocumented | 7+ |
| 7 | 1 | uint8 | Charging status (enum 4.7) -- undocumented | 8 |

Length history (`dokit:src/lib/statusservice.cpp:633-639`): API 0.02 (the PDF) says 5 bytes; API 1.00 added Battery Status (6 bytes) [per dokit comment; the 1.00 doc is not in the sources]; Pokit Pro actually returns 8 bytes, where byte 6 = physical switch position and byte 7 = charging status ("It appears that..." i.e. reverse-engineered).
- **Pokit Meter** returns 5 bytes: no battery status (dokit sets it to 255 = "not set") (`statusservice.cpp:621,626-631`; `TEST:teststatusservice.cpp:420-428`). Real vector: `00 25 07 33 40` = idle, 2.797 V.
- **Pokit Pro** returns 8 bytes. Real vectors: `02 64 3b 83 40 01 00 00` = AC voltage, 4.101 V, battery Good, switch Voltage, Discharging (`TEST:...:431-438`).
- Charging samples: `00 e5 d0 82 40 01 01 01` (4.088 V, switch=MultiMode, charging byte=1), `... 01 01 02` ("charged"), `... 01 01 00` ("discharging") (`TEST:...:472-526`). NOTE: the test's expected struct says `Discharging` for rows named "charging"/"charged", but the test does not compare `chargingStatus` (`TEST:...:545-557`), so those expectations are unchecked; the byte values (1 = charging, 2 = charged, 0 = discharging) match the enum in `statusservice.h:110-114`. Treat charging status as mildly verified.
- Battery voltage range seen: Meter 2.76-2.80 V, Pro 4.09-4.20 V (README: 2.76221 V; tests). PDF says "0.0 - 3.3 (V)" for the Meter (p.16), which does not hold for the Pro (Li-ion).
- The Battery Status threshold (what voltage makes `Low`) is **not found in sources**.

### 3.5 Status service: Device Name (read/write)
Raw UTF-8 bytes, no terminator, no length prefix; max **11 bytes** (dokit rejects `> 11` bytes on write: `statusservice.cpp:345-350`; PDF p.16: "1 to 11 alphanumeric characters"). Read decodes UTF-8 (`...:321-327`). Written via a normal GATT write (`...:352`). Whether a name change needs a reconnect/re-advertisement to show up: **not found in sources**.

### 3.6 Status service: Flash LED (write, 1 byte)
Single uint8, value **1** (`01`). Flashes the LED (twice per PDF p.16). "Any value other than 1 will be ignored" (PDF p.16; `statusservice.cpp:380-384`). Meter only; on Pro the write errors with ATT error `0x80` (`statusservice.cpp:363-365`).

### 3.7 Status service: Torch (Pro; read/write/notify, 1 byte)
`00` = off, `01` = on (`statusservice.h:127-130`; `statusservice.cpp:675-684,412-423`; `TEST:teststatusservice.cpp:568-569`).

### 3.8 Status service: Button Press (Pro; read/write/notify, 2 bytes)
- Byte 0: unknown; "in all examples ... always `0x02`"; if you write to the characteristic, whatever you set as byte 0 persists and byte 1 reverts to the live button state (`statusservice.cpp:695-702`; `TEST:teststatusservice.cpp:585-589`).
- Byte 1: button event: `00` Released, `01` Pressed, `02` Held ("typically 1,500 ms") (`statusservice.h:134-138`; the Android app only looks at `bytes[1]`).
Exactly 2 bytes required (`statusservice.cpp:689-693,770-778`). Source: undocumented in PDF.

### 3.9 DSO Settings (write, 13 bytes)

| Off | Size | Type | Field | Notes |
|---|---|---|---|---|
| 0 | 1 | uint8 | Command | 0 FreeRunning, 1 RisingEdgeTrigger, 2 FallingEdgeTrigger, 3 ResendData |
| 1 | 4 | float | Trigger level | Volts or Amps by mode; only used for edge triggers; negative and 0 are valid (CHANGELOG fixed negative/zero triggers: `dokit:CHANGELOG.md:36-37`) |
| 5 | 1 | uint8 | Mode | 0 Idle, 1 DC V, 2 AC V, 3 DC A, 4 AC A (note: this DSO list has only 0-4) |
| 6 | 1 | uint8 | Range | per-product index; **auto-range (255) is NOT allowed in DSO** (`dsoservice.cpp:158,166`; `pokitpro.h:39,72`) |
| 7 | 4 | uint32 | Sampling window | **microseconds** |
| 11 | 2 | uint16 | Number of samples | PDF: 1 to 8192. dokit: Meter fails above **8191**; Pro supports up to **16384** (`dokit:src/cli/dsocommand.cpp:238-253`) |

Source: `dsoservice.cpp:341-359` (asserts 13), `dsoservice.h:44-75`, PDF p.8-9. ResendData (3): "all other attributes will be ignored" (PDF p.9; `dsoservice.cpp:211-217`).
Sample rate = numberOfSamples * 1e6 / window_us (`dsocommand.cpp:369`); both devices sample up to 1 MHz (`dsocommand.cpp:258`).

### 3.10 DSO Metadata (read/notify, 17 bytes)

| Off | Size | Type | Field |
|---|---|---|---|
| 0 | 1 | uint8 | Status: 0 Done, 1 Sampling, 255 Error |
| 1 | 4 | float | Scale (multiply each raw sample by this) |
| 5 | 1 | uint8 | Mode (as 3.9) |
| 6 | 1 | uint8 | Range used |
| 7 | 4 | uint32 | Sampling window used (us) |
| 11 | 2 | uint16 | Number of samples acquired |
| 13 | 4 | uint32 | Sampling rate (Hz) |

Source: `dsoservice.cpp:364-383` (exactly 17), `dsoservice.h:78-93`, PDF p.10.

### 3.11 DSO Reading (notify only)
Concatenated int16 LE samples, each in -2048..2047; real value = `sample * metadata.scale` (`dsoservice.cpp:388-401`; `dsocommand.cpp:442`). PDF: packets of up to 10 samples (20 bytes), sent sequentially with no sequence validation; verify total against Metadata.numberOfSamples (PDF p.11). dokit imposes no 10-sample cap (`dsoservice.cpp:109-112`). Odd-length values are rejected.

### 3.12 Data Logger Settings (write)
Two variants. dokit picks the variant by looking at the **cached Metadata characteristic length**: `>= 23` => Pro layout (13 bytes), otherwise Meter layout (11 bytes) (`dokit:src/lib/dataloggerservice.cpp:166-167,370-379`).

| Off | Size | Field | Meter (11 B) | Pro (13 B) |
|---|---|---|---|---|
| 0 | 1 uint8 | Command | 0 Start, 1 Stop, 2 Refresh | same |
| 1 | 2 uint16 | Arguments | reserved (0) | same |
| 3 | 1 uint8 | Mode | 0 Idle, 1 DC V, 2 AC V, 3 DC A, 4 AC A, 5 Temperature (Temperature not in PDF) | same |
| 4 | 1 uint8 | Range | index | same |
| 5 | Meter: 2 uint16 = **seconds**; Pro: 4 uint32 = **milliseconds** | Update interval | | |
| Meter 7 / Pro 9 | 4 uint32 | Timestamp | opaque; echoed back in Metadata | same |

dokit sends Meter interval as `(ms + 500) / 1000` rounded seconds (`dataloggerservice.cpp:372`). The Pro 32-bit ms interval is "not officially documented anywhere" (`...:365-369`). Source: `dataloggerservice.cpp:349-379`, `dataloggerservice.h:43-73`, PDF p.12-13 (PDF has 11 bytes, uint16 seconds; summary p.20 says Update Interval 1-3600 s, small print).
Stop = command 1, others ignored; Refresh = command 2, others ignored (`dataloggerservice.cpp:200-221` (stopLogger/fetchSamples), PDF p.12). Default Timestamp the CLI sends is current Unix seconds (`dokit:src/cli/loggerstartcommand.cpp:118`).

### 3.13 Data Logger Metadata (read/notify; 15 bytes Meter / 23 bytes Pro)

| Off | Size | Field |
|---|---|---|
| 0 | 1 uint8 | Status: 0 Done, 1 Sampling, 2 BufferFull, 255 Error |
| 1 | 4 float | Scale |
| 5 | 1 uint8 | Mode |
| 6 | 1 uint8 | Range |
| Meter: 7 (2 uint16 = seconds), 9 (2 uint16 samples), 11 (4 uint32 timestamp) | | |
| Pro: 7 (4 uint32 = milliseconds), 11 (2 uint16 samples), 13..18 (6 bytes **unknown**), 19 (4 uint32 timestamp) | | |

Source: `dataloggerservice.cpp:384-422` (min 15/max 23; sizes other than 15/23 log a warning and leave interval/count/timestamp zero). PDF p.13-14 documents the 15-byte layout but calls the interval "microseconds" (wrong; dokit says whole seconds for Meter and ms for Pro, `dataloggerservice.cpp:402-407`). Sample count 1..6192 (`dataloggerservice.h:90`, PDF p.14).

### 3.14 Data Logger Reading (notify only)
int16 LE samples, real value = `sample * metadata.scale`; PDF says up to 10 samples (20 bytes) per notification; dokit notes the Pro "seems to send 88 samples (in 176 bytes) at a time" (`dataloggerservice.cpp:96-107`), so do not assume 20 bytes (and MTU must allow it). Logger fetch order: enable Metadata + Reading notifications, then write Refresh (`dokit:src/cli/loggerfetchcommand.cpp:66-76`); timestamps for sample i are `metadata.timestamp*1000 + i*updateInterval(ms)` (`loggerfetchcommand.cpp:93,143`).

---

## 4. Enums and tables (numeric values)

### 4.1 Multimeter mode (Settings byte 0 and Reading byte 5)
`dokit:include/qtpokit/multimeterservice.h:40-52` (PDF p.5-7 has 0-8 only):

| Value | Mode | In PDF? |
|---|---|---|
| 0 | Idle | yes |
| 1 | DC voltage | yes |
| 2 | AC voltage | yes |
| 3 | DC current | yes |
| 4 | AC current | yes |
| 5 | Resistance | yes |
| 6 | Diode | yes |
| 7 | Continuity | yes |
| 8 | Temperature | yes |
| 9 | Capacitance | no (reverse-engineered; Pro only, `pokitproducts.cpp:135`) |
| 10 | External temperature (external probe) | no (reverse-engineered; which product supports it: not found in sources) |

### 4.2 Range index tables
In every case the index selects the **upper limit** of the range ("Up to X"); the lower limit is the previous index's value (PDF p.6 prints them as bands like "300mV to 2V"). `255` = auto-range for all. Units of the max value: voltage mV, current uA, resistance ohm, capacitance nF (`dokit:src/lib/pokitproducts.cpp:153,196,237,278`). The same tables are used for DSO and Data Logger (DSO/Logger have no resistance/capacitance modes) (`dsoservice.cpp:55-68`).

**Pokit Meter** (`dokit:include/qtpokit/pokitmeter.h:20-57`; values `pokitmeter.cpp:44-57,79-95,115-129`)

| idx | Voltage (max mV) | Current (max uA) | Resistance (max ohm) |
|---|---|---|---|
| 0 | 300 mV (300) | 10 mA (10,000) | 160 (160) |
| 1 | 2 V (2,000) | 30 mA (30,000) | 330 (330) |
| 2 | 6 V (6,000) | 150 mA (150,000) | 890 (890) |
| 3 | 12 V (12,000) | 300 mA (300,000) | 1.5 k (1,500) |
| 4 | 30 V (30,000) | **2 A** (2,000,000) | 10 k (10,000) |
| 5 | 60 V (60,000; "60V DC (42V AC)", `pokitmeter.h:53`) | - | 100 k (100,000) |
| 6 | - | - | 470 k (470,000) |
| 7 | - | - | 1 M (1,000,000) |
| 255 | Auto | Auto | Auto |

(The PDF's Meter current table gives idx 4 as "300mA to 3A": see section 6.) No capacitance on the Meter (`pokitproducts.cpp:135,143`).

**Pokit Pro** (`dokit:include/qtpokit/pokitpro.h:20-73`; values `pokitpro.cpp:51-62,92-107,141-160,191-207`; all reverse-engineered, "undocumented by Pokit Innovations")

| idx | Voltage (max mV) | Current (max uA) | Resistance (max ohm) | Capacitance (max nF) |
|---|---|---|---|---|
| 0 | 250 mV (250) | 500 uA (500) | 30 (30) | 100 nF (100) |
| 1 | 2 V (2,000) | 2 mA (2,000) | 75 (75) | 10 uF (10,000) |
| 2 | 10 V (10,000) | 10 mA (10,000) | 400 (400) | 1 mF (1,000,000) |
| 3 | 30 V (30,000) | 125 mA (125,000) | 5 k (5,000) | - |
| 4 | 60 V (60,000) | 300 mA (300,000) | 10 k (10,000) | - |
| 5 | 125 V (125,000) | 3 A (3,000,000) | 15 k (15,000) | - |
| 6 | 400 V (400,000) | 10 A (10,000,000) | 40 k (40,000) | - |
| 7 | 600 V (600,000) | - | 500 k (500,000) | - |
| 8 | - | - | 700 k (700,000) | - |
| 9 | - | - | 1 M (1,000,000) | - |
| 10 | - | - | 3 M (3,000,000) | - |
| 255 | Auto | Auto | Auto | Auto |

(A comment in `pokitpro.h:32` says "Up to 5μA" for index 0 of current: a typo, the code and strings say 500 uA: `pokitpro.cpp:77,95`.) Max value for the auto value reports the table maximum (`pokitpro.cpp:102,155,202,57`).

Range selection helper semantics in the CLI (not protocol): pick the lowest index whose max >= requested; unspecified/0 or too-large => 255 (`dokit:src/cli/devicecommand.cpp:60-90`). Modes with no range (Diode, Continuity, Temperature, ExternalTemperature) get range `0` from the CLI (`metercommand.cpp:171`); PDF says "N/A" for them.

### 4.3 Multimeter Reading `status` byte (byte 0) per mode
It is an enum value, not a bit mask; no bits for polarity or overload are defined anywhere in the sources. `dokit:include/qtpokit/multimeterservice.h:68-75`; CLI interpretation `dokit:src/cli/metercommand.cpp:213-237`; PDF p.7.

| Reading mode | Status 0 | Status 1 | Status 255 |
|---|---|---|---|
| DC V, AC V, DC A, AC A, Resistance (and Capacitance, per CLI) | Auto-range OFF | Auto-range ON | Error |
| Continuity (7) | No continuity | Continuity | Error |
| Temperature (8), External temp (10), Diode (6) | OK | (undefined) | Error |
| Idle (0) | (no meaning defined) | - | Error |

Any other value: **not found in sources**. dokit checks `255` first for any mode (`metercommand.cpp:214`). Polarity: not a separate flag; negative readings are just negative floats **[inference]**. Overload / out-of-range: **no explicit flag found**. The only hint: the CLI special-cases a reading `value` of +/-Infinity when emitting JSON (`metercommand.cpp:269-270`), which suggests the device reports overload as an infinite float **[inference, unverified]**; status 255 = Error is the other candidate.

### 4.4 Device status (Status byte 0)
`dokit:include/qtpokit/statusservice.h:79-91` (PDF p.15-16 agrees, 0-10):
0 Idle, 1 MM DC V, 2 MM AC V, 3 MM DC A, 4 MM AC A, 5 MM Resistance, 6 MM Diode, 7 MM Continuity, 8 MM Temperature, 9 DSO sampling, 10 Data Logger sampling. (Capacitance/external temp status values: **not found in sources**; the enum has no entry. Parser casts the raw byte unchecked.)

### 4.5 Battery status (Status byte 5; absent on Meter)
`0` Low (replace battery), `1` Good (`statusservice.h:95-98`). dokit's "not present" sentinel is 255 (local only).

### 4.6 Switch position (Status byte 6; Pro; undocumented)
`0` Voltage ("V"), `1` MultiMode (Resistance / Low Current / Capacitance / Diode), `2` HighCurrent ("A") (`statusservice.h:102-106`). Android app names: `SWITCH_MODE_VOLTAGE`, `SWITCH_MODE_ALL`, `SWITCH_MODE_CURRENT` (`statusservice.cpp:69-70`). "Easily testable with a physical Pokit Pro".

### 4.7 Charging status (Status byte 7; Pro; undocumented)
`0` Discharging, `1` Charging, `2` Charged (`statusservice.h:110-114`; vectors in 3.4).

### 4.8 Button press, torch
Button: byte1 `0` Released, `1` Pressed, `2` Held. Torch: `0` Off, `1` On. (3.7, 3.8.)

### 4.9 DSO enums
Command: 0 FreeRunning, 1 RisingEdgeTrigger, 2 FallingEdgeTrigger, 3 ResendData. Mode: 0 Idle, 1 DC V, 2 AC V, 3 DC A, 4 AC A. Status: 0 Done, 1 Sampling, 255 Error. (`dsoservice.h:44-82`)

### 4.10 Data Logger enums
Command: 0 Start, 1 Stop, 2 Refresh. Mode: 0 Idle, 1 DC V, 2 AC V, 3 DC A, 4 AC A, 5 Temperature. Status: 0 Done, 1 Sampling, 2 BufferFull, 255 Error. (`dataloggerservice.h:43-81`; PDF p.12-13 has modes 0-4, statuses 0,1,2,255.)

---

## 5. Operational sequence and quirks

### 5.1 Getting multimeter readings (confirmed order, two independent clients)
1. Scan for the Status service UUID (section 1), connect, discover services and the Multimeter service's characteristics (dokit waits for "service details discovered": `dokit:src/lib/abstractpokitservice.cpp:517-555`).
2. Determine product (Meter vs Pro) from the Status service UUID **before** choosing range indices (range tables differ: `dokit:src/cli/metercommand.cpp:184-196` comment).
3. dokit order: **enable Reading notifications (CCCD write `01 00`), then write Settings** (`dokit:src/cli/metercommand.cpp:176-181`); readings are then delivered as notifications. The CLI only starts *consuming* readings after the Settings write completes (`metercommand.cpp:201-206`); dokit 0.6.0 changelog notes it fixed a "race condition causing some early Bluetooth messages being missed" (`dokit:CHANGELOG.md:29`).
4. JS order: write Settings (mode, range 255, 100 ms) -> get Reading char -> `startNotifications` -> one explicit `readValue()` (`JS:162-193`). Both orders work in practice, so you can use either; for Swift, enabling notifications first then writing Settings avoids missing the first sample.
5. PDF p.5: "To start MM acquisitions, the application needs to set the attributes of the Settings characteristic. After initialised, the MM will notify every new measurement through its Reading characteristic automatically." A plain read of Reading is also allowed at any time (PDF p.7).
6. Settings write is acknowledged: dokit emits `settingsWritten` on the GATT write-response callback (`dokit:src/lib/multimeterservice.cpp:346-355`). dokit uses Qt's default `writeCharacteristic(char, value)` (no explicit write mode); the callback it relies on is only delivered for write-with-response, so **write-with-response is the evidenced mode**. Whether write-without-response is supported by the characteristic: **not found in sources** (the PDF just says "Write", p.5).

### 5.2 Update interval
- Settings bytes 2-5, uint32 ms (3.1). dokit CLI default 1000 ms (`dokit:src/cli/metercommand.h:34`); JS uses 100 ms (`JS:157`); a 60,000 ms value is encoded in tests (`TEST:...:213`).
- Minimum / maximum accepted interval: **not found in sources**. What happens if the interval is shorter than the measurement time: not found. A value of 0 is only used in the "zeroed Idle" test vector.
- The PDF says the device notifies "every new measurement"; dokit's name for the field is "update interval"; notifications arrive at about that period (JS/dokit assume so).

### 5.3 Stopping
- Write Settings with Mode `0` (Idle) (range/interval ignored; JS sends `mode=0, range=255, 100`: `JS:52,84,102,149-158`). PDF p.5: invalid values also force Idle.
- dokit's CLI does not send Idle; it just disconnects (`metercommand.cpp:292-294`). Whether the device returns to idle by itself on disconnect: **not found in sources** (the JS client explicitly sets Idle before leaving, on back/kill: `JS:102,208-212`, and the Bangle app also reconnects on disconnect `JS:213`).
- Optionally disable notifications (`0x0000` to CCCD) (`multimeterservice.cpp:236-240`).
- Device Status (Status service) reports the active mode (4.4), so the Status characteristic can be polled (Meter) or notified (Pro) to confirm it went to Idle.

### 5.4 Pro vs Meter behavioural differences found
- Status UUID differs (Meter ...aec4, Pro ...aec5) (`statusservice.h:30,33`).
- Status characteristic length (5 vs 8 bytes), Meter read-only vs Pro read/notify (3.4, 2.1).
- Flash LED: Meter only; Torch and Button Press: Pro only.
- Range tables entirely different (4.2); Pro adds Capacitance mode (9).
- DSO: Meter max 8191 samples/window (PDF claims 8192); Pro 16384 (`dsocommand.cpp:238-253`). Auto-range not allowed in DSO (either product; dokit comment lists it under Pro, assert is product-independent: `dsoservice.cpp:166`). DSO re-arm: dokit rewrites the Settings (same command) after each full window to capture again unless range == 255 (`dsocommand.cpp:472-477`).
- Data Logger Settings/Metadata layouts differ (3.12, 3.13); Pro sends large (176 B) logger reading notifications (3.14).
- Serial Number string has a trailing NUL on Pro ("Pokit (Pro) devices", `deviceinfoservice.cpp:237`).
- Pro firmware 2.0.2 added extra unknown services (`notes.md:19-22`).
- **Physical mode switch on the Pro**: the position is readable (Status byte 6, 4.6) and is documented only as an enum (V / multi-mode / A). **What the device does if the requested multimeter mode or range does not match the switch position (rejects the write, returns Error status 255, ignores, etc.) is NOT FOUND in any source.** Which modes/ranges belong to each switch position is also not stated (the enum comments at `statusservice.h:102-106` are the only hint: Voltage position; "Resistance / Low Current / Capacitance / Diode" for the middle; "High Current" for the A position). No source documents whether the Meter/Pro switch affects DSO/logger either.
- Firmware-bug comments in dokit: only (a) Meter DSO fails above 8191 samples (`dsocommand.cpp:240-241`), (b) Pro Flash LED ATT error 0x80, (c) Serial Number trailing NUL. No MTU, connection-interval, or timing notes exist; dokit only logs connection parameter updates (`pokitdevice.cpp:364-369`).

### 5.5 Other operational notes
- Status notifications: Meter has none, so poll with reads (`statusservice.h:154`).
- Characteristics must not be used before service-detail discovery completes; cached values via the stack (`abstractpokitservice.cpp:268-298`).
- Reading/Status parsing tolerates *longer* values (extra bytes ignored with a warning) to cope with firmware growth (`abstractpokitservice.cpp:394-417`; tests at `TEST:testmultimeterservice.cpp:262-268`); a decoder should therefore accept `>= min` lengths.
- Notification payloads >20 bytes (Pro logger 176 B) imply an ATT MTU of at least ~179 or long-notification support; the sources do not discuss MTU **[inference]**.
- DSO flow (CLI): enable Metadata and Reading notifications, then write Settings; Metadata notification gives scale/sample count; collect `numberOfSamples` int16 values from Reading notifications; multiply by scale (`dsocommand.cpp:371-381,410-421,440-470`).
- Logger flow: Start (write settings with command 0) / Stop (command 1) / fetch = enable Metadata + Reading notifications then write command 2 (3.12-3.14).

---

## 6. Discrepancies

### 6.1 The multimeter Reading UUID question
- JS client: `047d3559-8bee-423a-b229-4417fa603b90` (`app.js:5`, var `mmservice_measurement_uuid`).
- dokit: `047d3559-8bee-423a-b229-4417fa603b90` (`include/qtpokit/multimeterservice.h:36`).
- PDF: `047d3559-8bee-423a-b229-4417fa603b90` (p.7, section 2.3.2, Read/Notify, 7 bytes; also p.20 summary).
**All three agree exactly. There is no discrepancy.** (Likewise the Settings UUID `53dc9a7a-bc19-4280-b76b-002d0e23b078` is identical in all three: `app.js:4`, `multimeterservice.h:33`, PDF p.5; the MM service UUID `e7481d2f-5781-442e-bb9a-fd4e3441dadc` is identical: `app.js:3`, `multimeterservice.h:28`, PDF p.5.) Note the JS names it "measurement".

### 6.2 PDF vs dokit
1. **Status service UUID**: PDF p.15 only knows `...aec4`; Pro uses `...aec5` (`statusservice.cpp:27-29`: "API 1.00 (and 0.02) states ... aec4 which is correct for the Pokit Meter, but Pokit Pro uses aec5"). JS has both (`app.js:1-2`).
2. **Meter current ranges**: PDF p.6/7/9/12-14: idx 0 "0A to 10mA", 1 "10-30 mA", 2 "30-150 mA", 3 "150-300 mA", 4 "300mA to **3A**"; dokit Meter idx 4 = "Up to **2A**" (2,000,000 uA; `pokitmeter.h:25`, `pokitmeter.cpp:51`). PDF device characteristics also say Max Current "2 (A)" (p.15, p.20), so the PDF is internally inconsistent; dokit and the 2 A device value agree. Treat the Meter's top current range as 2 A, but be aware the vendor doc says 3 A.
3. **Status characteristic length/content**: PDF 5 bytes (device status + battery voltage). dokit: Meter 5, Pro 8 (adds battery status at [5], switch position [6], charging status [7]); "API 1.00" 6 bytes (not in sources) (`statusservice.cpp:633-639`).
4. **Battery voltage range**: PDF p.16 "0.0 - 3.3 (V)"; real devices: Meter 2.76-2.80 V, Pro 4.09-4.20 V (tests/README). Do not clamp to 3.3.
5. **Data Logger update interval**: PDF p.13 Settings uint16 seconds (p.20 summary: "1 - 3600 (s)", small print); PDF p.14 Metadata "uint16, in **microseconds**". dokit: Meter = uint16 *seconds* in both; Pro = uint32 *milliseconds*, with different total sizes (Pro settings 13 B, metadata 23 B with 6 unknown bytes) (`dataloggerservice.cpp:365-419`).
6. **Logger Metadata sample count**: PDF p.14 "1 to 6192"; PDF summary p.20 reads "0 - 8192" (small print; as I read it). dokit says 6192 (`dataloggerservice.h:90`).
7. **DSO number of samples**: PDF 1..8192 (p.9-10); dokit: Meter breaks above 8191, Pro up to 16384 (`dsocommand.cpp:238-253`).
8. **DSO max sample rate**: PDF text p.8 "up to 10M samples per second" and p.10 Metadata "1 to 10000000 (Hz)"; PDF summary p.20 and Device Characteristics p.15 say 1,000,000 Hz / 1000 KHz; dokit uses 1 MHz for both products (`dsocommand.cpp:258`). So the PDF is internally inconsistent; real devices: 1 MHz.
9. **Modes 9 (Capacitance) and 10 (External temperature)** (and logger mode 5 Temperature, Pro current/voltage/resistance/capacitance tables, Torch, Button Press, Calibration service, OTA, Serial Number characteristic, Pro 8-byte status) are not in the PDF; dokit documents them as reverse-engineered (`multimeterservice.cpp:27-36`, `pokitpro.cpp`, `statusservice.h:50,53`).
10. **Flash LED**: PDF p.16 lists it for the device generally; dokit finds it write-only on Meter and failing (ATT 0x80) on Pro (`statusservice.h:163`).
11. **Device Characteristics "Max" values**: PDF p.15 (Meter) 60 V / 2 A / 1000 kΩ / 1000 kHz / 8192; real Pro reports 850 / 10 / 3000 / 1000 / 16384 (`TEST:teststatusservice.cpp:362-365`). Also the PDF table labels the resistance field "Max Voltage" a second time (typo, p.15); dokit treats offset 6 as max resistance (`statusservice.cpp:597`).
12. **Device Name table**: PDF p.16 lists a spurious "Battery Voltage" attribute in the Device Name characteristic (copy-paste; actual value is just the name bytes: dokit decodes the whole value as UTF-8, `statusservice.cpp:326`).
13. **Resistance range top for Meter** is consistent (idx 7 = 1 MΩ). **Meter voltage** consistent (PDF p.6 idx 0-5, 255). No other numerical mismatch found for Meter voltage/resistance.
14. **PDF Data logger/DSO "Mode" lists only 0-4**; dokit's DataLogger enum adds 5 Temperature.
15. **Typo in dokit header**: `pokitpro.h:32` comment "Up to 5μA" vs actual 500 uA. Harmless.
16. **dokit doc/code mismatch**: `DataLoggerService::fetchSamples` and the DSO "fetch" documentation say "Refresh"; for the DSO the code sends command 3 (ResendData) (`dsoservice.cpp:201-217`). Harmless.
17. **JS vs dokit**: JS treats continuity by `value < 1000.0` (ohm-like threshold) and ignores the status byte (`app.js:121-130`); dokit/PDF define Continuity status 0/1 (status byte). JS declares units V/A/Ohm/°C and never uses Capacitance (mode 9) or External Temp (10); JS writes Settings with `mode` taken from a JS object key (string), which DataView coerces (`app.js:78,155`).

---

## 7. Open questions / not found in sources

- Whether any Pokit device requires BLE pairing/bonding/encryption (no source says; nothing in dokit or the JS code requests it).
- Factory default device names for Meter / Pro (README only shows renamed examples).
- Write type (with/without response) per characteristic: only inferable that the Settings write is used with response; no source lists the characteristic properties bitfield beyond "Write".
- Minimum/maximum multimeter update interval; behaviour at very short intervals; whether the device keeps notifying after the client disconnects/reconnects (device state after disconnect, auto-idle).
- Overload / out-of-range signalling in the Reading (no flag defined; possible +Inf value or status 255, unverified). No polarity flag defined.
- Which modes/ranges the Pro accepts in which position of its physical switch (Status byte 6). (Not in dokit, JS, or PDF.) Observed on the owner's Pokit Pro (2026-11-27, reported in words, no byte capture): a Settings write for a mode that does not suit the switch gets an ATT error (code not recorded); the same write is accepted once the switch has been moved to a suitable position; moving the switch during a running measurement is reflected in Status, and the measurement carries on when the switch is back.
- Meaning of the Status "Low" battery threshold; calibrated unit of battery voltage beyond "volts"; Status length 7 (parser accepts; never observed) and lengths > 8.
- Button Press byte 0 meaning; the two unknown Pro Status-service characteristics; Calibration Get/Set Param layouts; OTA service protocol; unknown services listed in section 2.8.
- Whether the Meter supports Capacitance/External Temperature; whether Pro status values exist for capacitance/external temperature modes (Status enum has no such values).
- MTU / connection interval / ATT payload sizing requirements (large Pro logger notifications of 176 bytes imply long notifications or larger MTU; not discussed in sources).
- Whether the Status-service Device Name and GAP Device Name (0x2A00) are the same value.
- Data Logger Metadata bytes 13-18 on Pro (6 unknown bytes); logger Arguments field use.
- Clamp or other products: `PokitClamp = 3` is only a commented-out placeholder (`pokitproducts.h:22`); no data.
- PDF p.20 summary table is small print; values quoted from it ("1 - 3600 (s)", "0 - 8192") may be misread; the detailed pages (p.5-18) were legible and are the primary PDF citations.
