; WD1000 hard disk controller firmware reverse-engineered source code
; 1024-word version, with dynamic sector size support
; from a Radio Shack 5.25-inch Winchester controller

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


; Fast I/O select ports
; Note that the normal 8X300 port addressing scheme is not used;
; writing to the ivl and ivr address registers writes to the port
; selected by the fast I/O select PROM.

rd_ram		riv	rr=0
drq_clk		liv	rr=1
rd2		liv	rr=2
drq_clk		liv	rr=3
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
	nzt	aux,x0083		; no, so perform command

	; was a read command, so now it's done
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

	xmit	0h,r6	; clear error register
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

	xmit	7h,aux		; get head selct bits of SDH
	and	r5,r11

	xmit	3h,aux		; get drive select bits of SDH
	and	r5>>>3,aux
	xec	drive_sel_table,aux	; translate to bit position
	xor	r11,drive_head_sel	; set drive and head select

	xmit	0h,aux
	jmp	main_loop

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
	jmp	x012c

x0068:	xmit	10h,aux
	jmp	int_and_reset_data_pointer


cmd_seek:
	xmit	1h,r11	; call seek_save_step_rate, r11 specifies return loc
	jmp	seek_save_step_rate
clear_err_reg_and_reset_data_pointer:
	xmit	0h,aux
	xmit	0h,r6	; clear error reg

int_and_reset_data_pointer:
	nzt	int_clk,$+1	; set interrupt

; sets data pointer back to beginning of buffer
; BUG - always sets for 512-byte buffer
reset_buffer_pointer:
	xmit	0h,ram_addr_low
	xmit	96h,mac_control	; 512-byte
	jmp	main_loop


cmd_restore:
	xmit	drive_3_cylinder_high & 0ffh,aux
	and	r5,ram_addr_low
	xmit	4h,wr_ram	; set drive's current cylinder to 1024
	xmit	0h,wr_ram
	xmit	0h,r3
	xmit	0h,r4
	xmit	2h,r11	; call seek_save_step_rate, r11 specifies return loc
	jmp	seek_save_step_rate
x007a:	move	rd5[3],aux	; check track 0
	nzt	aux,clear_err_reg_and_reset_data_pointer
	xmit	2h,r6		; set error register for TR000 error
	jmp	x0068


	jmp	x0080		; unused
	nop	 // rd=0	; unused


x0080:	jmp	cmd_format_track


cmd_read_write:
	xmit	command_byte & 0ffh,ram_addr_low
	nzt	rd_ram[4],x0080		; write command?

x0083:	xmit	auto_restore_ok & 0ffh,ram_addr_low	; mark that no auto restore has been done
	xmit	0ffh,wr_ram

do_read_write_retry:
	xmit	3h,r11		; call seek, r11 specifies return loc
	jmp	seek
x0087:	xmit	18*2,r1		; max 18 pulses
	xmit	0h,r6		; no error
x0089:	xmit	91h,mac_control
	xmit	81h,mac_control
	xmit	0feh,aux	; ID mark byte for cyl 0-255, also used for counter

x008c:	nzt	rd5[0],read_write_no_index	; check INDEX
	xmit	0h,reset_index	; clear index
	add	r1,r1		; count down index pulses
	nzt	r1,read_write_no_index
	jmp	read_write_too_many_index

read_write_no_index:
	nzt	rd5[2],$+2	; check DRUN
	jmp	x008c

	xmit	18h,r11
x0094:	nzt	rd5[1],$+2	; check HFRQ
	jmp	x0089

	add	r11,r11
	nzt	r11,x0094
	xmit	0eh,r11
	xmit	09h,mac_control
	nzt	rd_serdes,$+1

	xmit	id_field_s_h_bb,ram_addr_low	; set up to save ID field sec size, head, bad block flag

	nzt	rd5[1],$	; wait for HFRQ
	xmit	01h,mac_control
	jmp	x00a0

	nop	 // rd=0	; unused

