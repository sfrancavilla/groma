#!/usr/bin/env python3
"""The readings behind the bar's System tile.

SystemControl.qml keeps this process alive; it prints one JSON line of
readings every few seconds. A line on stdin is a new interval in seconds and
asks for a reading at once, so the tile opens on fresh numbers and polls
faster while it is looked at. stdin closing means the shell has gone, and so
does this.

One process rather than a `cat` per figure per tick: the point of the tile is
to show what the machine is doing, not to add to it.
"""
import glob
import json
import os
import selectors
import sys
import time

# Busy CPU time is everything but idle and iowait: a core waiting on the disk
# is not doing work.
IDLE_FIELDS = (3, 4)

# Where the CPU's own temperature lives, best first: the package sensor of
# AMD (Tdie is the real die, Tctl carries a fan-curve offset on some parts),
# Intel, and the common ARM name.
SENSORS = [
    ("k10temp", ("Tdie", "Tctl")),
    ("zenpower", ("Tdie", "Tctl")),
    ("coretemp", ("Package id 0",)),
    ("cpu_thermal", ()),
]


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return None


def cpu_times():
    fields = [int(v) for v in read("/proc/stat").split("\n", 1)[0].split()[1:]]
    idle = sum(fields[i] for i in IDLE_FIELDS)
    return sum(fields), idle


def memory():
    info = {}
    for line in read("/proc/meminfo").splitlines():
        key, value = line.split(":", 1)
        info[key] = int(value.split()[0]) * 1024
    return {
        "memTotal": info.get("MemTotal", 0),
        "memUsed": info.get("MemTotal", 0) - info.get("MemAvailable", 0),
        "swapTotal": info.get("SwapTotal", 0),
        "swapUsed": info.get("SwapTotal", 0) - info.get("SwapFree", 0),
    }


def find_temperature():
    """The path of the CPU's temperature, found once."""
    hwmons = {read(os.path.join(d, "name")).strip(): d
              for d in glob.glob("/sys/class/hwmon/hwmon*")
              if read(os.path.join(d, "name"))}
    for name, labels in SENSORS:
        d = hwmons.get(name)
        if not d:
            continue
        found = {(read(p) or "").strip(): p.replace("_label", "_input")
                 for p in glob.glob(os.path.join(d, "temp*_label"))}
        for label in labels:
            if label in found:
                return found[label]
        if os.path.exists(os.path.join(d, "temp1_input")):
            return os.path.join(d, "temp1_input")
    for zone in glob.glob("/sys/class/thermal/thermal_zone*"):
        if (read(os.path.join(zone, "type")) or "").strip() == "x86_pkg_temp":
            return os.path.join(zone, "temp")
    return None


def find_gpu():
    """amdgpu reports how busy it is, and its own temperature beside it;
    Intel and nouveau report neither."""
    found = sorted(glob.glob("/sys/class/drm/card*/device/gpu_busy_percent"))
    if not found:
        return None, None
    device = os.path.dirname(found[0])
    sensor = sorted(glob.glob(os.path.join(device, "hwmon", "hwmon*", "temp1_input")))
    return found[0], sensor[0] if sensor else None


def disks():
    """/ always, and /home when it is a filesystem of its own.

    Compared by device rather than by stat: Btrfs subvolumes each get their
    own st_dev, and @home on the same disk as @ has the same free space.
    """
    sources = {}
    for line in read("/proc/self/mounts").splitlines():
        source, target = line.split()[:2]
        sources[target] = source
    out = []
    for mount in ("/", "/home"):
        if mount not in sources:
            continue
        if mount != "/" and sources[mount] == sources.get("/"):
            continue
        st = os.statvfs(mount)
        out.append({
            "mount": mount,
            "size": st.f_blocks * st.f_frsize,
            "free": st.f_bavail * st.f_frsize,
        })
    return out


def main():
    temperature = find_temperature()
    gpu, gpu_temperature = find_gpu()
    threads = os.cpu_count() or 1

    interval = 3.0
    cpu = 0.0
    previous = cpu_times()
    sampled = time.monotonic()
    time.sleep(0.25)

    selector = selectors.DefaultSelector()
    selector.register(sys.stdin, selectors.EVENT_READ)

    while True:
        # A reading asked for straight after the last one would measure a
        # few ticks, which is noise: keep the last figure until there is a
        # span worth dividing.
        if time.monotonic() - sampled >= 0.25:
            total, idle = cpu_times()
            span = total - previous[0]
            cpu = 1 - (idle - previous[1]) / span if span > 0 else 0
            previous = (total, idle)
            sampled = time.monotonic()

        celsius = read(temperature) if temperature else None
        busy = read(gpu) if gpu else None
        gpu_celsius = read(gpu_temperature) if gpu_temperature else None

        reading = {
            "cpu": max(0.0, min(1.0, cpu)),
            "threads": threads,
            "load": [float(v) for v in read("/proc/loadavg").split()[:3]],
            "temperature": int(celsius) / 1000 if celsius else None,
            "gpu": int(busy) / 100 if busy else None,
            "gpuTemperature": int(gpu_celsius) / 1000 if gpu_celsius else None,
            "disks": disks(),
        }
        reading.update(memory())
        print(json.dumps(reading), flush=True)

        if selector.select(timeout=interval):
            line = sys.stdin.readline()
            if not line:
                return
            try:
                interval = max(0.5, float(line))
            except ValueError:
                pass


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
