# Verification and implementation evidence

## RTL regression

Validated on **20 November 2026** with **Vivado XSim 2024.1**: **23 checks passed**. The [saved result](reports/2026-11-20-rtl-regression.txt) includes source hashes and passing assertions. The project-recreation script was also run successfully and generated a new Vivado project with VIO output products. A fresh synthesis/implementation build was not run for this validation.

`verification/tb_rfid_access.v` adds executable checks around the existing, unchanged `rfid_reader_top.v`. The original `tb_rfid_reader.v` is retained as a waveform-oriented example.

The regression checks:

- Reset and default authorized access, including the three abstract command outputs.
- Wrong UID denial; unsupported ATQA and SAK rejection without changing the UID failure count.
- Failure-count clearing after successful access or enrollment.
- First/second mismatch denial and lockout on the third mismatch.
- Ignored scan/enrollment requests during lockout, recovery, and the exact inclusive timer boundary.
- Replacing the authorized UID and rejecting the previous UID.
- Latching card fields and accepting only one scan from a held trigger.
- Volatile enrollment, default-UID restoration, and reset during lockout.

Simulation uses an 8 ns clock and `LOCK_CYCLES = 40` to test the lockout boundary quickly. The board wrapper retains its original `1_250_000_000` setting. Each transaction is driven on falling clock edges, while the monitor samples after rising-edge updates.

Run instructions are in the [main README](../README.md#quick-start-simulate-without-a-board). The runner requires a passing completion marker, a successful tool exit, and a generated trace. A watchdog terminates a hung test.

The GitHub Actions workflow runs the same testbench with Icarus Verilog and uploads the transcript and CSV trace for each run. Board-level VIO integration requires AMD Vivado; the standalone regression does not simulate vendor IP.

## Archived Vivado implementation

The original local project contained reports dated **16 November 2026** and a generated bitstream. The repository keeps readable report excerpts rather than generated caches or bitstreams:

- [Timing summary excerpt](reports/2026-11-16-timing-summary.txt)
- [Placed utilization report](reports/2026-11-16-utilization.txt)

The timing excerpt retains the settings, timing checks, summary, and path-group tables; detailed paths are omitted. The local computer name is removed from both files. These are historical artifacts, not results of a fresh synthesis or evidence of a live board test. No source hash was recorded at the original report-generation time, so their correspondence to the current RTL is not independently established.

| Metric | Archived value |
| --- | ---: |
| Slice LUTs | 698 (1.31%) |
| Slice registers | 1,332 (1.25%) |
| Worst setup slack | +2.732 ns |
| Total negative setup slack | 0.000 ns |
| Worst hold slack | +0.061 ns |
| Failing setup / hold endpoints | 0 / 0 |

These totals include the VIO and debug hub; they do not isolate the access controller's area. Slack is the remaining time margin on the analyzed paths. The report says the supplied constraints are met, while also listing **3 inputs with no input delay**, **6 outputs with no output delay**, **TIMING-18** warnings, and **LUTAR-1** warnings. These limits prevent treating the report as complete external-interface timing signoff.

## What remains unverified

- A repeatable physical-board demonstration and recorded output.
- Physical RFID communication or real-card interoperability.
- Mechanical button behavior, clock-domain crossing robustness, and external I/O timing closure.
- Security properties beyond the modeled UID comparison and timer behavior.

The [design notes](design.md) describe known behavior that is intentionally preserved, including the lock timer's extra clock period and the fast lock-status LED toggle.