x00a0:	add	r11,r11
	nzt	r11,$+2
	jmp	x0089

; check ID field mark byte and cylinder high
	nzt	rd2[6],x00a0	; bdone
	xor	r4,aux
	xor	rd_serdes,aux
	nzt	aux,x0089

; check ID field cylinder low
	move	r3,aux
	nzt	rd2[6],$	; wait for bdone
	xor	rd_serdes,aux
	nzt	aux,x0089

; check ID field sector size and head number
	xmit	67h,aux
	and	r5,aux
	nzt	rd2[6],$	; wait for bdone
	move	rd_serdes,wr_ram
	xor	rd_serdes[6:0],aux
	nzt	aux,x0089

; check ID field sector number
	move	r2,aux
	nzt	rd2[6],$	; wait for bdone
	xor	rd_serdes,aux
	nzt	aux,x0089

	xmit	drive_3_cylinder_high & 0ffh,aux	; point to drive's current cyl
	and	r5,ram_addr_low

	nzt	rd2[6],$	; wait for bdone
	nzt	rd_serdes,$+1
	move	rd_ram[9:2],aux
	xor	rd_ram[7:2],r11

	nzt	rd2[6],$	; wait for bdone
	nzt	rd_serdes,$+1
	xmit	0ffh,aux
	xor	r11,aux
	xmit	precomp & 0ffh,ram_addr_low

	nzt	rd2[6],$	; wait for bdone
	xmit	91h,mac_control

	nzt	rd2[5],id_field_crc_error	; check CRCOK
	add	rd_ram,aux
	xmit	id_field_s_h_bb & 0ffh,ram_addr_low
	move	rd_ram[7],aux		;  get back block flag (MSB of ID field sector size/head byte)
	nzt	aux,bad_block

	xmit	command_byte & 0ffh,ram_addr_low
	nzt	rd_ram[4],write_sector	; cmd bit 4 distinguishes read/write
	jmp	read_sector


id_field_crc_error:
	xmit	0dfh,aux	; turn on 20h bit of error reg of ID CRC err
	and	r6,r6
	xmit	20h,aux
	xor	r6,r6
	jmp	x0089


write_sector:
	xmit	0ch,aux
	xor	ovf>>>7,aux	; control RWC (bit 1)
	xmit	0h,wr_serdes
	xmit	0b9h,mac_control
	move	aux,drive_control

; write ten bytes of 00h
	xmit	0ffh,aux
	xmit	0ah,r11
x00d6:	nzt	rd2[6],$	; wait for bdone
	xmit	0h,wr_serdes
	add	r11,r11
	nzt	r11,x00d6

; write data address mark
	xmit	0b1h,mac_control
	nzt	rd2[6],$	; wait for bdone
	xmit	0a1h,wr_serdes

	xmit	3h,aux		; set RAM buffer address low from table
	and	r5>>>5,aux
	xec	wr_ram_buffer_addr_low_table,aux

	nzt	rd2[6],$	; wait for bdone
	xmit	0f8h,wr_serdes

	xec	wr_ram_buffer_addr_high_table,aux	; set RAM addr high (and MAC control) from table

; write content of data field
x00e3:	nzt	rd2[7],x00e7		; if RVOF, done writing data
	nzt	rd2[6],$		; wait for bdone
	move	rd_ram,wr_serdes
	jmp	x00e3

x00e7:	nzt	rd2[6],$		; wait for bdone
	xmit	0h,wr_serdes
	xmit	0f1h,mac_control
	xmit	5h,r11
	xmit	0ffh,aux
x00ec:	nzt	rd2[6],$		; wait for bdone
	xmit	0h,wr_serdes
	add	r11,r11
	nzt	r11,x00ec
	xmit	0fh,drive_control

	xmit	saved_sector_count & 0ffh,ram_addr_low
	move	rd_ram,r1

	jmp	clear_err_reg_and_reset_data_pointer


