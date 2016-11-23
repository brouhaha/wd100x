; WD1000 hard disk controller firmware reverse-engineered source code
; 512-word version

; Assembly source code copyright 2016 Eric Smith <spacewar@gmail.com>

; No copyright is claimed on the executable object code as
; found in the WD1000 PROM chips.

; This program is free software: you can redistribute it and/or modify
; it under the terms of version 3 of the GNU General Public License
; as published by the Free Software Foundation.

; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
; GNU General Public License for more details.

; You should have received a copy of the GNU General Public License
; along with this program.  If not, see <http://www.gnu.org/licenses/>.


; The assembler syntax used herein does not match any existing 8X300
; assembler, including Signetics MCCAP.	 This assembly source code
; has not been assembled for verification against the actual WD1000
; PROM chips.


; WD1000 PROMs (512x8):
;    U41 800000-036A most significant byte
;    U51 800000-035A least significant byte
;    U28 800000-037A fast I/O select

; This firmware is hard-coded for a single sector size; changing
; the sector size required installing different firmware.


; Fast I/O select ports
; Note that the normal 8X300 port addressing scheme is not used;
; writing to the ivl and ivr address registers writes to the port
; selected by the fast I/O select PROM.

rd_ram		riv	rr=0
drq_clk		liv	rr=1
rd2		liv	rr=2
int_clk		liv	rr=3
rd_serdes	liv	rr=4
rd5		liv	rr=5
rd_host_port	liv	rr=6

wr_ram		riv	wr=0
drive_ctl	liv	wr=1
ram_addr_low	liv	wr=2
reset_index	liv	wr=3
wr_serdes	liv	wr=4
drive_head_sel	liv	wr=5
wr_host_port	liv	wr=6
mac_control	liv	wr=7


; RAM definitions
; Addresses are from the 8X300 point of view, though the hardware
; uses inverted addresses.

; controller tracks current cylinder for each drive
drive_0_cylinder_high	equ	100h
drive_0_cylinder_low	equ	101h
drive_1_cylinder_high	equ	108h
drive_1_cylinder_low	equ	109h
drive_2_cylinder_high	equ	110h
drive_2_cylinder_low	equ	111h
drive_3_cylinder_high	equ	118h
drive_3_cylinder_low	equ	119h

seek_temp_1		equ	1e0h
seek_temp_2		equ	1e1h
seek_temp_3		equ	1e2h

seek_save_sector	equ	1e7h
seek_save_sector_count	equ	1e8h
seek_save_sdh		equ	1e9h

command_byte		equ	1efh
saved_sector_count	equ	1f0h
id_field_s_h_bb		equ	1f1h

auto_restore_ok		equ	1f5h	; 0ffh if auto restore not done yet, 0 if it has
precomp			equ	1f6h
step_rate		equ	1f7h	; step rate used by all drives
unk_1f8			equ	1f8h	; unkown, reset initializes to 20h

data_buffer		equ	300h	; for 256 byte sectors
					; use 380h for 128 byte sectors
					; use 200h for 512 byte sectors

	org	0

	jmp	reset

; main loop entry after host transfers a data byte to/from task file
main_loop_after_data_xfer:
	nzt	rd2[7],data_xfer_done	; if ROVF, data xfer is done

; main loop entry to set DRQ
main_loop_set_drq:
	nzt	drq_clk,main_loop	; set DRQ, read data ignored

; main loop to wait for the host to access a task file register
main_loop:
	nzt	rd2[4],main_loop	; loop until CSAC
	xec	task_file_access,rd2[3:0]	; dispatch on /HRW, /HA2../HA0
	jmp	main_loop		

task_file_access:
	; host reads task file:
	jmp	host_read_tf_status	; tf7: status
	move	r5,wr_host_port		; tf6: sdh
	move	r4,wr_host_port		; tf5: cyl_hi
	move	r3,wr_host_port		; tf4: cyl_lo
	move	r2,wr_host_port		; tf3: sector
	move	r1,wr_host_port		; tf2: sector count (format cmd only)
	move	r6,wr_host_port		; tf1: error
	jmp	host_read_tf_data	; tf0: data

	; host writes task file:
	jmp	host_wr_tf_cmd		; tf7: cmd
	jmp	host_wr_tf_sdh		; tf6: sdh
	move	rd_host_port,r4		; tf5: cyl_hi
	move	rd_host_port,r3		; tf4: cyl_lo
	move	rd_host_port,r2		; tf3: sector
	move	rd_host_port,r1		; tf2: sector count (format cmd only)
	jmp	host_wr_tf_precomp	; tf1: precomp
	jmp	host_wr_tf_data		; tf0: data


