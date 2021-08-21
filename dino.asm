%define VAR_BASE 0xfa00
%define @(name) [bp+(name)-VAR_BASE]

[org 0x7c00]

cpu 8086
use16

_start:
	mov ax, 0x0013
	int 0x10		; set video 320x200x256 mode

	mov ax, 0xa000	; 0xa000 video segment
	mov es, ax		; setup extended segment

	mov bp, VAR_BASE

	; init screen
	mov al, 0x0f
	mov cx, screen_width*screen_height
	xor di, di
	rep stosb

	xor ax, ax
	; clearing variable memory
	mov di, VAR_END-VAR_BASE-1
	; use a manual loop since the destination is in ds
	.clear:
		mov [bp+di], al
		dec di
		jns .clear

	; initialize vars
	mov byte @(e_t_set_b), enemy_timer_max	; enemy timer

	; draw ground line
	mov di, ground_start
	mov cl, screen_width/2	; cx=0 from above
	; ax=0 from above
	rep stosw

	; init_dirt generates random dirt
	init_dirt:
		mov cx, dirt_rows
	_id_l:
		call random_pixel
		loop _id_l
	; end init_dirt


_game_loop:
	dec byte @(enemy_timer_b)	; decreasing the enemy timer


	; clear playarea
	mov al, 0x0f
	mov di, playarea_start
	mov cx, playarea_lines*screen_width
	rep stosb


	print_score:
		mov cl, 0x27		; cx=0, set initial column
		mov ax, [score_w]	; get score

	_ps_div:
		cwd				; clear dx
		div word [ten]	; divide ax by 10
		add dl, 0x30	; convert number to ascii

		; saving registers so that interrupts don't interfere
		push ax

		mov al, dl	; get char from dl
		mov dl, cl	; get column from cl

		mov bx, 0x000f	; bh (page) = 0x00; bl (colour) = 0x0f (used later)

		mov ah, 0x02	; set cursor
		int 0x10

		mov ah, 0x0e	; printin chars bby
		int 0x10

		; recovering the registers
		pop ax

		dec cx	; decrement column

		or ax, ax
		jnz _ps_div
	; end print_score


	mov dh, enemy_speed	; setting enemy speed
	; dh = amount to advance the enemies
	; handle_draw_enemies loops through all the enemies
	handle_draw_enemies:
		mov cx, max_enemies
		mov di, enemies_start
	_dhe_l:
		mov bx, word [di]	; get x,y coord
		or bl, bl			; checking if the enemy is outside the screen
		jz _dhe_re			; if so, try creating a new one

		; setting vars for draw_sprite
		mov dl, enemy_scaling	; scaling
		mov si, [di+2]			; get sprite address
		mov al, bh				; y position
		call draw_sprite

		sub byte [di], dh	; subtract from x position
		jnb _dhe_after_point
		inc word @(score_w)
		mov byte [di], 0	; just so it doesn't overflow on me

		mov ax, [score_w]		; get score
		mov bl, score_divisor
		div bl					; divide score by score_divisor
		or ah, ah
		jnz _dhe_after_point	; if score%score_divisor != 0

		; decreasing the timer
		cmp byte @(e_t_set_b), enemy_timer_min
		jng _dhe_after_point	; if e_t_set_b <= enemy_timer_min
		dec byte @(e_t_set_b)
	_dhe_after_point:

		jmp _dhe_i_end			; jump to the end

	_dhe_re:
		; bl=0 on entry
		; random_enemy assumes di is set by handle_draw_enemies
		random_enemy:
			; checking the timer
			cmp byte @(enemy_timer_b), bl
			jg _re_end

			mov al, [e_t_set_b]
			mov byte @(enemy_timer_b), al	; setting the enemy timer

			; preparing enemy
			mov word [di], 255 | (139 << 8)	; set horizontal & vertical position
			mov word [di+2], cactus+7		; setting sprite to cactus

			; randomizing enemy
			in ax, 0x40	; get 'random' number

			shr al, 1
			jnc _re_end

			; changing sprite from cactus to bomber
			add word [di+2], bomber-cactus
			sub byte [di+1], 18	; changing bomber's vertical position

			shr al, 1
			jc _re_end

			sub byte [di+1], 25	; once again lifting bomber
		_re_end:
		; end random_enemy

	_dhe_i_end:
		; advance by enemy_size (di += 4)
		scasw
		scasw
		loop _dhe_l
	; end handle_draw_enemies


	; cx=0 on entry
	; handle_jump:
		mov si, rows_jump_b
		mov bx, rows_up_b
		cmp byte [bx], cl		; cl=0, check if dino is in the air
		jng _hj_no_rows
		sub byte [bx], gravity	; if so, subtract gravity from it's displacement
		jmp _hj_no_keystroke	; and don't check for a keystroke

	_hj_no_rows:
		mov ah, 0x02		; get shift flags
		int 0x16
		test al, 0b11		; testing for shift keys
		jz _hj_no_keystroke
		mov byte [si], jump
	_hj_no_keystroke:

		mov al, [si]
		cmp al, 0				; check if jump force is greater than 0
		jng _hj_no_jump
		add byte [bx], al		; if it is - add it to the displacement
		sub byte [si], gravity	; subtract gravity from the jump force
	_hj_no_jump:
	; end handle_jump


	; draw_dino draws dino accounting for the jump value
	; draw_dino:
		mov ax, dino_initial_y	; ah=0
		mov bx, dino_initial_x	; bh=0

		; check if to subtract the jump value
		mov cl, @(rows_up_b)
		cmp cl, ah	; ah=0
		jng _dd_no_jump
		sub al, cl
	_dd_no_jump:

		; check for collisions
		push ax
		mov dx, screen_width
		mul dx
		lea di, [bx+5*dino_scaling]
		add di, ax
		mov byte cl, [es:di]

		; check for crouch
		mov ah, 0x02
		int 0x16
		xor al, 0b100	; check for ctrl key
		jnz _dd_no_crouch

		mov dl, dino_scaling_crouched
		mov byte @(rows_up_b), bh	; bh is 0, thanks to previous mov

		jmp _dd_crouch_end
	_dd_no_crouch:
		mov dl, dino_scaling

		sub di, 7*dino_scaling*screen_width-2*dino_scaling
		and byte cl, [es:di]

	_dd_crouch_end:
		pop ax

		; draw dino!
		mov si, dino+7
		call draw_sprite

		; finalize collision check
		or cl, cl
		jz game_over
	; end draw_dino


	; scrolls the ground at ground_start
	scroll_ground:
		mov si, ground_start+screen_width+1
		mov di, ground_start+screen_width
		mov cx, dirt_rows-1
		rep es movsb

		call random_pixel	; generate random pixel at the end
	; end scroll_ground


	; waits for 1 system clock tick
	frame:
		mov ah, 0
		int 0x1a
	_f_l:
		mov bl, dl
		int 0x1a
		xor bl, dl
		jz _f_l
	; end frame

	jmp _game_loop



