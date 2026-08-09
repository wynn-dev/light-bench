#!/usr/bin/env bash
# bench.sh — light Linux VM benchmark: CPU, memory, disk, network. ~2 min.
# Requires: sysbench, fio (v3+), curl. Usage: ./bench.sh [-d DIR] [--no-net] [--install]
set -u
export LC_ALL=C

DIR=.
NET=1
INSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    -d) DIR=$2; shift 2 ;;
    --no-net) NET=0; shift ;;
    --install) INSTALL=1; shift ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1 (see --help)" >&2; exit 1 ;;
  esac
done

# ---------- dependencies ----------
missing=""
for c in sysbench fio curl; do
  command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
done
if [ -n "$missing" ]; then
  pm=""
  for p in apt-get dnf yum apk pacman zypper; do
    command -v "$p" >/dev/null 2>&1 && { pm=$p; break; }
  done
  case "$pm" in
    apt-get) cmd="apt-get update && apt-get install -y$missing" ;;
    dnf|yum) cmd="$pm install -y epel-release &&$pm install -y$missing" ;;
    apk)     cmd="apk add$missing" ;;
    pacman)  cmd="pacman -Sy --noconfirm$missing" ;;
    zypper)  cmd="zypper install -y$missing" ;;
    *)       cmd="" ;;
  esac
  if [ "$INSTALL" = 1 ] && [ -n "$cmd" ]; then
    echo "installing:$missing"
    sudo sh -c "$cmd" || { echo "install failed" >&2; exit 1; }
  else
    echo "missing tools:$missing" >&2
    [ -n "$cmd" ] && echo "install with:  sudo sh -c '$cmd'  (or rerun with --install)" >&2
    exit 1
  fi
fi

hdr() { printf '\n== %s ==\n' "$1"; }

# ---------- system info ----------
hdr "System"
CORES=$(nproc)
CPU_MODEL=$(awk -F': ' '/model name/{print $2; exit}' /proc/cpuinfo)
CPU_MODEL=${CPU_MODEL:-$(uname -m)}
RAM_MB=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)
VIRT=$(systemd-detect-virt 2>/dev/null || echo "unknown")
DISTRO=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")
printf '%-8s %s\n' host "$(hostname)" distro "${DISTRO:-unknown}" kernel "$(uname -r)" \
  cpu "$CPU_MODEL (${CORES}c)" ram "${RAM_MB} MB" virt "$VIRT"

# ---------- cpu ----------
hdr "CPU (sysbench, prime 20000, 10s/run)"
cpu_run() { sysbench cpu --cpu-max-prime=20000 --threads="$1" --time=10 run \
              | awk '/events per second/{print $4}'; }
CPU1=$(cpu_run 1);        echo "1 thread : $CPU1 events/s"
CPUN=$(cpu_run "$CORES"); echo "$CORES threads: $CPUN events/s"
SCALE=$(awk "BEGIN{printf \"%.2f\", $CPUN/$CPU1}")
echo "scaling  : ${SCALE}x"

# ---------- memory ----------
hdr "Memory (sysbench, 1M blocks, 5s/run)"
mem_run() { sysbench memory --memory-block-size=1M --memory-total-size=512G \
              --memory-oper="$1" --time=5 run \
              | sed -n 's/.*(\([0-9.]*\) MiB\/sec).*/\1/p'; }
MEMW=$(mem_run write); echo "write: $MEMW MiB/s"
MEMR=$(mem_run read);  echo "read : $MEMR MiB/s"

# ---------- disk ----------
TESTFILE=$DIR/.bench.$$.tmp
trap 'rm -f "$TESTFILE"' EXIT
avail_mb=$(df -Pk "$DIR" | awk 'NR==2{printf "%d", $4/1024}')
SIZE_MB=1024
[ "$avail_mb" -lt 4096 ] && SIZE_MB=$((avail_mb / 4))
[ "$SIZE_MB" -lt 64 ] && { echo "not enough free space in $DIR for disk test" >&2; exit 1; }
hdr "Disk (fio, ${SIZE_MB}M file in $DIR, direct I/O, 10s/run)"

