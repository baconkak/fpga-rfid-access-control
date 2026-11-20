# Design notes

## Interfaces

`rfid_reader_top` is independent of AMD IP. It receives an 8 ns clock, synchronous active-high reset, a scan trigger, a live registration-mode input, and parallel card fields. The board wrapper instantiates this core and the `vio_0` debug IP.

The core captures ATQA, UID, and SAK on a rising scan event. It does not wait for card responses from a reader: `WAIT_*` states advance over captured data. Inputs changing after capture do not affect the current transaction unless another trigger edge occurs. The registration switch is read live and should remain stable throughout a transaction.

## State map

| Value | State | Main action |
| ---: | --- | --- |
| 0 | IDLE | Wait for a scan |
| 1 | SEND_REQA | Present command `0x26` |
| 2 | WAIT_ATQA | Require ATQA `0x0004`, otherwise deny |
| 3 | SEND_ANTICOLL | Present command `0x93` |
| 4 | WAIT_UID | Advance using the captured UID |
| 5 | SEND_SELECT | Present command `0x70` |
| 6 | WAIT_SAK | Require SAK `0x08`, otherwise deny |
| 7 | CHECK_ACCESS | Enroll, compare UID, and update the failure count |
| 8 | GRANTED | Assert green; accept a new scan |
| 9 | DENIED | Assert red; accept a new scan |
| 10 | LOCKED | Ignore access requests until the timer expires |

## Enrollment and failure counting

- Reset sets the only authorized UID to `0x904B0296`.
- A valid-format card in registration mode replaces that UID. There is no administrator authentication or nonvolatile storage.
- A successful normal scan or successful registration clears the failure count.
- Wrong UIDs reaching `CHECK_ACCESS` increment the count. The third mismatch enters `LOCKED`.
- ATQA or SAK mismatches go directly to `DENIED` and leave the failure count unchanged. They neither increment nor clear it.
- Reset exits lockout immediately and restores the default UID.

## Lock timing and indicators

The board wrapper sets `LOCK_CYCLES = 1_250_000_000`, targeting approximately 10 seconds at 125 MHz. With the current inclusive counter comparison, the state is occupied for `LOCK_CYCLES + 1` clock periods: 10 seconds plus 8 ns. The regression verifies this boundary with a smaller parameter.

`led_red = lock_timer[3]` in `LOCKED`. At 125 MHz this toggles too quickly to provide a visible slow blink; use the numeric state or a waveform to distinguish lockout. Green/red access results persist in the granted/denied states. Blue follows registration mode directly, including while locked.

## Board connections from the supplied XDC

| Signal | Board control / output | FPGA pin |
| --- | --- | --- |
| `clk` | 125 MHz system clock | H16 |
| `btn0_rst` | BTN0 | D19 |
| `btn1_scan` | BTN1 | D20 |
| `sw0_reg` | SW0 | M20 |
| `led[0:3]` | LD0–LD3, binary state | R14, P14, N16, M14 |
| `led4_r` | LD4 red | N15 |
| `led4_g` | LD4 green | G17 |
| `led4_b` | LD4 blue | L15 |

All listed I/O uses `LVCMOS33`. These are the assignments in the project; check your board revision before wiring external hardware.

## VIO probes

Directions below are relative to the VIO IP. Outputs drive the controller; inputs observe it.

| Probe | Width | Function | Initial value |
| --- | ---: | --- | --- |
| `probe_out0` | 1 | Scan trigger | `0` |
| `probe_out1` | 16 | ATQA | `0x0004` |
| `probe_out2` | 32 | UID | `0x904B0296` |
| `probe_out3` | 8 | SAK | `0x08` |
| `probe_in0` | 4 | Controller state | Observed |
| `probe_in1` | 8 | Abstract command | Observed |

## Clock and protocol limitations

The scan path uses two sampling registers, but the edge detector consumes the first register as well as the second. It should be redesigned and reviewed before treating it as a hardened asynchronous input crossing. Reset and registration mode also need a board-level synchronization review. Neither button is debounced.

The design does not implement RF transmission, a reader-chip bus, CRC/parity, multi-card anticollision, 7/10-byte UID cascade levels, cryptographic authentication, or protocol response timeouts. The command bytes are markers for the modeled sequence; `0x70` alone is not a complete SELECT frame.

No claim of production security or full protocol compliance is made. The existing RTL is preserved so that documented behavior, simulation evidence, and archived implementation results remain easy to compare.
