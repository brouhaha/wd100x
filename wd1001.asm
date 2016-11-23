; WD1001 hard disk controller firmware reverse-engineered source code

; Assembly source code copyright 2016 Eric Smith <spacewar@gmail.com>

; No copyright is claimed on the executable object code as
; found in the WD1001 PROM chips.

; This program is free software: you can redistribute it and/or modify
; it under the terms of version 3 of the GNU General Public License
; as published by the Free Software Foundation.

; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
; GNU General Public License for more details.

; You should have received a copy of the GNU General Public License
; along with this program.  If not, see <http://www.gnu.org/licenses/>.


; The assembler syntax used herein does not match any existing 8X305
; assembler, including Signetics MCCAP.	 This assembly source code
; has not been assembled for verification against the actual WD1001
; PROM chips.


; Fast I/O select ports
; Note that the normal 8X305 port addressing scheme is not used;
; writing to the ivl and ivr address registers writes to the port
; selected by the fast I/O select PROM.

rd_ram		riv	rr=0x0
drq_clk		liv	rr=0x1
rd2		liv	rr=0x2
int_clk		liv	rr=0x3
rd_serdes	liv	rr=0x4
rd5		liv	rr=0x5
rd_host_port	liv	rr=0x6

wr_ram		riv	wr=0x8
ram_addr	liv	wr=0xa
reset_index	liv	wr=0xb
wr_serdes	liv	wr=0xc
drive_head_sel	liv	wr=0xd
wr_host_port	liv	wr=0xe
mac_control	liv	wr=0xf


; RAM definitions
; Addresses are from the 8X305 point of view, though the hardware
; uses inverted addresses, and rearranges the bits.  Bits 1..0 of the
; address byte from the 8X305 form bits 9..8 of the RAM address.
; Bits 1..0 of the RAM address are hardwired.

; controller tracks current cylinder for each drive
drive_0_cylinder_high	equ	000h
drive_1_cylinder_high	equ	008h
drive_2_cylinder_high	equ	010h
drive_3_cylinder_high	equ	018h

buffer_512		equ	002h	; 200h

?			equ	000h
?			equ	068h
syndrome		equ	06ch
?			equ	070h
auto_restore_ok		equ	074h	; 0ffh if auto restore not done yet, 0 if it has
precomp			equ	078h
step_rate		equ	07ch
command_byte		equ	090h
seek_save_regs		equ	0a0h
seek_save_regs_2	equ	0b0h



;seek_temp_1		equ	1e0h
;seek_temp_2		equ	1e1h
;seek_temp_3		equ	1e2h

;seek_save_sector	equ	1e7h
;seek_save_sector_count	equ	1e8h
;seek_save_sdh		equ	1e9h

;saved_sector_count	equ	1f0h
;id_field_s_h_bb		equ	1f1h

;
;unk_1f8			equ	1f8h	; unkown, reset initializes to 20h

;data_buffer		equ	300h	; for 256 byte sectors
					; use 380h for 128 byte sectors
					; use 200h for 512 byte sectors

	org	0

        jmp     reset

x0001:  xmit    0h,flag

; main loop entry after host transfers a data byte to/from task file
main_loop_after_data_xfer:
	nzt     rd2[7],data_xfer_done	; if ROVF, data xfer is done

; main loop entry to set DRQ
main_loop_set_drq:
	nzt     drq_clk,main_loop	; set DRQ, read data ignored

; main loop to wait for the host to access a task file register
main_loop:
	nzt     rd2[4],main_loop	; loop until CSAC
        xec     task_file_access,rd2[3:0]	; dispatch on /HRW, /HA2../HA0
        jmp     main_loop

task_file_access:
	; host reads task file
	jmp     host_read_tf_status	; tf7: status
        move    r5,wr_host_port		; tf6: sdh
        move    r4,wr_host_port		; tf5: cyl_hi
        move    r3,wr_host_port		; tf4: cyl_lo
        move    r2,wr_host_port		; tf3: sector
        move    r1,wr_host_port		; tf2: sector count
        move    r6,wr_host_port		; tf1: error
        jmp     host_read_tf_data	; tf0: data

	; host writes task file
        jmp     host_wr_tf_cmd		; tf7: cmd
        jmp     host_wr_tf_sdh		; tf6: sdh
        move    rd_host_port,r4		; tf5: cyl_hi
        move    rd_host_port,r3		; tf4: cyl_lo
        move    rd_host_port,r2		; tf3: sector
        move    rd_host_port,r1		; tf2: sector count
        jmp     host_wr_tf_precomp	; tf1: precomp
        jmp     host_wr_tf_data		; tf0: data