data_xfer_done:
	xmit	95h,mac_control
	move	aux,r11
	xmit	command_byte & 0ffh,ram_addr_low

	xmit	5h,aux			; was it a format track command?
	xor	rd_ram[6:4],aux
	nzt	aux,$+2
	jmp	format_track

	xmit	command_byte & 0ffh,ram_addr_low
	move	rd_ram[4],aux		; was it a read sector command?
	nzt	aux,x0080		; no, so perform command

	; was a read command, so it's now done
	xmit	command_byte & 0ffh,ram_addr_low
	xmit	10h,aux
	and	r11,aux
	nzt	rd_ram[4:3],$+2		; check DMA mode bit
	jmp	reset_buffer_pointer	; programmed I/O, so no int
	jmp	int_and_reset_data_pointer	; DMA done, so int


reset:	xmit	95h,mac_control
	xmit	77h,drive_head_sel
	xmit	0fh,drive_control

; clear RAM from 100h to 3ffh
	xmit	0h,ram_addr_low
x002a:	xmit	0h,wr_ram
	nzt	rd2[7],$+2	; RVOF?
	jmp	x002a

	xmit	95h,mac_control
	xmit	step_rate & 0ffh,ram_addr_low
	xmit	0fh,wr_ram		; default step rate
	xmit	20h,wr_ram		; unknown

	xmit	1h,r1	; initial sector count
	xmit	0h,r2	; initial sector
	xmit	0h,r3	; initial cylinder low
	xmit	0h,r4	; initial cylinder high
	xmit	0h,r5	; initial size/drive/head

clear_err_reg_and_reset_data_pointer:
	xmit	0h,r6
	xmit	0h,aux
	jmp	reset_buffer_pointer


host_read_tf_status:
	xor	rd5[6:4],r11	; get read, write fault, seek complete bits
	move	r11>>>4,r11
	move	r11,wr_host_port
	jmp	main_loop


host_read_tf_data:
	move	rd_ram,wr_host_port
	jmp	main_loop_after_data_xfer


host_wr_tf_data:
	move	rd_host_port,wr_ram
	jmp	main_loop_after_data_xfer


host_wr_tf_sdh:
	move	rd_host_port,r5

	xmit	7h,aux		; get head select bits of SDH
	and	r5,r11

	xmit	3h,aux		; get drive select bits of SDH
	and	r5>>>3,aux
	xec	drive_sel_table,aux	; translate to bit position
	xor	r11,drive_head_sel	; set drive and head select

	xmit	0h,aux
	jmp	main_loop

; table of drive_had_sel register values for drive n, head 7
drive_sel_table:
	xmit	77h,aux
	xmit	6fh,aux
	xmit	5fh,aux
	xmit	3fh,aux


host_wr_tf_precomp:
	xmit	95h,mac_control
	xmit	precomp & 0ffh,ram_addr_low
	move	rd_host_port,wr_ram
	jmp	main_loop


host_wr_tf_cmd:
	move	rd_host_port,r6
	nzt	rd2[3],$

	xmit	95h,mac_control		; save command in RAM
	xmit	command_byte & 0ffh,ram_addr_low
	move	r6,wr_ram

	move	r1,wr_ram		; save sector count in RAM

	xmit	command_byte & 0ffh,ram_addr_low

	xec	cmd_table,rd_ram[6:5]	; dispatch command via table

cmd_table:
	jmp	cmd_restore
	jmp	cmd_read_write
	jmp	cmd_format_track
	jmp	cmd_seek


x005e:	xmit	4h,r6
	jmp	x0061



bad_block:
	xmit	80h,r6		; set bad block detect error

x0061:	xmit	command_byte & 0ffh,ram_addr_low
	xmit	2h,aux
	xor	rd_ram[6:4],aux
	move	rd_ram,r1
	nzt	aux,x0068
	xmit	90h,aux
	jmp	x0117

x0068:	xmit	10h,aux
	jmp	int_and_reset_data_pointer


cmd_seek:
	xmit	1h,r11	; call seek_save_step_rate, r11 specifies return loc
	jmp	seek_save_step_rate
x006c:	xmit	0h,aux

int_and_reset_data_pointer:
	nzt	int_clk,$+1	; set interrupt