wr_ram_buffer_addr_low_table:
	xmit	0h,ram_addr_low
	xmit	0h,ram_addr_low
	xmit	0h,ram_addr_low
	xmit	80h,ram_addr_low

wr_ram_buffer_addr_high_table:
	xmit	0b3h,mac_control
	xmit	0b2h,mac_control
	xmit	0b2h,mac_control
	xmit	0b3h,mac_control


read_sector:
	xmit	0f8h,aux	; delay
	xmit	50h,r11
	add	r11,r11
	nzt	r11,$-1

	xmit	89h,mac_control
	xmit	0a0h,r11
	add	r11,r11
	nzt	r11,$-1
	xmit	09h,mac_control
	
	xmit	18h,r11		; delay
	add	r11,r11
	nzt	r11,$-1

	xmit	78h,r11
	xmit	3h,aux
	and	r5>>>5,aux
	xec	rd_ram_buffer_addr_high_table,aux
	xec	fmt_ram_buffer_addr_low_table,aux
	xmit	0f8h,aux
	nzt	rd_serdes,$+1
	jmp	x011b


rd_ram_buffer_addr_high_table:
	xmit	3h,mac_control
	xmit	2h,mac_control
	xmit	2h,mac_control
	xmit	3h,mac_control


x0114:	add	r11,r11
	nzt	r11,x011b

x0116:	xmit	0feh,aux	; turn on 01h bit in status reg for DAM not found
	and	r6,r6
	xmit	1h,aux
	xor	r6,r6
	jmp	x0089

x011b:	nzt	rd2[6],x0114		; bdone
	xor	rd_serdes,aux
	nzt	aux,x0116
	jmp	read_sector_data


	nop	 // rd=0	; not used


read_sector_data:
	nzt	rd2[7],x0124		; if ROVF, done reading sector data
	nzt	rd2[6],$		; wait for bdone
	move	rd_serdes,wr_ram
	jmp	read_sector_data

x0124:	nzt	rd2[6],$		; wait for bdone
	nzt	rd_serdes,$+1

	nzt	rd2[6],$		; wait for bdone
	nzt	rd_serdes,$+1

	nzt	rd2[6],$		; wait for bdone
	nzt	rd2[5],read_sector_crc_error	; test crc_ok
; fall through to generate interrupt and DRQ to host

cmd_format_track:
	xmit	95h,mac_control
	xmit	80h,aux
x012c:	xmit	command_byte & 0ffh,ram_addr_low
	nzt	rd_ram[4:3],$+2
	nzt	int_clk,$+1
	move	rd_ram,r1
	move	aux,r11

	xmit	3h,aux
	and	r5>>>5,aux
	xec	fmt_ram_buffer_addr_low_table,aux

	xec	fmt1_ram_buffer_addr_high_table,aux
	move	r11,aux
	jmp	main_loop_set_drq


read_sector_crc_error:
	xmit	40h,r6		; data CRC err bit in error reg
	jmp	x0089


fmt1_ram_buffer_addr_high_table:
	xmit	97h,mac_control
	xmit	96h,mac_control
	xmit	96h,mac_control
	xmit	97h,mac_control


read_write_too_many_index:
	xmit	40h,aux		; already have data field CRC error?
	and	r6,aux
	nzt	aux,x0149	; yes, report that

	xmit	1h,aux		; already have DAM not found error?
	and	r6,aux
	nzt	aux,x0149	; yes, report that

	xmit	20h,aux		; already have ID field CRC error?
	and	r6,aux
	nzt	aux,x0149	; yes, report that

	xmit	auto_restore_ok & 0ffh,ram_addr_low ; has auto-restore retry been done?
	nzt	rd_ram,auto_restore_retry

	xmit	10h,aux		; write 10h to error reg for ID not found
x0149:	move	aux,r6
	jmp	x0061