data_xfer_done:
	nzt     rd2[5],x001a
        xmit    0ffh,flag
        jmp     main_loop_set_drq

x001a:  move    aux,r11

        xmit    command_byte,ram_addr
        xmit    5h,aux			; was it a format track command?
        xor     rd_ram[6:4],aux
        nzt     aux,$+2
        jmp     format_track

	xmit    command_byte,ram_addr
        move    rd_ram[4],aux		; was it a read sector command
        nzt     aux,x0090		; no, so perform command

	; was a read command, so now it's done
        xmit    command_byte,ram_addr
        xmit    10h,aux
        and     r11,r11
        nzt     rd_ram[2],$+2
        jmp     x002e

	nzt     r11,x002e

        xmit    1h,aux		; increment sector
        add     r2,r2
        xmit    0ffh,aux	; decrement sector count
        add     r1,r1
        nzt     r1,multiple_next	; sector count is zero? if no, do next

x002e:  xmit    68h,ram_addr
        move    r11,aux
        xor     rd_ram,aux
        xmit    command_byte,ram_addr
        nzt     rd_ram[4:3],x0034	; check DMA mode bit
        jmp     reset_buffer_pointer	; programmed I/O, so no int
x0034:  jmp     int_and_reset_data_pointer	; DMA done, so int


reset:  xmit    90h,mac_control
        xmit    0efh,drive_head_sel
        xmit    0h,ram_addr
x0038:  xmit    0h,wr_ram
        nzt     rd2[7],x003b
        jmp     x0038
x003b:  xmit    step_rate,ram_addr
        xmit    0fh,wr_ram
        xmit    unk_078,ram_addr
        xmit    20h,wr_ram
        xmit    1h,r1
        xmit    0h,r2
        xmit    0h,r3
        xmit    0h,r4
        xmit    0h,r5
        xmit    0h,r6
        xmit    0h,aux
        jmp     reset_buffer_pointer


host_read_tf_status:  xor     rd5[6:4],r11
        move    r11>>>4,r11
        move    r11,wr_host_port
        jmp     main_loop


host_read_tf_data:
	move    rd_ram,wr_host_port
        jmp     main_loop_after_data_xfer


host_wr_tf_data:
	move    rd_host_port,wr_ram
        jmp     main_loop_after_data_xfer


host_wr_tf_sdh:
	move    rd_host_port,r5
        xmit    7h,aux
        and     r5,r11
        xmit    3h,aux
        and     r5>>>3,aux
        xec     x0058,aux
        xor     r11,drive_head_sel
        xmit    0h,aux
        jmp     main_loop
x0058:  xmit    0efh,aux
        xmit    0dfh,aux
        xmit    0bfh,aux
        xmit    7fh,aux


host_wr_tf_precomp:
	xmit    precomp,ram_addr
        move    rd_host_port,wr_ram
        jmp     main_loop


host_wr_tf_cmd:  move    rd_host_port,r6
x0060:  nzt     rd2[3],x0060
        xmit    68h,ram_addr
        xmit    0h,wr_ram
        xmit    command_byte,ram_addr
        move    r6,wr_ram

; when we reenter here, ram_addr must point one past command_byte
multiple_next:
	move    r1,wr_ram
        xmit    command_byte,ram_addr
        xmit    0h,aux
        xec     cmd_table,rd_ram[6:5]

cmd_table:
	jmp     cmd_restore
        jmp     cmd_read_write
        jmp     cmd_format_track
        jmp     cmd_seek

x006d:  xmit    4h,r6
        jmp     x0070


bad_block:
	xmit    80h,r6

x0070:  xmit    command_byte,ram_addr
        xmit    2h,aux
        xor     rd_ram[6:4],aux
        move    rd_ram,r1
        nzt     aux,x0077
        xmit    90h,aux
        jmp     x0156
x0077:  xmit    10h,aux
        jmp     int_and_reset_data_pointer


cmd_seek:
	xmit    1h,r11
        jmp     seek_save_step_rate
clear_err_reg_and_reset_data_pointer:
	xmit    0h,aux

