
# mp1.S - missile-command version
# Good luck, and have fun!

.data
	

	mp1_list_head: .long 0
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'
	EXPLOSION = 64

	# Character to draw for empty space
	SPACE = 32

	# Characters for base
	L_SLASH = 47
	BASE_X = 120
	ROOF = 94
	R_SLASH = 92

	#Value of first position of first base
	BOT_ROW = 3876
	#Distance from last position of a base to first of next -1
	GAP = 32

	#Row width value
	FULL_Y = 80

	#Character for crosshairs
	CROSSHAIR = 43

	#Bytes for checking bases
	FIRST_BYTE = 0x00000001
	SECOND_BYTE = 0x00000100
	THIRD_BYTE = 0x00010000

	#Value for setting all bases to alive
	START_BASES = 0x00010101

	#Shift Bits value for xhair
	SHIFT = 16

	#Max dimensions of frame
	MAX_X = 79
	MAX_Y = 24

	#Add a one in position 16, 17, 18 for status
	SIXTEEN = 0x00008000
	SEVENTEEN = 0x00010000
	EIGHTEEN = 0x00020000

	#This will have the size of missile
	MISSILE_SIZE = 36


# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs

.text

#cl = lower half of ecx 

# void mp1_poke(void);
# You can use this function to write to video memory.

#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write (Character 1/0)
#            %eax - Offset from the start of video memory that you wish
#                   to write to (position)
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
pushl %ebp
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi

push %eax
push %ecx
push %edx

call update_missiles
call draw_cities
call draw_crosshairs

pop %edx
pop %ecx
pop %eax

popl %esi
popl %edi
popl %ebx
leave

		ret


# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
movl 8(%esp), %ebx #get the cmd value

cmpl $0, %ebx
jl bad_cmd
cmpl $4, %ebx
jg bad_cmd

jmp *ioctl_functions(,%ebx,4)

bad_cmd: #If outside the range of 0 to 4
movl $-1, %eax #We return with -1

ret

ioctl_functions: .long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame


# ----------------- Functions private to this file -------------------

update_missiles:
pushl %ebp
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi

movl mp1_missile_list, %ebx #Grab the head of the list
cmpl $0, %ebx #See if its empty
je tasklet_end #If there are no missiles, end

through_list:
cmpl  $0, EXPLODED(%ebx) #See if it has exploded
jg decrease_exploded
#If it got past here, it hasn't reached the dest yet

#remove current missile spot
movl $0, %eax #clear eax
movl $0, %ecx
movl Y(%ebx), %ecx #get value of yz as row counter
shr $SHIFT, %ecx
re_mis_mul: #remove missile multiply operation
cmpl $0, %ecx #If y=0, no more multiplication
je re_mis_mul_done #remove missile multiply done
addl $FULL_Y, %eax #Add the width of a row for the multipication
subl $1, %ecx #Decrement ecx in exchange for the 80
jmp re_mis_mul
re_mis_mul_done:
addl %eax, %eax #Now multiply the value by 2 for the row value

#Now work on adding column value
#It's adding the column value twice
movl X(%ebx), %ecx
shr $SHIFT, %ecx
addl %ecx, %eax 
addl %ecx, %eax 

#space
movl $SPACE, %ecx

pushl %eax
pushl %ecx
pushl %edx

call mp1_poke

popl %edx
popl %ecx
popl %eax


#update positions
movl VX(%ebx), %ecx #grab x velocity and add it to x position
addl %ecx, X(%ebx)
movl VY(%ebx), %ecx #grab y velocity and add it to y position
addl %ecx, Y(%ebx)

#Check outside x
cmpl $0, X(%ebx)
jl free_missile
cmp $79, X(%ebx)
jg free_missile
#check outside y
cmpl $0, Y(%ebx)
jl free_missile
cmpl $24, Y(%ebx)
jg free_missile
#If we are out of bounds, free misssile

movl $0, %edx #Use this as a flag to check if we hit the destination
movl X(%ebx), %ecx
subl DEST_X(%ebx), %ecx
addl %ecx, %edx #Put the difference between x and dest_x in edx
movl Y(%ebx), %ecx
subl DEST_Y(%ebx), %ecx
addl %ecx, %edx #Put the difference between y and dest_y in edx