x_do_read_write_retry:
	jmp	do_read_write_retry


auto_restore_retry:
	xmit	auto_restore_ok & 0ffh,ram_addr_low	; mark that we've done auto-restore
	xmit	0h,wr_ram
	xmit	drive_3_cyl_high & 0ffh,aux
	and	r5,ram_addr_low
	xmit	0h,wr_ram
	xmit	0h,wr_ram
	xmit	0fh,drive_control	; set dir inward, step not active

x0153:	nzt	rd5[3],x_do_read_write_retry	; if track 0, now retry read/write command
	xmit	0bh,drive_control	; set dir inward, set setp

	xmit	28h,r1
	add	r1,r1
	nzt	r1,$-1

	xmit	0fh,drive_control	; set dir inward, clear step
x0159:	nzt	rd5[4],x0153		; test seek complete
	jmp	x0159


fmt_ram_buffer_addr_low_table:
	xmit	0h,ram_addr_low
	xmit	0h,ram_addr_low
	xmit	0h,ram_addr_low
	xmit	80h,ram_addr_low

fmt2_ram_buffer_addr_high_table:
	xmit	0b3h,r6
	xmit	0b2h,r6
	xmit	0b2h,r6
	xmit	0b3h,r6


format_track:
	xmit	4h,r11		; call seek, r11 specifies return loc
	jmp	seek
x0165:	xmit	drive_3_cylinder_high & 0ffh,aux
	and	r5,ram_addr_low
	move	rd_ram[9:2],aux
	xor	rd_ram[7:2],r11
	xmit	0ffh,aux
	xor	r11,aux
	xmit	precomp & 0ffh,ram_addr_low
	add	rd_ram,aux
	xmit	0ch,aux
	xor	ovf<<<1,aux
	xmit	0b9h,mac_control
	xmit	0h,reset_index
	move	aux,drive_control

	xmit	3h,aux
	and	r5>>>5,aux
	xec	fmt_ram_buffer_addr_low_table,aux
	xec	fmt2_ram_buffer_addr_high_table,aux

	nzt	rd5[0],$	; wait for index

format_sector:
; write gap 3, 15 or 30 bytes of 4e
	xmit	1h,aux
	add	r5>>>5,r11
	and	r11>>>1,aux
	xmit	1eh,r11
	nzt	aux,x017d

	xmit	0fh,r11
x017d:	xmit	0ffh,aux
x017e:	nzt	rd2[6],$	; wait for bdone
	xmit	4eh,wr_serdes
	add	r11,r11
	nzt	r11,x017e

; write 14 bytes of 00
	xmit	0eh,r11
	xmit	0b9h,mac_control
x0184:	nzt	rd2[6],$		; wait for bdone
	xmit	0h,wr_serdes
	add	r11,r11
	nzt	r11,x0184

	move	r6,mac_control
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
	nzt	rd2[6],$

	move	rd_ram,wr_serdes
	nzt	rd2[6],$

; write 4 bytes of zeros after ID field
	xmit	0f1h,mac_control
x019a:	nzt	rd2[6],$		; wait for bdone
	xmit	0h,wr_serdes
	add	r11,r11
	nzt	r11,x019a
	xmit	0b1h,mac_control

; write 13 bytes of zeros before data field
	xmit	0dh,r11
x01a0:	nzt	rd2[6],$		; wait for bdone
	xmit	0h,wr_serdes
	add	r11,r11
	nzt	r11,x01a0

	xmit	0b9h,mac_control	; pulse CRC initialization
	xmit	0b1h,mac_control

; write Data AM
	nzt	rd2[6],$		; wait for bdone
	xmit	0a1h,wr_serdes
	xmit	3h,aux
	and	r5>>>5,aux
	xmit	0h,reset_index

	nzt	rd2[6],$
	xmit	0f8h,wr_serdes
	xmit	80h,r11

	xec	fmt3_sec_size_table,aux
	xmit	0ffh,aux