; prints game over string, waits for input, and then resets the game
game_over:
	mov bx, 0x000f	; page 0, white colour
	mov dx, 0x0c0f	; cursor row and col
	mov ah, 0x02	; set cursor
	int 0x10

	mov ah, 0x0e				; print char interrupt
	mov cx, str_go_end-str_go	; 10 chars
	mov si, str_go				; point to game_over string

_go_l:
	lodsb		; get char
	int 0x10	; print it
	loop _go_l

	mov ah, 0x00	; wait for an input
	int 0x16

	jmp _start


random_pixel:
	in al, 0x40
	and al, 0x55
	jz _dd_black
	mov al, 0x0f
_dd_black:
	stosb
	ret


; al = y coord, bl = x coord, dl = scaling;
; modify coords and scaling; scaling - 1 for 8x8 pixels
; mov the address of the sprite's last byte to the si register (addr+7)
draw_sprite:
	push cx
	push di

	; high bytes of the words will always be 0
	mov byte @(y_coord_w), al
	mov byte @(x_coord_w), bl
	mov bl, 8	; bl will act as the sprite's byte counter
	mov bh, dl	; bh will act as the row scaling counter

_ds_coords:
	; prepare starting coords
	push dx
	mov ax, @(y_coord_w)	; get y coord
	mov dx, screen_width	; size of pixel row
	mul dx					; multiply ax by screen_width
	pop dx

	add ax, @(x_coord_w)	; add x coord
	xchg ax, di

	mov cl, 8			; cl will act as the sprite's pixel counter
_ds_row_pixel:
	mov byte al, [si]	; load sprite's byte
	shr al, cl
	mov al, 0			; set colour to black

	push cx
	mov cl, dl	; horizontal scaling

	jc _ds_draw_pixel	; perform a jump if carry is set because of shr
	add di, cx			; advance di
	jmp _ds_trans_done
_ds_draw_pixel:
	rep stosb			; draw picked colour
_ds_trans_done:
	pop cx

	loop _ds_row_pixel		; loop for 8 pixels

	dec word @(y_coord_w)	; increase the y coord

	dec byte bh				; decrement the row counter
	jnz _ds_coords			; repeat row

	mov byte bh, dl			; reset row counter

	dec si					; increase sprite address
	dec bl					; decrease the byte counter
	jnz _ds_coords

	pop di
	pop cx
	ret


; general consts
ten				equ 10
screen_width	equ 320
screen_height	equ 200

; draw_dino consts
dino_initial_y			equ 139
dino_initial_x			equ 35
dino_scaling			equ 3
dino_scaling_crouched	equ 2

; ground consts
ground_start	equ 140*screen_width
dirt_rows		equ 10*screen_width

; clear_playarea consts
playarea_start	equ 26*screen_width
playarea_lines	equ 114

; handle_jump consts
gravity	equ 7
jump	equ 30

; handle_draw_enemies consts
max_enemies		equ 40
enemy_size		equ 1+1+2	; (byte, byte, word)
enemy_speed		equ 7
enemy_scaling	equ 2

; enemy_timer_consts
enemy_timer_max	equ 20
enemy_timer_min	equ 10

; score will be divided by this value when checking if to increase difficulty
score_divisor	equ 10

; game_over string const
str_go	db	"game over!"
str_go_end:

; sprite data
dino	db \
	0b00000110, \
	0b00001101, \
	0b00001111, \
	0b00011110, \
	0b10111100, \
	0b01111010, \
	0b00010000, \
	0b00011000

cactus	db \
	0b00011100, \
	0b00100010, \
	0b01110011, \
	0b00100110, \
	0b01101011, \
	0b00100010, \
	0b01100111, \
	0b00110010

bomber	db \
	0b00000011, \
	0b00000111, \
	0b01101110, \
	0b10111111, \
	0b11111111, \
	0b00001110, \
	0b00000111, \
	0b00000001

times 510-($-$$) db 0
; the magic number
dw 0xaa55

[absolute VAR_BASE]
; draw_sprite variables
y_coord_w	resw 1	; word
x_coord_w	resw 1	; word

; score variable
score_w	resw 1

; handle_jump variables
rows_up_b	resb 1
rows_jump_b	resb 1

; random_enemy variable
enemy_timer_b	resb 1

; variable that the enemy_timer_b will be set to after overflowing
e_t_set_b	resb 1

; handle_draw_enemies variable
enemies_start	resb enemy_size * max_enemies

VAR_END:
