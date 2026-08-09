# light-bench

A single-file benchmark for Linux VMs. No config, no bloat — one script, ~2 minutes, and a summary block you can diff between machines.

Covers:

- **CPU** — sysbench prime workload: single-thread median of 3 runs with **spread %** (noisy-neighbor signal), all-core scaling factor, **steal time** measured during the run (catches oversubscribed hosts), and AES-256-GCM throughput if openssl is present (exposes missing AES-NI passthrough)
- **Memory** — sequential write/read bandwidth, plus random-access read as a latency proxy
- **Disk** — fio with direct I/O: sequential MiB/s, random 4k IOPS **with p99 latency** (catches throttled cloud volumes), QD1 read latency (true device latency), and fsync p50/p99 (the number that matters for databases)
- **Network** — ping RTT, TTFB to a CDN (works where ICMP is blocked), and download throughput (skippable)

## Usage

```sh
curl -fsSL https://raw.githubusercontent.com/wynn-dev/light-bench/main/bench.sh | bash
```

If `sysbench`/`fio`/`curl` aren't installed yet, this variant installs them first (apt/dnf/yum/apk/pacman/zypper are auto-detected):

```sh
curl -fsSL https://raw.githubusercontent.com/wynn-dev/light-bench/main/bench.sh | sudo bash -s -- --install
```

### Flags

Pass flags after `bash -s --`, e.g. `... | bash -s -- -d /data --no-net`.

| Flag | Effect |
|------|--------|
| `-d DIR` | Directory for disk tests (default: current dir). Point it at the disk you care about. |
| `--no-net` | Skip the network section (airgapped VMs). |
| `--install` | Install missing dependencies via the detected package manager. |

## Sample output

```
== Summary ==
  host   myvm | Ubuntu 24.04.4 LTS | aarch64 10c | 7936 MB | kvm
  cpu    4554 single (±1.5%) | 20723 x10 (4.55x) | steal 0.0%  [events/s]
  aes    7940  [MiB/s, aes-256-gcm 1 thread]
  mem    48259 write | 69170 read | 1017 rnd  [MiB/s]
  disk   7519 write | 11593 read  [MiB/s seq]
  iops   231321 write (p99 0.28) | 321823 read (p99 0.28)  [4k QD32, ms]
  lat    0.03 p50 | 0.04 p99  [4k QD1 read, ms]
  fsync  0.05 p50 | 0.40 p99  [ms]
  net    ping 8.2 ms | ttfb 45 ms | down 940 Mbit/s
```

## Notes

- The disk test writes a temporary 1 GiB file (smaller if space is tight) in the target directory and removes it afterwards.
- The download test pulls a 100 MB file from Hetzner Ashburn, capped at 30 seconds.
- On shared hosts, run it twice at different hours — noisy neighbors vary by time of day, and the spread between runs is itself useful data.
- Numbers are for comparing VMs against each other under identical settings, not absolute hardware truth.

## License

MIT