; sets data pointer back to beginning of buffer
reset_buffer_pointer:
	xmit	0h,ram_addr_low
	xmit	97h,mac_control	; 256-byte
	jmp	main_loop


cmd_restore:
	xmit	drive_3_cylinder_high & 0ffh,aux
	and	r5,ram_addr_low
	xmit	4h,wr_ram	; set drive's current cylinder to 1024
	xmit	0h,wr_ram
	xmit	0h,r3
	xmit	0h,r4
	xmit	2h,r11		; call seek_save_step_rate, r11 specifies return loc
	jmp	seek_save_step_rate
x0079:	move	rd5[3],aux	; check track 0
	nzt	aux,x006c
	xmit	2h,r6		; set error register for TR000 error
	jmp	x0068


x007d:	jmp	cmd_read_write

cmd_read_write:
	xmit	command_byte & 0ffh,ram_addr_low
	nzt	rd_ram[4],x007d		; write command?

x0080:	xmit	auto_restore_ok & 0ffh,ram_addr_low	; mark that no auto restore has been done
	xmit	0ffh,wr_ram

do_read_write_retry:
	xmit	3h,r11		; call seek, r11 specifies return loc
	jmp	seek
x0084:	xmit	18*2,r1		; max 18 index pulses
	xmit	0h,r6		; no error
x0086:	xmit	91h,mac_control
	xmit	81h,mac_control
	xmit	0feh,aux	; ID mark byte for cyl 0-255, also used for counter

x0089:	nzt	rd5[0],read_write_no_index	; check INDEX
	xmit	0h,reset_index	; clear index
	add	r1,r1		; count down index pulses
	nzt	r1,read_write_no_index
	jmp	read_write_too_many_index

read_write_no_index:
	nzt	rd5[2],$+2	; check DRUN
	jmp	x0089
	
	xmit	18h,r11
x0091:	nzt	rd5[1],$+2	; check HFRQ
	jmp	x0086

	add	r11,r11
	nzt	r11,x0091
	xmit	0eh,r11
	xmit	09h,mac_control
	nzt	rd_serdes,$+1

	xmit	id_field_s_h_bb & 0ffh,ram_addr_low	; set up to save ID field sec size, head,bad block flag

	nzt	rd5[1],$		; wait for HFRQ
	xmit	01h,mac_control
x009b:	add	r11,r11
	nzt	r11,$+2
	jmp	x0086

; check ID field mark byte and cylinder high
	nzt	rd2[6],x009b		; bdone
	xor	r4,aux
	xor	rd_serdes,aux
	nzt	aux,x0086

; check ID field cylinder low
	move	r3,aux
	nzt	rd2[6],$		; wait for bdone
	xor	rd_serdes,aux
	nzt	aux,x0086

; check ID field sector size and head number
	xmit	67h,aux
	and	r5,aux
	nzt	rd2[6],$		; wait for bdone
	move	rd_serdes,wr_ram	; save ID field sec size, head, bad block flag
	xor	rd_serdes[6:0],aux
	nzt	aux,x0086

; check ID field sector number
	move	r2,aux
	nzt	rd2[6],$		; wait for bdone
	xor	rd_serdes,aux
	nzt	aux,x0086

	xmit	drive_3_cylinder_high & 0ffh,aux	; point to drive's current cyl
	and	r5,ram_addr_low

	nzt	rd2[6],$		; wait for bdone
	nzt	rd_serdes,$+1
	move	rd_ram[9:2],aux
	xor	rd_ram[7:2],r11

	nzt	rd2[6],$		; wait for bdone
	nzt	rd_serdes,$+1
	xmit	0ffh,aux
	xor	r11,aux
	xmit	precomp & 0ffh,ram_addr_low

	nzt	rd2[6],$		; wait for bdone
	xmit	91h,mac_control
	jmp	x00c0


	nop	 // rd=0	; unused
	nop	 // rd=0	; unused


x00c0:	nzt	rd2[5],id_field_crc_error	; check CRCOK
	add	rd_ram,aux
	xmit	id_field_s_h_bb & 0ffh,ram_addr_low
	move	rd_ram[7],aux		; get bad block flag (MSB of ID field sector size/head byte)
	nzt	aux,bad_block

	xmit	command_byte & 0ffh,ram_addr_low
	nzt	rd_ram[4],write_sector	; cmd bit 4 distinguishes read/write
	jmp	read_sector


id_field_crc_error:
	xmit	0dfh,aux	; turn on 20h bit of error reg for ID CRC err
	and	r6,r6
	xmit	20h,aux
	xor	r6,r6
	jmp	x0086


