# light-bench

A single-file benchmark for Linux VMs. No config, no bloat — one script, ~2 minutes, and a summary block you can diff between machines.

Covers:

- **CPU** — sysbench prime workload, single thread and all cores, scaling factor, plus **steal time** measured during the run (catches oversubscribed hosts)
- **Memory** — sequential write/read bandwidth, plus random-access read as a latency proxy
- **Disk** — fio with direct I/O: sequential MiB/s, random 4k IOPS, and fsync latency p50/p99 (the number that matters for databases)
- **Network** — ping RTT and download throughput (skippable)

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
  cpu    4612 single | 17216 x10 (3.73x) | steal 0.0%  [events/s]
  mem    28504 write | 56091 read | 914 rnd  [MiB/s]
  disk   7643 write | 11220 read  [MiB/s]
  iops   120295 write | 269349 read  [4k rand]
  fsync  0.05 p50 | 0.60 p99  [ms]
  net    ping 8.2 ms | down 107 Mbit/s
```

## Notes

- The disk test writes a temporary 1 GiB file (smaller if space is tight) in the target directory and removes it afterwards.
- The download test pulls a 100 MB file from Hetzner Ashburn, capped at 30 seconds.
- On shared hosts, run it twice at different hours — noisy neighbors vary by time of day, and the spread between runs is itself useful data.
- Numbers are for comparing VMs against each other under identical settings, not absolute hardware truth.

## License

MIT