fio_terse() { # fio_terse <extra args...> -> terse line (empty on failure)
  fio --name=bench --filename="$TESTFILE" --size="${SIZE_MB}M" --runtime=10 \
      --time_based --direct=1 --ioengine=libaio --randrepeat=0 \
      --output-format=terse --terse-version=3 "$@" 2>/dev/null | tail -1
}
f() { echo "$1" | cut -d';' -f"$2"; }   # f <terse line> <field>

t=$(fio_terse --rw=read --bs=1M --iodepth=8)
SEQR=$(awk "BEGIN{printf \"%.0f\", $(f "$t" 7)/1024}");  echo "seq read  : $SEQR MiB/s"
t=$(fio_terse --rw=write --bs=1M --iodepth=8)
SEQW=$(awk "BEGIN{printf \"%.0f\", $(f "$t" 48)/1024}"); echo "seq write : $SEQW MiB/s"
t=$(fio_terse --rw=randread --bs=4k --iodepth=32)
RNDR=$(awk "BEGIN{printf \"%.0f\", $(f "$t" 8)}");       echo "rand read : $RNDR IOPS (4k)"
t=$(fio_terse --rw=randwrite --bs=4k --iodepth=32)
RNDW=$(awk "BEGIN{printf \"%.0f\", $(f "$t" 49)}");      echo "rand write: $RNDW IOPS (4k)"

# fsync latency (buffered 4k writes + fsync each — the database-relevant number).
# Sync percentiles only exist in JSON output; the sync block is last, hence tail -1.
j=$(fio --name=fsync --filename="$TESTFILE" --size="${SIZE_MB}M" --runtime=10 \
        --time_based --rw=write --bs=4k --iodepth=1 --fsync=1 --ioengine=libaio \
        --randrepeat=0 --output-format=json 2>/dev/null)
FS50=$(echo "$j" | grep -o '"50.000000" : [0-9]*' | tail -1 | awk '{printf "%.2f", $3/1e6}')
FS99=$(echo "$j" | grep -o '"99.000000" : [0-9]*' | tail -1 | awk '{printf "%.2f", $3/1e6}')
echo "fsync lat : p50 ${FS50} ms, p99 ${FS99} ms"
rm -f "$TESTFILE"

# ---------- network ----------
PING="skipped" DL="skipped"
if [ "$NET" = 1 ]; then
  hdr "Network"
  rtt=$(ping -c 5 -q 1.1.1.1 2>/dev/null | awk -F'/' '/^(rtt|round-trip)/{print $5}')
  PING=${rtt:+"$rtt ms"}; PING=${PING:-"n/a (icmp blocked?)"}
  echo "ping 1.1.1.1 : $PING"
  bps=$(curl -fs -o /dev/null --max-time 30 -w '%{speed_download}' \
        'https://ash-speed.hetzner.com/100MB.bin' 2>/dev/null)
  DL=$(awk "BEGIN{v=${bps:-0}*8/1e6; if (v>=1) printf \"%.0f Mbit/s\", v;
        else if (v>0) printf \"%.2f Mbit/s\", v; else print \"n/a\"}")
  echo "download     : $DL (hetzner ashburn, 100 MB, 30s cap)"
fi

# ---------- summary ----------
hdr "Summary"
printf '%-22s %s\n' \
  "cpu single-thread"  "$CPU1 events/s" \
  "cpu ${CORES}-thread"       "$CPUN events/s (${SCALE}x)" \
  "mem write / read"   "$MEMW / $MEMR MiB/s" \
  "disk seq w / r"     "$SEQW / $SEQR MiB/s" \
  "disk rand w / r"    "$RNDW / $RNDR IOPS" \
  "fsync p50 / p99"    "$FS50 / $FS99 ms" \
  "net ping / down"    "$PING / $DL"