write_sector:
	xmit	0ch,aux
	xor	ovf<<<1,aux		; control RWC (bit 1)
	xmit	0h,wr_serdes
	xmit	0bbh,mac_control
	move	aux,drive_control

; write ten bytes of 00h
	xmit	0ffh,aux
	xmit	0ah,r11
x00d4:	nzt	rd2[6],$		; wait for bdone
	xmit	0h,wr_serdes
	add	r11,r11
	nzt	r11,x00d4

; write data address mark
	xmit	0b3h,mac_control	; change to 0b2h for 512-byte sect
	nzt	rd2[6],$		; wait for bdone
	xmit	0a1h,wr_serdes

	nzt	rd2[6],$		; wait for bdone
	xmit	0f8h,wr_serdes

	xmit	0h,ram_addr_low		; change to 80h for 128-byte sect
	jmp	x00e0


	nop	 // rd=0	; unused


; write data content of data field
x00e0:	nzt	rd2[7],x00e4		; if RVOF, done writing data
	nzt	rd2[6],$		; wait for bdone
	move	rd_ram,wr_serdes
	jmp	x00e0

x00e4:	nzt	rd2[6],$		; wait for bdone
	xmit	0h,wr_serdes
	xmit	0f1h,mac_control
	xmit	5h,r11
x00e8:	nzt	rd2[6],$		; wait for bdone
	xmit	0h,wr_serdes
	add	r11,r11
	nzt	r11,x00e8
	xmit	0fh,drive_control

	xmit	saved_sector_count & 0ffh,ram_addr_low	; restore count from RAM
	move	rd_ram,r1

	jmp	x006c


read_sector:
	xmit	0f8h,aux

	xmit	50h,r11		; delay
	add	r11,r11
	nzt	r11,$-1

	xmit	8bh,mac_control

	xmit	0a0h,r11
	add	r11,r11
	nzt	r11,$-1

	xmit	0bh,mac_control

	xmit	18h,r11			; delay
	add	r11,r11
	nzt	r11,$-1

	xmit	78h,r11
	xmit	3h,mac_control	; change to 02h for 512-byte sectors?
	nzt	rd_serdes,$+1
	jmp	x0107


x0100:	add	r11,r11
	nzt	r11,x0107

x0102:	xmit	0feh,aux	; turn on 01h bit in status reg for DAM not found
	and	r6,r6
	xmit	1h,aux
	xor	r6,r6
	jmp	x0086

x0107:	nzt	rd2[6],x0100		; bdone
	xor	rd_serdes,aux
	nzt	aux,x0102
	xmit	0h,ram_addr_low		; change to 80h for 128-byte sectors

read_sector_data:
	nzt	rd2[7],x010f		; if RVOF, done reading sector data
	nzt	rd2[6],$		; wait for bdone
	move	rd_serdes,wr_ram
	jmp	read_sector_data

x010f:	nzt	rd2[6],$		; wait for bdone
	nzt	rd_serdes,$+1

	nzt	rd2[6],$		; wait for bdone
	nzt	rd_serdes,$+1

	nzt	rd2[6],$		; wait for bdone
	nzt	rd2[5],read_sector_crc_error	; test crc_ok
; fall through to generate interrupt and DRQ to host

cmd_format_track:
	xmit	95h,mac_control
	xmit	80h,aux
x0117:	xmit	command_byte & 0ffh,ram_addr_low
	nzt	rd_ram[4:3],$+2
	nzt	int_clk,$+1
	move	rd_ram,r1
	xmit	97h,mac_control
	xmit	0h,ram_addr_low
	jmp	main_loop_set_drq


read_sector_crc_error:
	xmit	0bfh,aux	; turn on 40h bit in error reg for data CRC err
	and	r6,r6
	xmit	40h,aux
	xor	r6,r6
	jmp	x0086


read_write_too_many_index:
	xmit	40h,aux		; already have data field CRC error?
	and	r6,aux
	nzt	aux,x012f	; yes, report that

	xmit	1h,aux		; already have DAM not found error?
	and	r6,aux
	nzt	aux,x012f	; yes, report that

	xmit	20h,aux		; already have ID field CRC error?
	and	r6,aux
	nzt	aux,x012f	; yes, report that

	xmit	auto_restore_ok & 0ffh,ram_addr_low ; has auto-restore retry been done?
	nzt	rd_ram,auto_restore_retry

	xmit	10h,aux		; write 10h to error reg for ID not found