cmpl $0, %edx #If it's not zero, we have not hit the dest, and we keep the character c
jg char_c
#In the case we have hit the dest, we get explode


pushl %eax
pushl %ecx
pushl %edx

push $EXPLOSION #Push the @ character on the stack to grab later
pushl %ebx

call missile_explode

popl %edx
popl %edx

popl %edx
popl %ecx
popl %eax

cmpl $0, %eax
je draw_missile

pushl %eax
pushl %ecx
pushl %edx

call mp1_notify_user

popl %edx
popl %ecx
popl %eax

jmp draw_missile

char_c:
push C(%ebx)#push the character c for to grab
jmp draw_missile

decrease_exploded:#Decrease the det value
subl $1, EXPLODED(%ebx)
cmpl $0, EXPLODED(%ebx) 
je done_exploding #If it's zero, we want to replace it with a space. 
#Otherwise, keep the explosion character
push $EXPLOSION
jmp draw_missile

done_exploding:
push $SPACE


draw_missile:
movl $0, %eax #clear eax
movl Y(%ebx), %ecx #get value of y as row counter
draw_mis_mul: #draw missile multiply operation
cmpl $0, %ecx #If y=0, no more multiplication
je draw_mis_mul_done #draw missile multiply done
addl $FULL_Y, %eax #Add the width of a row for the multipication
subl $1, %ecx #Decrement ecx in exchange for the 80
jmp draw_mis_mul
draw_mis_mul_done:
addl %eax, %eax #Now multiply the value by 2 for the row value

#Now work on adding column value
#It's adding the column value twice
addl X(%ebx), %eax 
addl X(%ebx), %eax 

#grab the character we put on the stack, whether it be char c, space, or @
pop %ecx

pushl %eax
pushl %ecx
pushl %edx

call mp1_poke

popl %edx
popl %ecx
popl %eax

cmpl $32, %ecx #If we have a space here, then the missle is gone, so we free
je free_missile


jmp next_missile
free_missile:

pushl %eax
pushl %ecx
pushl %edx

pushl %ebx
call mp1_free
popl %ebx

popl %edx
popl %ecx
popl %eax

next_missile: #Get the next missile
movl  NEXT(%ebx), %ebx
cmpl $0, %ebx
jne  through_list #If it's not 0, we still go through

tasklet_end:
popl %esi
popl %edi
popl %ebx
leave

		ret

#draw the base
draw_cities:
pushl %ebp
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi

movb $0, %cl
movl $BOT_ROW, %eax #Put first base, first position value in 

movl base_alive, %ebx #Get the base's position and find if base 1 is good
andl $FIRST_BYTE, %ebx
cmpl $0, %ebx
je b1dead #if it's zero, it's destroyed
#draw stuff for the alive base
movb $L_SLASH, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax
addl $2, %eax
movb $ROOF, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax
addl $2, %eax
movb $ROOF, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax
addl $2, %eax
movb $ROOF, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax
addl $2, %eax
movb $R_SLASH, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

jmp base1_done
b1dead:
#draw stuff for the dead base
movb $BASE_X, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $BASE_X, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $BASE_X, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $BASE_X, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $BASE_X, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax


#Done with base 1
base1_done:

#Reset width and now add gap
addl $GAP, %eax

movl base_alive, %ebx 
andl $SECOND_BYTE, %ebx
cmpl $0, %ebx
je b2dead #if it's zero, it's destroyed
#draw stuff for the alive base
movb $L_SLASH, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

#Always add 2 due to byte offset
addl $2, %eax
movb $ROOF, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $ROOF, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $ROOF, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $R_SLASH, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

jmp base2_done
b2dead:
#draw stuff for the dead base
movb $BASE_X, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $BASE_X, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $BASE_X, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $BASE_X, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $BASE_X, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax


#Done with base 2
base2_done:

addl $GAP, %eax
movl base_alive, %ebx 
andl $THIRD_BYTE, %ebx
cmpl $0, %ebx
je b3dead
movb $L_SLASH, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $ROOF, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $ROOF, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $ROOF, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $R_SLASH, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax


jmp base3_done
b3dead:
movb $BASE_X, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $BASE_X, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $BASE_X, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $BASE_X, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

addl $2, %eax
movb $BASE_X, %cl
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax


base3_done:

#Pop the stored values
popl %esi
popl %edi
popl %ebx
leave

ret



draw_crosshairs:

pushl %ebp
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi

movl $0, %eax #clear eax
movl crosshairs_y, %ecx #get value of y as row counter
crosshair_mul: #Crosshair multipication operation
cmpl $0, %ecx #If y=0, no more multiplication
je crosshair_mul_done #Crosshair multiplication done
addl $FULL_Y, %eax #Add the width of a row for the multipication
subl $1, %ecx #Decrement ecx in exchange for the 80
jmp crosshair_mul
crosshair_mul_done:
addl %eax, %eax #Now multiply the value by 2 for the row value

#Now work on adding column value
#It's adding the column value twice
addl crosshairs_x, %eax 
addl crosshairs_x, %eax 

#Crosshair
movl $CROSSHAIR, %ecx
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax



popl %esi
popl %edi
popl %ebx
leave
ret 

#Start the game
mp1_ioctl_startgame:
pushl %ebp
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi

movl $12, crosshairs_y #Put the (40,12) location in to start 
movl $40, crosshairs_x #as was asked in the document

movl $START_BASES, base_alive #Set nonzero values for the bases


popl %esi
popl %edi
popl %ebx
leave

		ret

mp1_ioctl_addmissile:
pushl %ebp
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi


movl 8(%ebp), %ecx #pointer to the missile


#Allocate space

#Put Caller saves here
pushl %ecx

pushl $MISSILE_SIZE #Get the missile pointer for the function
call mp1_malloc
popl %ecx #Get rid of 36

#Pop caller saves here
popl %ecx

#Return address in eax
#Also store it in ebx for safety
movl %eax, %ebx
#If eax is 0, just skip to return -1
cmpl $0, %eax
je addmissile_minus1


#Call mp1_copy_from_user to put it in kernel

#Put Caller saves here
push %ecx

push $MISSILE_SIZE #Push n
push %ecx
push %eax
call mp1_copy_from_user

#The TAs just shrugged at messing with esp, so I'm just popping 3 times
pop %ecx
pop %ecx
pop %ecx

pop %ecx#Pop caller saves here

cmpl $0, %eax #Check if it returns 0. Pop Callers there
#If eax is 0 here, use free with the spot for malloc, then -1
jne addmissile_minus1m

#If eax is 0 here, use free with the spot for malloc, then -1

#Put the missile in the list
#ebx is new missile
movl mp1_missile_list, %ebx
movl %ebx, NEXT(%ecx)
movl %ecx, mp1_missile_list

#Return 0
movl $0, %eax
jmp addmissile_end

#Return -1
addmissile_minus1:
movl $-1, %eax
jmp addmissile_end

#Return -1 after malloc
addmissile_minus1m:

pushl %ebx #return register for undoing the malloc
call mp1_free

#Pop off the ebx (since messing with esp is bad)
popl %eax
movl $-1, %eax

addmissile_end:
popl %esi
popl %edi
popl %ebx
leave

		ret

mp1_ioctl_movexhairs:
pushl %ebp
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi

#Erase the old crosshair
movl $0, %eax #clear eax
movl crosshairs_y, %ecx #get value of y as row counter
old_hair_mul: #Crosshair multipication operation
cmpl $0, %ecx #If y=0, no more multiplication
je old_hair_mul_done #Crosshair multiplication done
addl $FULL_Y, %eax #Add the width of a row for the multipication
subl $1, %ecx #Decrement ecx in exchange for the 80
jmp old_hair_mul
old_hair_mul_done:
addl %eax, %eax #Now multiply the value by 2 for the row value

#Now work on adding column value
#It's adding the column value twice
addl crosshairs_x, %eax 
addl crosshairs_x, %eax 

#Crosshair
movl $SPACE, %ecx
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax

movl 8(%ebp), %ebx #get the xhair value
movl %ebx, %eax #Put xhair in another register
#eax will be replaced later, so it should be fine to use
#ebx will be lower 16, eax upper 16
shl $SHIFT, %ebx
shr $SHIFT, %ebx
shr $SHIFT, %eax

