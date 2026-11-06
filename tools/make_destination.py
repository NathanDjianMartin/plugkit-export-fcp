#!/usr/bin/env python3
"""Builds Resources/PlugKit.fcpxdest, the Final Cut share destination, from the structure Frame.io's own app ships:
an FFShareExportMediaDestination (Export Media, H.264) whose post-export job action is "Open with Application".
Usage: make_destination.py <Frame.io H.264.fcpxdest> <app path> <out>"""
import plistlib, sys, uuid

src, app, out = sys.argv[1:4]
d = plistlib.load(open(src, "rb"))
objs = d["$objects"]
for i, o in enumerate(objs):
    if not isinstance(o, str):
        continue
    if o == "Frame.io H.264":
        objs[i] = "PlugKit"
    elif 'jobAction kind="open"' in o:
        objs[i] = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><jobAction kind="open" '
                   f'name="Open with Application" flags="1" job-count="1" default-title="" appName="{app}"/>')
    elif len(o) == 36 and o.count("-") == 4:
        objs[i] = str(uuid.uuid5(uuid.NAMESPACE_URL, "com.nathan.plugkitexport.destination")).upper()
plistlib.dump(d, open(out, "wb"), fmt=plistlib.FMT_BINARY)