int_and_reset_data_pointer:
	nzt     int_clk,$+1

; sets data pointer back to beginning of buffer
; BUG - always sets for 512-byte buffer
reset_buffer_pointer:
	xmit    buffer_512,ram_addr
        xmit    90h,mac_control
        xmit    0ffh,waen
        jmp     main_loop


cmd_restore:
	xmit    drive_3_cylinder_high,aux
        and     r5,ram_addr
        xmit    4h,wr_ram	; set drive's current cylinder to 1024
        xmit    0h,wr_ram
        xmit    0h,r3
        xmit    0h,r4
        xmit    2h,r11	; call seek_save_step_rate, r11 specifies return loc
        jmp     seek_save_step_rate
x0089:  move    rd5[3],aux	; check track 0
        nzt     aux,clear_err_reg_and_reset_data_pointer
        xmit    2h,r6		; set error register for TR000 error
        jmp     x0077


x008d:  jmp     cmd_format_track

cmd_read_write:
	xmit    cmd_byte,ram_addr
        nzt     rd_ram[4],x008d		; write command?

x0090:  xmit    auto_restore_ok,ram_addr	; mark that no auto restore has been done
        xmit    0ffh,wr_ram

do_read_write_retry:
	xmit    3h,r11
        jmp     seek
x0094:  xmit    12h,r1
        xmit    0h,r6
x0096:  xmit    90h,mac_control
        xmit    0h,ecc_sel
        xmit    80h,mac_control
        jmp     x00a0

	org	00a0h

x00a0:  nzt     rd5[0],read_write_no_index	; check INDEX
        xmit    0h,reset_index	; clear index
        xmit    0ffh,aux
        add     r1,r1		; count down index pulses
        nzt     r1,read_write_no_index
        jmp     read_write_too_many_index

read_write_no_index:
	nzt     rd5[2],$+2	; check DRUN
        jmp     x00a0

	xmit    0feh,aux
        xmit    18h,r11
x00aa:  nzt     rd5[1],$+2	; check HFRQ
        jmp     x0096

	add     r11,r11
        nzt     r11,x00aa
        xmit    0eh,r11
        xmit    8h,mac_control
        xmit    0h,mac_control
        nzt     rd_serdes,$+1

	xmit    seek_save_regs,ram_addr	; set up to save ID field sec size, head, bad block flag
x00b3:  nzt     rd5[0],x00b5	; check INDEX
        jmp     x0096
x00b5:  nzt     rd5[1],x00b3	; check HFRQ

x00b6:  add     r11,r11
        nzt     r11,$+2
        jmp     x0096

; check ID field mark byte and cylinder high
	nzt     rd2[6],x00b6	; bdone
        xor     r4,aux
        xor     rd_serdes,aux
        nzt     aux,x0096

; check ID field cylinder low
        move    r3,aux
	nzt     rd2[6],$	; wait for bdone
        xor     rd_serdes,aux
        nzt     aux,x0096

; check ID field sector size and head number
        xmit    67h,aux
        and     r5,aux
	nzt     rd2[6],$		; wait for bdone
        xmit    40h,mac_control
        move    rd_serdes,wr_ram	; save ID field sec size, head, bad block flag
        xor     rd_serdes[6:0],aux
        nzt     aux,x0096

; check ID field sector number
        move    r2,aux
	nzt     rd2[6],$		; wait for bdone
        xor     rd_serdes,aux
        nzt     aux,x0096

        xmit    command_byte,ram_addr

; check ID field CRC first byte
	nzt     rd2[6],$	; wait for bdone
        nzt     rd_serdes,id_field_crc_error

        xmit    6h,aux		; get sector size and commmand long bit
        and     r5>>>4,aux
        xor     rd_ram[1],aux

; check ID field CRC first byte
	nzt     rd2[6],$	; wait for bdone
        nzt     rd_serdes,id_field_crc_error

        xec     buf_addr_table_1,aux	; reset buffer pointer
        jmp     x00e3


id_field_crc_error:
	xmit    0dfh,aux	; turn on 20h bit of error reg for ID CRC err
        and     r6,r6
        xmit    20h,aux
        xor     r6,r6
        jmp     x0096


