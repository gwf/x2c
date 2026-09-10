"""The Python view of membytes.c, so both languages read one counter set.

`run.py build` compiles membytes.c into the benchmark binary directory as
a dylib; this module loads it through ctypes. If the dylib is missing the
samples report 0, which the runner treats as missing, not as zero bytes.
"""

import ctypes
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

LIBRARY = os.path.join(common.BINARIES, "libmembytes.dylib")

_library = None
if os.path.exists(LIBRARY):
    _library = ctypes.CDLL(LIBRARY)
    for name in ("xb_footprint", "xb_footprint_peak", "xb_resident",
                 "xb_resident_peak"):
        getattr(_library, name).restype = ctypes.c_uint64
        getattr(_library, name).argtypes = []


def _read(name):
    return int(getattr(_library, name)()) if _library else 0


def footprint():
    return _read("xb_footprint")


def footprint_peak():
    return _read("xb_footprint_peak")


def resident():
    return _read("xb_resident")


def resident_peak():
    return _read("xb_resident_peak")


def available():
    return _library is not None
