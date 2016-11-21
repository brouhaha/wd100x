# wd100x - Reverse-engineered WD100x disk controller firmware

Copyright 2016 Eric Smith <spacewar@gmail.com>

wd100x development is hosted at the
[wd100x Github repository](https://github.com/brouhaha/wd100x/).

## Introduction

Western Digital's earliest hard disk controllers were board-level
products based on the Signetics 8X300 or 8X305 bipolar processors.
They supported up to four drives with the ST506 interface (5.25-inch)
or SA1000 interface (8-inch).

The original WD1000 used CRC error detection, and had a hard-coded
sector size of 128, 256, or 512 bytes, and changing the sector size
required a PROM change.

The later WD1001 used 32-bit ECC on the sector data fields, and the
sector size was configurable over the host interface.

The WD1000 host interface had a "task file" of eight registers, which
was used with minor changes by WD1010 and WD2010 hard disk controller
chips, the IBM PC/AT disk controller, and later, with more substantial
changes, by the ATA (IDE) disk interface.

## Status

The assembler syntax used does not match any existing 8X300 assembler,
including Signetics MCCAP.  This assembly source code has not been
assembled for verification against the actual WD1000 PROM chips.

The source code was originally derived from a disassembly produced by
[s8x30x](https://github.com/brouhaha/s8x30x).

## License information

This program is free software: you can redistribute it and/or modify
it under the terms of version 3 of the GNU General Public License
as published by the Free Software Foundation.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