x012f:	move	aux,r6
	jmp	x0061


x_do_read_write_retry:
	jmp	do_read_write_retry


auto_restore_retry:
	xmit	auto_restore_ok & 0ffh,ram_addr_low	; mark that we've done an auto-restore
	xmit	0h,wr_ram

	xmit	drive_3_cyl_high & 0ffh,aux
	and	r5,ram_addr_low
	xmit	0h,wr_ram
	xmit	0h,wr_ram
	xmit	0fh,drive_control	; set dir inward, step not active

x0139:	nzt	rd5[3],x_do_read_write_retry	; if track 0, now retry read/write command

	xmit	0bh,drive_control	; set dir inward, set step

	xmit	28h,r1
	add	r1,r1
	nzt	r1,$-1

	xmit	0fh,drive_control	; set dir inward, clear step
x013f:	nzt	rd5[4],x0139		; test seek complete
	jmp	x013f


format_track:
	xmit	4h,r11		; call seek, r11 specifies return loc
	jmp	seek
x0143:	xmit	drive_3_cylinder_high & 0ffh,aux
	and	r5,ram_addr_low
	move	rd_ram[9:2],aux
	xor	rd_ram[7:2],r11
	xmit	0ffh,aux
	xor	r11,aux
	xmit	precomp & 0ffh,ram_addr_low
	add	rd_ram,aux
	xmit	0ch,aux
	xor	ovf<<<1,aux
	xmit	0bbh,mac_control
	xmit	0h,reset_index
	xmit	0h,ram_addr_low
	move	aux,drive_control

	nzt	rd5[0],$		; wait for index

format_sector:
; write gap 3, 15 bytes of 4e
	xmit	0ffh,aux
	xmit	0fh,r11
x0154:	nzt	rd2[6],$		; wait for bdone
	xmit	4eh,wr_serdes
	add	r11,r11
	nzt	r11,x0154

; write 14 bvtes of 00
	xmit	0eh,r11
	xmit	0bbh,mac_control
x015a:	nzt	rd2[6],$		; wait for bdone
	xmit	0h,wr_serdes
	add	r11,r11
	nzt	r11,x015a

	xmit	0b3h,mac_control
	nzt	rd2[6],$		; wait for bdone

	xmit	0a1h,wr_serdes
	xmit	0feh,aux
	nzt	rd2[6],$		; wait for bdone

	xor	r4,wr_serdes
	nzt	rd2[6],$		; wait for bdone
	move	r3,wr_serdes

	xmit	67h,aux
	and	r5,aux
	nzt	rd2[6],$		; wait for bdone
	xor	rd_ram,wr_serdes

	xmit	4h,r11
	xmit	0ffh,aux
	nzt	rd2[6],$		; wait for bdone

	move	rd_ram,wr_serdes
	nzt	rd2[6],$		; wait for bdone

; write 4 bytes of zeros after ID field
	xmit	0f3h,mac_control
x0170:	nzt	rd2[6],$		; wait for bdone
	xmit	0h,wr_serdes
	add	r11,r11
	nzt	r11,x0170
	xmit	0b3h,mac_control

; write 13 bytes of zeros before data field
	xmit	0dh,r11
x0176:	nzt	rd2[6],$		; wait for bdone
	xmit	0h,wr_serdes
	add	r11,r11
	nzt	r11,x0176

	xmit	0bbh,mac_control	; pulse CRC initialization
	xmit	0b3h,mac_control

; write Data AM
	nzt	rd2[6],$		; wait for bdone
	xmit	0a1h,wr_serdes
	xmit	0h,reset_index

	nzt	rd2[6],$		; wait for bdone
	xmit	0f8h,wr_serdes
	xmit	80h,r11

fmt_write_sector_data:
	nzt	rd2[6],$		; wait for bdone
	xmit	0h,wr_serdes

	nzt	rd2[6],$		; wait for bdone
	xmit	0h,wr_serdes

	add	r11,r11
	nzt	r11,fmt_write_sector_data

; write two bytes of CRC, 3 bytes of zeros
	xmit	5h,r11
	nzt	rd2[6],$		; wait for bdone
	xmit	0f3h,mac_control
x018b:	nzt	rd2[6],$		; wait for bdone
	xmit	0h,wr_serdes
	add	r11,r11
	nzt	r11,x018b
	
	add	r1,r1			; more sectors to format?
	nzt	r1,format_sector