buf_addr_table_1:
	xmit    3h,ram_addr	; 256-byte		300
        xmit    0feh,ram_addr	; 256-byte, long	2fc
        xmit    2h,ram_addr	; 512-byte		200
        xmit    0fdh,ram_addr	; 512-byte, long	1fc
        xmit    2h,ram_addr	; 512-byte		200
        xmit    0fdh,ram_addr	; 512-byte, long	1fc
        xmit    83h,ram_addr	; 128-byte		380
        xmit    7fh,ram_addr	; 128-byte, long	37c


x00e3:  xmit    90h,mac_control
        move    r5,ecc_sel		; bit 7 of SDH reg enables ECC
        xmit    seek_save_regs,ram_addr
        move    rd_ram[7],aux		; get bad block flag (MSB of ID field sector size/head byte)
        nzt     aux,bad_block

        xmit    command_byte,ram_addr
        nzt     rd_ram[4],x00eb		; was it a read sector command?
        jmp     read_sector

; write data address mark
x00eb:	xmit    0b0h,mac_control
	nzt     rd2[6],$		; wait for bdone
        xmit    0a1h,wr_serdes

	nzt     rd2[6],$		; wait for bdone
        xmit    0f8h,wr_serdes

; write contents of data field
; XXX where was the approprate RAM buffer address set up?
x00fa:  nzt     rd2[6],$		; wait for bdone
        move    rd_ram,wr_serdes
        nzt     rd2[7],$+2		; if RVOF, almost done writing data
        jmp     x00fa

After RVOF, one more byte to be written
	nzt     rd2[6],$		; wait for bdone
        move    rd_ram,wr_serdes

        xmit    command_byte,ram_addr
        xmit    3h,r11			; assume writing three extra zero bytes

	nzt     rd2[6],$		; wait for bdone
        nzt     rd_ram[1],x010c		; if LONG write, skip writing CRC/ECC

        xmit    0f0h,mac_control
        xmit    6h,r11			; assume writing six extra zero bytes

        xmit    0h,wr_serdes		; write first CRC/ECC byte

	nzt     rd2[6],$		; wait for bdone

        xmit    80h,aux			; ECC mode?
        and     r5,aux
        nzt     aux,$+2
        xmit    4h,r11			; yes, only write four extra zero bytes

x010c:	xmit    0h,wr_serdes		; write a zero byte (first CRC/ECC if not long mode)
        xmit    0ffh,aux

; write additional bytes, may be CRC/ECC, then some zeros
x010e:  nzt     rd2[6],$		; wait for bdone
        xmit    0h,wr_serdes
        add     r11,r11
        nzt     r11,x010e

        xmit    0ffh,write_gate		; turn off write gate

        move    rd_ram,r1
        xmit    command_byte,ram_addr
        nzt     rd_ram[2],x0117		; MULTIPLE?
        jmp     clear_err_reg_and_reset_data_pointer

x0117:  xmit    1h,aux		; increment sector
        add     r2,r2
        xmit    0ffh,aux	; decrement sector count
        add     r1,r1
        nzt     r1,$+2		; sector count is zero?
        jmp     clear_err_reg_and_reset_data_pointer	; yes, done
	jmp     multiple_next	; no, do next


read_sector:
	move    r11,ram_addr

        xmit    0f8h,aux

        xmit    50h,r11		; delay
	add     r11,r11
        nzt     r11,$-1

        xmit    88h,mac_control

        xmit    0a0h,r11	; delay
	add     r11,r11
        nzt     r11,$-1

        xmit    8h,mac_control

        xmit    18h,r11		; delay
	add     r11,r11
        nzt     r11,$-1

        xmit    78h,r11
        xmit    0h,mac_control
        nzt     rd_serdes,$+1
	jmp     x0136


x012f:  add     r11,r11
        nzt     r11,x0136
x0131:  xmit    0feh,aux
        and     r6,r6
        xmit    1h,aux
        xor     r6,r6
        jmp     x0096

x0136:  nzt     rd2[6],x012f
        xor     rd_serdes,aux
        nzt     aux,x0131

x0139:  nzt     rd2[6],$		; wait for BDONE
        move    rd_serdes,wr_ram
        nzt     rd2[7],x013d		; if ROVF, done reading sector data
        jmp     x0139

x013d:  xmit    40h,mac_control

; read last byte of data field
	nzt     rd2[6],$		; wait for bdone
        move    rd_serdes,wr_ram

