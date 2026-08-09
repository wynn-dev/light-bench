# light-bench

A single-file benchmark for Linux VMs. No config, no bloat — one script, ~2 minutes, and a summary block you can diff between machines.

Covers:

- **CPU** — sysbench prime workload, single thread and all cores, with a scaling factor
- **Memory** — sequential write/read bandwidth (sysbench, 1M blocks)
- **Disk** — fio with direct I/O: sequential MiB/s, random 4k IOPS, and fsync latency p50/p99 (the number that matters for databases)
- **Network** — ping RTT and download throughput (skippable)

## Usage

```sh
curl -fsSL https://raw.githubusercontent.com/wynn-dev/light-bench/main/bench.sh -o bench.sh
chmod +x bench.sh
./bench.sh
```

Requires `sysbench`, `fio`, and `curl`. If any are missing, the script prints the exact install command for your distro's package manager — or run `./bench.sh --install` to let it install them via sudo.

### Flags

| Flag | Effect |
|------|--------|
| `-d DIR` | Directory for disk tests (default: current dir). Point it at the disk you care about. |
| `--no-net` | Skip the network section (airgapped VMs). |
| `--install` | Install missing dependencies via the detected package manager. |

## Sample output

```
== Summary ==
cpu single-thread      4663.44 events/s
cpu 10-thread          22772.48 events/s (4.88x)
mem write / read       47832.86 / 68868.55 MiB/s
disk seq w / r         5349 / 9389 MiB/s
disk rand w / r        226708 / 344748 IOPS
fsync p50 / p99        0.06 / 0.58 ms
net ping / down        95.065 ms / 108 Mbit/s
```

## Notes

- The disk test writes a temporary 1 GiB file (smaller if space is tight) in the target directory and removes it afterwards.
- The download test pulls a 100 MB file from Hetzner Ashburn, capped at 30 seconds.
- Numbers are for comparing VMs against each other under identical settings, not absolute hardware truth.

## License

MIT