fmt_write_sector_data:
	nzt	rd2[6],$		; wait for bdone
	xmit	0h,wr_serdes

	nzt	rd2[6],$		; wait for bdone
	xmit	0h,wr_serdes

	add	r11,r11
	nzt	r11,fmt_write_sector_data

; write two bytes of CRC, 3 bytes of zeros
	xmit	5h,r11
	nzt	rd2[6],$		; wiat for bdone
	xmit	0f1h,mac_control
x01b9:	nzt	rd2[6],$		; wait for bdone
	xmit	0h,wr_serdes
	add	r11,r11
	nzt	r11,x01b9

	add	r1,r1			; more sectors to format?
	nzt	r1,format_sector

; write gap 4, 4E repeats until index
	xmit	4eh,wr_serdes
	nzt	rd5[0],$		; wait for index
	xmit	0fh,drive_control
	jmp	clear_err_reg_and_reset_data_pointer


fmt3_sec_size_table:
	xmit	80h,r11
	xmit	0h,r11
	xmit	0h,r11
	xmit	40h,r11


	org	200h


; on entry here, r6 contains the command byte
seek_save_step_rate:
	xmit	step_rate & 0ffh,ram_addr_low
	move	r6,wr_ram

seek:	xmit	80h,wr_host_port
	xmit	91h,mac_control
	xmit	5h,aux
	xor	rd5[6:4],aux
	nzt	aux,x0264

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
x0213:	xmit	0ffh,aux
	xor	r1,r1
	xor	r2,r2
	xmit	1h,aux
	add	r1,r1
	move	ovf,aux
	add	r2,r2
	nzt	r6,x0227
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
	nzt	aux,x0213
x0227:	nzt	r1,x0241
	nzt	r2,x0241

x0229:
; restore saved task file registers
	xmit	seek_save_sector & 0ffh,ram_addr_low
	move	rd_ram,r2
	move	rd_ram,r1
	move	rd_ram,r5

; was the command a seek
	xmit	command_byte & 0ffh,ram_addr_low
	xmit	7h,aux
	xor	rd_ram[6:4],r6
	nzt	r6,$+2
	jmp	x023a

; not a seek command
	xmit	80h,r6
	xmit	0ffh,aux
x0234:	xmit	0h,reset_index

	nzt	rd5[4],x023a	; check seek complete
	nzt	rd5[0],$-1	; check index

	add	r6,r6
	nzt	r6,x0234
	jmp	x005e


; command was seek
x023a:	xmit	2h,aux
	xor	rd5[6:5],aux
	nzt	aux,x0264
	jmp	seek_return


	jmp	x0229

x023f:	nzt	rd5[3],$-1
	jmp	x0244

x0241:	xmit	8h,aux
	and	r5,aux
	nzt	aux,x023f
x0244:	xmit	0ffh,aux
	add	r1,r1
	add	ovf,aux
	add	r2,r2

; save registers for actual stepping squence
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

x0255:	nzt	r2,$+2		; pulse count = 0?
	jmp	step_pulses_done

	add	r2,r2
	xmit	4h,r4

x0259:	xmit	0f8h,r3		; delay
	add	r3,r3
	nzt	r3,$-1

	add	r4,r4
	nzt	r4,x0259
	jmp	x0255


step_pulses_done:
; restore registers used in stepping sequence
	xmit	seek_temp_1 & 0ffh,ram_addr_low
	move	rd_ram,r2
	move	rd_ram,r3
	move	rd_ram,r4
	jmp	x0227


x0264:	jmp	x005e


; return to caller, r11 specifies return loc
seek_return:
	xec	x0265,r11
	jmp	clear_err_reg_and_reset_data_pointer // wr=7	; 1
	jmp	x007a // wr=7	; 2
	jmp	x0087 // wr=7	; 3
	jmp	x0165 // wr=7	; 4