; read four syndrome bytes
        xmit    0ffh,aux
        xmit    syndrome,ram_addr
        xmit    4h,r11

x0143:  nzt     rd2[6],$		; wait for bdone
        move    rd_serdes,wr_ram
        add     r11,r11
        nzt     r11,x0143

        xmit    90h,mac_control
        xmit    0h,aux

        xmit    command_byte,ram_addr	; LONG command?
        nzt     rd_ram[1],x0150

        xmit    syndrome,ram_addr
        nzt     rd_ram,x0151
        nzt     rd_ram,x0151
        nzt     rd_ram,x0151
        nzt     rd_ram,x0151
x0150:  jmp     x0154

x0151:  jmp     read_sector_ecc_error


cmd_format_track:
	xmit    68h,ram_addr
        xmit    0h,wr_ram

x0154:  xmit    80h,r11
        xor     r11,aux
x0156:  xmit    command_byte,ram_addr
        nzt     rd_ram[4:3],x0159
        nzt     int_clk,x0159
x0159:  move    rd_ram,r1
        xmit    68h,ram_addr
        xor     rd_ram,r11
        xmit    command_byte,ram_addr
        xmit    6h,aux
        and     r5>>>4,aux
        xor     rd_ram[1],aux	; merge in LONG bit form command
        xec     buf_addr_table_2,aux
        move    r11,aux
        xmit    0ffh,waen
        jmp     x0001


buf_addr_table_2:
	xmit    3h,ram_addr	; 256-byte		300
        xmit    0feh,ram_addr	; 256-byte, long	2fc
        xmit    2h,ram_addr	; 512-byte		200
        xmit    0fdh,ram_addr	; 512-byte, long	1fc
        xmit    2h,ram_addr	; 512-byte		200
        xmit    0fdh,ram_addr	; 512-byte, long	1fc
        xmit    83h,ram_addr	; 128-byte		380
        xmit    7fh,ram_addr	; 128-byte, long	37c


read_write_too_many_index:
	xmit    40h,aux		; already have data field CRC error?
        and     r6,aux
        nzt     aux,x0178	; yes, report that

        xmit    1h,aux		; already have DAM not found error?
        and     r6,aux
        nzt     aux,x0178	; yes, report that

        xmit    20h,aux		; already have ID field CRC error?
        and     r6,aux
        nzt     aux,x0178	; yes, report that

        xmit    auto_restore_ok,ram_addr      ; has auto-restore retry been done?
        nzt     rd_ram,auto_restore_retry

        xmit    10h,aux		; write 10h to error reg for ID not found
x0178:  move    aux,r6
        jmp     x0070


auto_restore_retry:
	xmit    auto_restore_ok,ram_addr	; mark that we've done auto-restore
        xmit    0h,wr_ram

        xmit    drive_3_cylinder_high,aux
        and     r5,ram_addr
        xmit    0h,wr_ram
        xmit    0h,wr_ram

        xmit    0h,r6
        xmit    4h,r11
        xmit    0ffh,aux

        xmit    0ffh,direction
x0184:  nzt     rd5[3],x_do_read_write_retry	; if track 0, now retry read/write command
        xmit    0h,step		; set step

        xmit    9h,r1		; delay
	add     r1,r1
        nzt     r1,$-1

        xmit    0ffh,step	; clear step

        xmit    8h,r1		; delay
	add     r1,r1
        nzt     r1,$-1

x018d:  nzt     rd5[4],x0190	; test seek complete
        jmp     x018d


x_do_read_write_retry:
	jmp     do_read_write_retry


x0190:  add     r6,r6
        nzt     r6,x0184
        add     r11,r11
        nzt     r11,x0184
        xmit    2h,r6
        jmp     x0070


format_track:
	xmit    4h,r11
        jmp     seek
x0198:  xmit    6h,aux
        and     r5>>>4,aux
        xec     buf_addr_table_2,aux
        xmit    0b8h,mac_control
        xmit    0h,reset_index
        xmit    0h,write_gate
x019e:  nzt     rd5[0],x019e
x019f:  xmit    0h,ecc_sel
        xmit    1h,aux
        add     r5>>>5,r11
        and     r11>>>1,aux
        xmit    1eh,r11
        nzt     aux,x01a6
        xmit    0fh,r11
