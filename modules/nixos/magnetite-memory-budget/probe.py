"""magnetite's memory budget as node_exporter textfile series (CAM-111 D11).

Writes, by write-then-rename, one file of:
  vanixiets_unit_memory_current_bytes{unit="<unit>"} and
  vanixiets_unit_memory_peak_bytes{unit="<unit>"} from systemd's
  MemoryCurrent and MemoryPeak, for each active unit matching the
  configured patterns and for system.slice and user.slice, and
  vanixiets_zram_{orig_data,compr_data,mem_used}_bytes from zram0's mm_stat.
systemd reads each unit's own cgroup wherever it is nested, so a unit
under a sub-slice is covered. An inactive unit, or a value systemd reports
as [not set], writes no series.

Usage: probe.py CONFIG OUTPUT_FILE
       probe.py --format CONFIG SHOW_OUTPUT MM_STAT   (prints the file)
CONFIG is JSON: {"units": [patterns], "aliases": {owner: alias}}.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

SLICES = ["system.slice", "user.slice"]
ZRAM = Path("/sys/block/zram0/mm_stat")
ZRAM_FIELDS = ["orig_data", "compr_data", "mem_used"]
OWNER_UNIT = re.compile(r"^omnigent-host-(?P<owner>.+)\.service$")


def parse_show(text):
    """systemctl show output for several units: blank-line separated
    blocks of Key=Value lines."""
    units = []
    for block in text.strip().split("\n\n"):
        props = {}
        for line in block.splitlines():
            key, sep, value = line.partition("=")
            if sep:
                props[key] = value
        if props:
            units.append(props)
    return units


def label(unit, aliases):
    match = OWNER_UNIT.match(unit)
    if match and match.group("owner") in aliases:
        return f"omnigent-host-{aliases[match.group('owner')]}.service"
    return unit


def format_budget(show_text, mm_stat_text, aliases):
    lines = []
    for props in parse_show(show_text):
        unit = props.get("Id", "")
        if not unit or props.get("ActiveState") != "active":
            continue
        name = label(unit, aliases)
        for prop, metric in (
            ("MemoryCurrent", "current"),
            ("MemoryPeak", "peak"),
        ):
            value = props.get(prop, "")
            if value.isdigit():
                lines.append(
                    f'vanixiets_unit_memory_{metric}_bytes{{unit="{name}"}} {value}'
                )
    fields = mm_stat_text.split()
    if len(fields) >= len(ZRAM_FIELDS) and all(
        f.isdigit() for f in fields[: len(ZRAM_FIELDS)]
    ):
        for name, value in zip(ZRAM_FIELDS, fields):
            lines.append(f"vanixiets_zram_{name}_bytes {value}")
    return "".join(f"{line}\n" for line in lines)


def systemctl(*args):
    return subprocess.run(
        ["systemctl", *args], check=True, capture_output=True, text=True
    ).stdout


def collect(config):
    listed = systemctl(
        "list-units",
        "--type=service",
        "--state=active",
        "--plain",
        "--no-legend",
        *config["units"],
    )
    units = [line.split()[0] for line in listed.splitlines() if line.strip()]
    show = systemctl(
        "show",
        "-p",
        "Id,ActiveState,MemoryCurrent,MemoryPeak",
        *units,
        *SLICES,
    )
    mm_stat = ZRAM.read_text() if ZRAM.exists() else ""
    return format_budget(show, mm_stat, config["aliases"])


def main(argv):
    if argv[1] == "--format":
        config = json.loads(Path(argv[2]).read_text())
        sys.stdout.write(
            format_budget(
                Path(argv[3]).read_text(),
                Path(argv[4]).read_text(),
                config["aliases"],
            )
        )
        return
    config = json.loads(Path(argv[1]).read_text())
    output = Path(argv[2])
    text = collect(config)
    tmp = output.with_name(f".{output.name}.tmp")
    tmp.write_text(text)
    os.chmod(tmp, 0o644)
    tmp.replace(output)


if __name__ == "__main__":
    main(sys.argv)