addw %bx, crosshairs_x #Add the new x value into the crosshair
cmpw $0, crosshairs_x
jge X_Hair_Zero
movl $0, crosshairs_x
jmp Adjust_X_Hair_Done
X_Hair_Zero: #If x >= 0
cmpw $MAX_X, crosshairs_x 
jle Adjust_X_Hair_Done
movl $MAX_X, crosshairs_x
Adjust_X_Hair_Done: #For when we're done fixing x

addw %ax, crosshairs_y
cmpw $0, crosshairs_y
jge Y_Hair_Zero
movl $0, crosshairs_y
jmp Adjust_Y_Hair_Done
Y_Hair_Zero: #If y >= 0
cmpw $MAX_Y, crosshairs_y 
jle Adjust_Y_Hair_Done
movl $MAX_Y, crosshairs_y
Adjust_Y_Hair_Done: #For when we're done fixing y

#Draw the new crosshair
movl $0, %eax #clear eax
movl crosshairs_y, %ecx #get value of y as row counter
new_hair_mul: #Crosshair multipication operation
cmpl $0, %ecx #If y=0, no more multiplication
je new_hair_mul_done #Crosshair multiplication done
addl $FULL_Y, %eax #Add the width of a row for the multipication
subl $1, %ecx #Decrement ecx in exchange for the 80
jmp new_hair_mul
new_hair_mul_done:
addl %eax, %eax #Now multiply the value by 2 for the row value

#Now work on adding column value
#It's adding the column value twice
addl crosshairs_x, %eax 
addl crosshairs_x, %eax 

#Crosshair
movl $CROSSHAIR, %ecx
pushl %eax
pushl %ecx
pushl %edx
call mp1_poke
popl %edx
popl %ecx
popl %eax


movl $0, %eax #return 0 always

popl %esi
popl %edi
popl %ebx
leave

		ret

mp1_ioctl_getstatus:
pushl %ebp
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi

movl $0, %ecx #Clear ecx to hold stuff

#Check First Base
movl base_alive, %ebx #Get the base value
andl $FIRST_BYTE, %ebx
cmpl $0, %ebx
je no_base1 #add value if it's not zero, skip if not
addl $SIXTEEN, %ecx
no_base1:

#Check Second Base
movl base_alive, %ebx #Get the base value
andl $SECOND_BYTE, %ebx
cmpl $0, %ebx
je no_base2 #add value if it's not zero, skip if not
addl $SEVENTEEN, %ecx
no_base2:

#Check THird Base
movl base_alive, %ebx #Get the base value
andl $THIRD_BYTE, %ebx
cmpl $0, %ebx
je no_base3 #add value if it's not zero, skip if not
addl $EIGHTEEN, %ecx
no_base3:

addl $mp1_score, %ecx

#Now call copy to function
push %ecx
movl %esp,  %eax #Get the address of the score as the from value
movl 8(%ebp), %ebx #pointer to the to


pushl $MISSILE_SIZE #Push n
pushl %eax #*from value
pushl %ebx #*to value
call mp1_copy_to_user
movl %eax, %ebx #Get returned value

#Remove arguments and the score (4 of them, hence 16)
popl %ecx
popl %ecx
popl %ecx
#Then pop the caller registers
popl %ecx


cmpl $0, %ebx
je status_ret0
movl $-1, %eax
jmp status_end
status_ret0:
movl $0, %eax

status_end:

popl %esi
popl %edi
popl %ebx
leave


		ret

mp1_ioctl_endgame:
movl %esp, %ebp
pushl %ebx
pushl %edi
pushl %esi

movl mp1_missile_list, %ebx
cmpl $0, %ebx
je end_theendgame
movl NEXT(%ebx), %ecx

another_missile:

pushl %eax
pushl %ecx
pushl %edx
pushl %ebx
call mp1_free
add $4, %esp
popl %edx
popl %ecx
popl %eax

cmpl $0, %ecx
je end_theendgame
movl %ecx, %ebx
movl NEXT(%ebx), %ecx
jmp another_missile

end_theendgame:

popl %esi
popl %edi
popl %ebx
leave

		ret