x01a6:  xmit    0ffh,aux
x01a7:  nzt     rd2[6],x01a7
        xmit    4eh,wr_serdes
        add     r11,r11
        nzt     r11,x01a7
        xmit    0eh,r11
        xmit    0b8h,mac_control
x01ad:  nzt     rd2[6],x01ad
        xmit    0h,wr_serdes
        add     r11,r11
        nzt     r11,x01ad
        xmit    0b0h,mac_control
x01b2:  nzt     rd2[6],x01b2
        xmit    0a1h,wr_serdes
        xmit    0feh,aux
x01b5:  nzt     rd2[6],x01b5
        xor     r4,wr_serdes
x01b7:  nzt     rd2[6],x01b7
        move    r3,wr_serdes
        xmit    67h,aux
        and     r5,aux
        move    rd_ram,r6
x01bc:  nzt     rd2[6],x01bc
        xor     r6,wr_serdes
        xmit    4h,r11
        xmit    0ffh,aux
x01c0:  nzt     rd2[6],x01c0
        move    rd_ram,wr_serdes
x01c2:  nzt     rd2[6],x01c2
        xmit    0f0h,mac_control
x01c4:  nzt     rd2[6],x01c4
        xmit    0h,wr_serdes
        add     r11,r11
        nzt     r11,x01c4
        nzt     r6,x01ef
        xmit    0b8h,mac_control
        move    r5,ecc_sel
        xmit    0dh,r11
x01cc:  nzt     rd2[6],x01cc
        xmit    0h,wr_serdes
        add     r11,r11
        nzt     r11,x01cc
        xmit    0b0h,mac_control
x01d1:  nzt     rd2[6],x01d1
        xmit    0a1h,wr_serdes
        xmit    0h,reset_index
        xmit    3h,aux
        and     r5>>>5,aux
x01d6:  nzt     rd2[6],x01d6
        xmit    0f8h,wr_serdes
        xec     x01f5,aux
        xmit    0ffh,aux
x01da:  nzt     rd2[6],x01da
        xmit    0h,wr_serdes
x01dc:  nzt     rd2[6],x01dc
        xmit    0h,wr_serdes
        add     r11,r11
        nzt     r11,x01da
        xmit    6h,r11
x01e1:  nzt     rd2[6],x01e1
        xmit    0f0h,mac_control
        xmit    0h,wr_serdes
        xmit    80h,aux
        and     r5,aux
x01e6:  nzt     rd2[6],x01e6
        xmit    0h,wr_serdes
        nzt     aux,x01ea
        xmit    4h,r11
x01ea:  xmit    0ffh,aux
x01eb:  nzt     rd2[6],x01eb
        xmit    0h,wr_serdes
        add     r11,r11
        nzt     r11,x01eb
x01ef:  add     r1,r1
        nzt     r1,x019f
        xmit    4eh,wr_serdes
x01f2:  nzt     rd5[0],x01f2
        xmit    0ffh,write_gate
        jmp     clear_err_reg_and_reset_data_pointer
x01f5:  xmit    80h,r11
        xmit    0h,r11
        xmit    0h,r11
        xmit    40h,r11


read_sector_ecc_error:
	xmit    80h,aux		; ECC mode set in SDH register?
        and     r5,aux
        nzt     aux,correct_read_data	; yes, try to correct

        xmit    40h,r6		; no, set data CRC/ECC err bit in error reg
        jmp     x0096


correct_read_data:
; save r1..r4
	xmit    seek_save_regs,ram_addr
        move    r1,wr_ram
        move    r2,wr_ram
        move    r3,wr_ram
        move    r4,wr_ram

        xmit    70h,ram_addr
        xmit    3h,aux
        and     r5>>>5,aux
        xmit    7h,wr_ram
        xec     x021c,aux

; get syndrome into r1..r4
        xmit    syndrome,ram_addr
        move    rd_ram,r1
        move    rd_ram,r2
        move    rd_ram,r3
        move    rd_ram,r4

; shift an entire byte at a type until we have a non-zero byte
; of the syndrome
        xmit    0h,r11
x020e:  nzt     r1,x0220

        xmit    70h,ram_addr
        xmit    8h,aux
        add     rd_ram,aux
        move    rd_ram,r6

        xmit    70h,ram_addr
        move    aux,wr_ram
        move    ovf,aux
        add     r6,wr_ram

        move    r2,r1
        move    r3,r2
        move    r4,r3
        xmit    0h,r4
        jmp     x020e