; write gap 4, 4E repeats until index
	xmit	4eh,wr_serdes
	nzt	rd5[0],$		; wait for index
	xmit	0fh,drive_control
	jmp	clear_err_reg_and_reset_data_pointer


	nop	 // rd=0


; on entry here, r6 contains the command byte
seek_save_step_rate:
	xmit	step_rate & 0ffh,ram_addr_low
	move	r6,wr_ram

seek:	xmit	80h,wr_host_port	; set status = busy
	xmit	91h,mac_control
	xmit	5h,aux
	xor	rd5[6:4],aux
	nzt	aux,x01fa

; save task file registers for scratch use
	xmit	seek_save_sector,ram_addr_low
	move	r2,wr_ram	; save sector #
	move	r1,wr_ram	; save sector count
	move	r5,wr_ram	; save s/d/h

	xmit	drive_3_cylinder_high,aux	; get drive's current cylinder in r2 (high), r1 (low)
	and	r5,ram_addr_low
	move	rd_ram,r2
	move	rd_ram,r1

	and	r5,ram_addr_low	; save requested seek cylinder as drive's current cylinder
	move	r4,wr_ram
	move	r3,wr_ram

	xmit	0h,r6
x01a9:	xmit	0ffh,aux
	xor	r1,r1
	xor	r2,r2
	xmit	1h,aux
	add	r1,r1
	move	ovf,aux
	add	r2,r2
	nzt	r6,x01bd
	move	r3,aux
	add	r1,r1
	move	ovf,aux
	add	r4,aux
	add	r2,r2
	xmit	8h,aux
	and	r2,aux
	xmit	7h,r5
	xor	r5,r5
	move	r5,drive_control
	xmit	1h,r6
	nzt	aux,x01a9
x01bd:	nzt	r1,x01d7
	nzt	r2,x01d7

x01bf:
; restore saved task file registers
	xmit	seek_save_sector & 0ffh,ram_addr_low
	move	rd_ram,r2
	move	rd_ram,r1
	move	rd_ram,r5

; was the command a seek?
	xmit	command_byte & 0ffh,ram_addr_low
	xmit	7h,aux
	xor	rd_ram[6:4],r6
	nzt	r6,$+2
	jmp	x01d0

; not a seek command
	xmit	80h,r6
	xmit	0ffh,aux
x01ca:	xmit	0h,reset_index

	nzt	rd5[4],x01d0	; check seek complete
	nzt	rd5[0],$-1	; check index

	add	r6,r6
	nzt	r6,x01ca
	jmp	x005e


; command was seek
x01d0:	xmit	2h,aux
	xor	rd5[6:5],aux
	nzt	aux,x01fa
	jmp	seek_return


	jmp	x01bf

x01d5:	nzt	rd5[3],$-1
	jmp	x01da

x01d7:	xmit	8h,aux
	and	r5,aux
	nzt	aux,x01d5
x01da:	xmit	0ffh,aux
	add	r1,r1
	add	ovf,aux
	add	r2,r2

; save registers for actual stepping sequence
	xmit	seek_temp_1 & 0ffh,ram_addr_low
	move	r2,wr_ram
	move	r3,wr_ram
	move	r4,wr_ram

; get step rate in r2
	xmit	step_rate & 0ffh,ram_addr_low
	xmit	4h,aux		; drive control reg STEP bit
	move	rd_ram[3:0],r2

	xor	r5,drive_control	; turn on STEP bit
	xmit	0ffh,aux

	xmit	9h,r4		; delay
	add	r4,r4
	nzt	r4,$-1

	move	r5,drive_control	; turn off step bit

x01eb:	nzt	r2,$+2		; pulse count = 0?
	jmp	step_pulses_done

	add	r2,r2		; pulse count -= 1
	xmit	4h,r4

x01ef:	xmit	0f8h,r3		; delay
	add	r3,r3
	nzt	r3,$-1

	add	r4,r4
	nzt	r4,x01ef
	jmp	x01eb


step_pulses_done:
; restore registers used in stepping sequence
	xmit	seek_temp_1 & 0ffh,ram_addr_low
	move	rd_ram,r2
	move	rd_ram,r3
	move	rd_ram,r4
	jmp	x01bd


x01fa:	jmp	x005e


; return to caller, r11 specifies return loc
seek_return:
	xec	x01fb,r11
	jmp	x006c		; 1
	jmp	x0079		; 2
	jmp	x0084		; 3
	jmp	x0143		; 4
