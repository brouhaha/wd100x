# wd100x - Reverse-engineered WD100x disk controller firmware

Copyright 2016, 2022 Eric Smith <spacewar@gmail.com>

wd100x development is hosted at the
[wd100x Github repository](https://github.com/brouhaha/wd100x/).

## Introduction

Western Digital's earliest hard disk controllers were board-level
products based on the Signetics 8X300 or 8X305 bipolar microprocessors.
They supported up to four drives with the ST506 interface (5.25-inch)
or SA1000 interface (8-inch).

The 8X300 was chosen because, as a bipolar processor, it was much faster
than the contemporary MOS microprocessors. Operating from an 8.0 MHz
crystal, instruction execution time is 250 ns.

The 8X300 uses 16-bit instructions, but the WD1000 and WD1001 use
24-bit wide instruction memory in the form of three 8-bit wide
bipolar PROMs. The additonal eight bits are used to provide I/O
port addressing in parallel with instruction execution.

The original WD1000 was 8X300-based and used CRC error detection.
There were two main versions of WD1000 firmware, using different sized
PROMs. The "small" version used 512-byte bipolar PROMs, and the
"large" version used 1024-byte bipolar PROMs. The small firmware
only supported a fixed sector size, which could be hard-coded as
128, 256, or 512 bytes. The large firmware allows the sector size
to be selected by the host.

Later WD1000 boards used the 8X305, but the firmware does not take
advantage of the 8X305 enhancements.

The later WD1001 was 8X305-based, used 32-bit ECC on the sector data
fields, always used "large" firmware, and supported configurable
sector size. The WD1001 firmware does not take advantage of the 8X305
enhancements, so substituting an 8X300 should work just as well.

The WD1000 host interface had a "task file" of eight registers, which
was used with minor changes by WD1010 and WD2010 hard disk controller
chips, the IBM PC/AT disk controller, and later, with more substantial
changes, by the ATA (IDE) disk interface.

## Status

The assembler syntax used does not match any existing 8X300 assembler,
including Signetics MCCAP. This assembly source code has not been
assembled for verification against the actual WD1000 PROM chips.

The source code was originally derived from a disassembly produced by
[s8x30x](https://github.com/brouhaha/s8x30x).

## License information

This program is free software: you can redistribute it and/or modify
it under the terms of version 3 of the GNU General Public License
as published by the Free Software Foundation.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <http://www.gnu.org/licenses/>.