x021c:  xmit    8h,wr_ram
        xmit    10h,wr_ram
        xmit    10h,wr_ram
        xmit    4h,wr_ram


; rotate register by one bit
x0220:  xmit    0b0h,ram_addr
        xmit    80h,aux
        and     r1>>>1,wr_ram
        and     r2>>>1,wr_ram
        and     r3>>>1,wr_ram
        and     r4>>>1,wr_ram

        xmit    7fh,aux
        and     r1>>>1,r1
        and     r2>>>1,r2
        and     r3>>>1,r3
        and     r4>>>1,r4

        xmit    0b0h,ram_addr
        move    rd_ram,aux
        xor     r2,r2
        move    rd_ram,aux
        xor     r3,r3
        move    rd_ram,aux
        xor     r4,r4
        xmit    80h,aux
        xor     rd_ram,aux

        nzt     aux,x023d

; xor in the polynomial
        xmit    22h,aux
        xor     r4,r4
        xmit    2h,aux
        xor     r3,r3
        xmit    5h,aux
        xor     r2,r2
        xmit    8ah,aux
        xor     r1,r1


x023d:  nzt     r1,x0249
        nzt     r11,x0245
        nzt     r3,x0249
        nzt     r4,x0249
        xmit    7h,aux
        and     r2,aux
        nzt     aux,x0249
        xmit    0ffh,r11

; check position count
x0245:  xmit    70h,ram_addr
        move    rd_ram[2:0],aux
        nzt     aux,x024d
        jmp     x0257

; is position count zero
x0249:  xmit    70h,ram_addr
        nzt     rd_ram,x024d
        nzt     rd_ram,x024d
        jmp     ecc_correction_failed	; yes

; position count is still non-zero
; decrement position count and try again
x024d:  xmit    70h,ram_addr
        xmit    0ffh,aux
        add     rd_ram,aux
        move    rd_ram,r6
        xmit    70h,ram_addr
        move    aux,wr_ram
        xmit    0ffh,aux
        add     ovf,aux
        add     r6,wr_ram
        jmp     x0220


x0257:  xmit    3h,aux
        and     r5>>>5,aux
        xec     x025b,aux
        jmp     x0264


x025b:  nzt     rd_ram[3],x025f
        nzt     rd_ram[4],x025f
        nzt     rd_ram[4],x025f
        nzt     rd_ram[2],x025f


; ECC correction successful
x025f:  xmit    68h,ram_addr
        xmit    0h,r6		; clear error
        xmit    40h,wr_ram
        xmit    0h,aux
        jmp     x0282


x0264:  xmit    70h,ram_addr
        xec     x027d,aux
        xor     rd_ram[7:5],aux
        xor     rd_ram[12:5],r1
        move    r1>>>6,r1
        xmit    70h,ram_addr
        move    rd_ram[4:3],r4

        xmit    5h,r11
        jmp     ecc_subroutine
x026d:

	move    rd_ram,aux
        xor     r2,r2
        move    rd_ram,aux
        xor     r3,r3

        xmit    6h,r11
        jmp     ecc_subroutine
x0273:

	move    r2,wr_ram
        xmit    0ffh,aux
        xor     r1,aux
        nzt     aux,x027b
        xmit    3h,aux
        xor     r4,aux
        nzt     aux,x027b
        jmp     x025f

x027b:  move    r3,wr_ram
        jmp     x025f


x027d:  xmit    0c0h,aux
        xmit    80h,aux
        xmit    80h,aux
        xmit    0e0h,aux


ecc_correction_failed:
	xmit    40h,r6		; uncorrectable, set data field ECC error

x0282:
; restore r1..r4
	xmit    seek_save_regs,ram_addr
        move    rd_ram,r1
        move    rd_ram,r2
        move    rd_ram,r3
        move    rd_ram,r4

        nzt     r6,x0289
        jmp     x0154
x0289:  jmp     x0096


; on entry here, r6 contains the command byte
seek_save_step_rate:
	xmit    step_rate,ram_addr
        move    r6,wr_ram

seek:	xmit    80h,wr_host_port	; set status = busy
        xmit    0h,waen
        xmit    5h,aux
        xor     rd5[6:4],aux
        nzt     aux,x02ca

        xmit    seek_save_regs,ram_addr
        move    r2,wr_ram
        move    r1,wr_ram
        move    r5,wr_ram

        xmit    drive_3_cylinder_high,aux	; get drive's current cylinder in r2 (high), r1 (low)
        and     r5,ram_addr
        move    rd_ram,r2
        move    rd_ram,r1

        and     r5,ram_addr	; save requested seek cylinder as drive's current cylinder
        move    r4,wr_ram
        move    r3,wr_ram

        and     r5,ram_addr
        move    rd_ram[9:2],aux
        xor     rd_ram[7:2],r6
        xmit    0ffh,aux
        xor     r6,aux

        xmit    precomp,ram_addr
        add     rd_ram,aux
        move    ovf>>>1,precomp_en
        move    ovf>>>1,rwc

        xmit    0h,r6
x02a6:  xmit    0ffh,aux
        xor     r1,r1
        xor     r2,r2
        xmit    1h,aux
        add     r1,r1
        move    ovf,aux
        add     r2,r2
        nzt     r6,x02b8
        move    r3,aux
        add     r1,r1
        move    ovf,aux
        add     r4,aux
        add     r2,r2
        move    r2,direction
        xmit    80h,aux
        and     r2,r5
        xmit    0ffh,r6
        nzt     r5,x02a6
x02b8:  nzt     r1,x02d2
        nzt     r2,x02d2

x02ba:
; restore saved task file registers
	xmit    seek_save_regs,ram_addr
        move    rd_ram,r2
        move    rd_ram,r1
        move    rd_ram,r5

; was the command a seek
        xmit    command_byte,ram_addr
        xmit    7h,aux
        xor     rd_ram[6:4],r6
        nzt     r6,$+2
        jmp     x02cb

; not a seek command
	xmit    80h,r6
        xmit    0ffh,aux
x02c5:  xmit    0h,reset_index

	nzt     rd5[4],x02cb
        nzt     rd5[0],$-1	; check index

        add     r6,r6
        nzt     r6,x02c5
x02ca:  jmp     x006d


; command was seek
x02cb:  xmit    2h,aux
        xor     rd5[6:5],aux
        nzt     aux,x02ca
        jmp     subroutine_return

x02cf:  jmp     x02ba
x02d0:  nzt     rd5[3],x02cf
        jmp     x02d3
x02d2:  nzt     r5,x02d0
x02d3:  xmit    0ffh,aux
        add     r1,r1
        add     ovf,aux
        add     r2,r2

; save registers for actual stepping sequence
        xmit    seek_save_regs_2,ram_addr
        move    r2,wr_ram
        move    r3,wr_ram
        move    r4,wr_ram

        xmit    step_rate,ram_addr
        move    rd_ram[3:0],r2

        xmit    0h,step		; turn on step bit
        xmit    0ffh,aux

        xmit    20h,r4		; delay
	add     r4,r4
        nzt     r4,$-1

        xmit    0ffh,step	; turn off setp bit

        xmit    16h,r4		; delay
	add     r4,r4
        nzt     r4,$-1

x02e6:  nzt     r2,$+2		; pulse count = 0?
        jmp     step_pulses_done

	add     r2,r2
        xmit    4h,r4

x02ea:  xmit    0f8h,r3		; delay
x02eb:  add     r3,r3
        nzt     r3,x02eb
        add     r4,r4
        nzt     r4,x02ea
        jmp     x02e6


step_pulses_done:
; restore registers used in stepping sequence
	xmit    seek_save_regs_2,ram_addr
        move    rd_ram,r2
        move    rd_ram,r3
        move    rd_ram,r4
        jmp     x02b8


ecc_subroutine:
	move    r1,ram_addr
        move    r4,r6
        xmit    0ffh,aux
x02f8:  nzt     r6,$+2
        jmp     subroutine_return

	nzt     rd_ram,$+1
	add     r6,r6
        jmp     x02f8


        jmp     subroutine_return	; XXX dead code!


	org	0300h

; subroutine return based on value in r11
subroutine_return:
	xec     x0300,r11

; return values 1..4 are used for seek subroutine
        jmp     clear_err_reg_and_reset_data_pointer	; 1
        jmp     x0089	; 2
        jmp     x0094	; 3
        jmp     x0198	; 4

; return values 5..6 are used for ECC subroutine
        jmp     x026d	; 5
        jmp     x0273	; 6
