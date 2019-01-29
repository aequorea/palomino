; CHARGER.SRC -- firmware for the battery charger
; Copyright 1994 by John Saeger   ** confidential **
; 6-2-94
; 7-4-94   adjusted battery present voltage
;	   added max battery voltage to terminate charge
; 7-13-94  measure voltage twice
; 8-29-94  released to alpha site testing
; 9-11-94  smooth derivative, 2Hz depolarization
; 9-24-94  (rev D) released to alpha site testing
;  1-2-95  (rev E) move floor up 0.2V, fix trickle blip, soft termination
;  2-7-95  (ref F) quick start after bad battery



	DEVICE  XT_OSC, WDT_ON, PWRT_ON, PROTECT_ON
	
	ID 	'1967'

	ORG	0ch	;register space
	
seCounter	DS 1
rwCounter	DS 1
tsCounter	DS 1
msCounter	DS 1
usCounter	DS 1

tempCounter	DS 1
adCounter	DS 1
startupCounter	DS 1
finishCounter	DS 1

digit		DS 1
flags		DS 1

voltage		DS 2
oldVoltage	DS 2
newVoltage	DS 2
temperature	DS 2
result		DS 2
derivative	DS 2
multiplier	DS 2

blipCounter	DS 3
smoothVoltage	DS 3

;other symbols
                    
red	=	RB.6
green	=	RB.7
power	=	RB.5
clock	=	RB.4	;for the logic analyzer
pulse	=	RB.2	;for the frequency counter
trigger	=	RB.3	;for the frequency counter & HP 3490A
bit1	=	RB.1
bit0	=	RB.0

batPresent =	flags.0
batOk	=	flags.1
batFull =	flags.2
batLow	=	flags.3
amber	=	flags.4
justRight =	flags.5
highOrderBlipBit = flags.6
signBit	=	derivative.7
                        
RTIE =		INTCON.5
ADIE =		INTCON.6

CHARGEDELAY =	128	;# of quarter seconds in a charging loop
UPPERVOLTAGE =	231	; 10.0V or higher means no battery
FASTEXITVOLTAGE = 189	;  9.2V or higher means relaxed exit test
FINISHCOUNT =	6	; 3 minutes

;*
;* program starts here
;*

	ORG	0	;reset to code space
	
	jmp	start
	
	ORG	4	;interrupt handler
	
inth
	jnb	amber,iret
	jnb	red,igreen
	clrb	red
	setb	green
	jmp	iret
	
igreen
	clrb	green
	setb	red	
iret	
	clrb	RTIF	;clear RTC interrupt flag
;*	clrwdt
	retfie	

start
	mov	RA,#0
	mov	RB,#0
	mov	flags,#0
	setb	RP0			;register page 1
	mov	TRISB,#0	 	;RB is all outputs
	mov	OPTION,#11001111b
	clrb	RP0			;register page 0
	
	clr	RTCC			;clear the RTC register
	clrb	RTIF			;clear RTC interrupt flag
	setb	RTIE			;enable RTC interrupts
	setb	GIE			;enable general interrupts

	setb	trigger			;release the trigger
	call	clearSmoothVoltage
	setb	green
	mov	tsCounter,#20
	call	tenthSeconds		;wait for charger to "warm up"
	
;*
;* wait for a battery to be inserted
;*
	
batWait
	clrb	amber
	clrb	red
	setb	green			;green LED on
	mov	tsCounter,#5
	call	tenthSeconds		;wait half a second
	clrb	green			;green LED off
	mov	tsCounter,#5
	call	tenthSeconds		;wait half a second
	
	call	measureTemp
	call	realTemperature

	clrb	red
	setb	green			;green LED on
	mov	tsCounter,#5
	call	tenthSeconds		;wait half a second
	clrb	green			;green LED off
	mov	tsCounter,#5
	call	tenthSeconds		;wait half a second
	
	call	measureVoltage
	call	realityCheck		;check reality
	jnb	justRight,freezeFire    ;  temperature bad
	jnb	batOk,batBad		;  battery bad
	jnb	batPresent,batWait	;  no battery
	jnb	batOk,batBad		;  battery bad
	
startCharge	
	
;	cjae	newVoltage,#185,trickle	;  voltage > 9.1V
	
	mov	finishCounter,#FINISHCOUNT ;init finish counter
	
;*
;* main charging loop
;*	
	
chargeLoop
;	call	second
	setb	power			;turn on the power
	setb	amber			;turn on the amber led
;	call	second
	call	realityWait		;delay
	clrb	power
;*	clrb	amber			;turn off the power
	call	realityCheck		;check reality
	jnb	justRight,freezeFire    ;  temperature bad
	jnb	batPresent,batWait	;  no battery
	jnb	batOk,batBad		;  battery bad
	jb	batFull,finish		;  if battery's full, we're done
	mov	finishCounter,#FINISHCOUNT ;else reset finish counter
	cjbe	newVoltage,#FASTEXITVOLTAGE,chargeLoop
	mov	finishCounter,#2	;fast exit if > 9.2V
	jmp	chargeLoop	
		
finish	djnz	finishCounter,chargeLoop	;  not done yet

;*
;* done charging -- wait for removal
;*

trickle
	clrb	amber			;battery full -- amber off
	clrb	power
	clrb	red
	setb	green 			;green LED on
	call	realityWait

	setb	power
	mov	msCounter,#20
	call	milliseconds		;blip the battery
	clrb	power
	mov	msCounter,#5
	call	milliseconds
	call	measureVoltage
                              
	call	realityCheck		;check reality
	jnb	justRight,freezeFire    ;  temperature bad
	jnb	batPresent,batWait	;  battery removed
	jnb	batOk,batBad		;  battery bad
	jb	batLow,batWait		;  battery went low
	
	jmp	trickle			;wait for removal
	
;*
;* battery was bad
;*	
	
batBad  
	clrb	amber			;battery bad -- amber off
	clrb	green
	setb	red			;red LED on
	call	realityWait
	call	realityCheck		;check reality
	jnb	justRight,freezeFire    ;  temperature bad
	jb	batOk,startCharge	;  battery ok
	setb	amber                   ;still bad
	setb	power			;give it a shot
	call	second
	clrb	power
	jmp	batBad			;try again
	
;*
;* temperature out of range
;*	
	
freezeFire
	clrb	amber
	clrb	power			;off with the power
	clrb	green
	setb	red			
	mov	tsCounter,#5
	call	tenthSeconds
	clrb	red
	mov	tsCounter,#5            ;blink the red LED
	call	tenthSeconds
	call	measureVoltage		
	call	realityCheck            ;taste the porridge
	call	blipResult		;show the temperature
	jnb	justRight,freezeFire	;  still hot or cold
	jnb	batpresent,batWait	;  battery removed
	jmp	freezeFire
	
	
;*
;* delay for a few half seconds
;*

realityWait
	mov	rwCounter,#CHARGEDELAY
realityWaitLoop
	call	excite
	call	relax
	call	excite
	call	relax
	call	excite
	call	relax
	call	excite
	call	relax
	call	excite

	clrb	power	
	mov	msCounter,#5
	call	milliseconds	
	call	measureVoltage
	
	snb	amber			;was power on ?
	setb	power			;  yes, turn it back on

	cjne	rwCounter,#12,rw2
	call	measureTemp
	call	realTemperature		;show the temperature
	
rw2	cjne	rwCounter,#24,rwdone	
	call	showDerivative		;show the derivative
	
rwdone
	csb	result,#UPPERVOLTAGE	;battery present ?		
	ret                    		;  early return if battery removed
	djnz	rwCounter,realityWaitLoop
	ret
	
excite
	snb	amber			;was power on ?
	setb	power			;  yes, turn it back on
	mov	msCounter,#37
	call	milliseconds
	ret
	
relax
;	clrb	power
	mov	msCounter,#4
	call	milliseconds
	ret
	
;*
;* measure the voltage
;*

measureVoltage
	mov	ADCON0,#01010001b 	;fosc/8,AIN2,ADON
	call	getResult
	mov	newVoltage,result
	mov	newVoltage+1,result+1	
	call	updateSmoothVoltage
	ret
	
	
getResult	
	clr	adCounter		;256 measurements	
	clr	result			;set up for new measurement
	clr	result+1
:again	
	mov	usCounter,#4		;delay 16 us
	call	microseconds
	setb	GO_DONE			;start an A/D conversion
:adWait	jb	GO_DONE,:adWait		;wait for completion
	clrb	ADIF			;clear interrupt bit
	add	result+1,ADRES		;16-bit add
	snc				;carry ?
	inc	result			;  yes, bump msb
	clrwdt
	djnz	adCounter,:again
	ret
	
;*
;* measure the temperature
;*

measureTemp
	mov	ADCON0,#01011001b 	;fosc/8,AIN3,ADON
	call	getResult
	mov	temperature,result
	mov	temperature+1,result+1
	ret
	
;*
;* measure the voltage, calculate the derivative and set the flags
;*	
	
realityCheck
	call	calculateDerivative
	clrb	batFull
	jb	signBit,setBatFull	    ;  derivative < 0
	cjne	derivative,#0,batNotFull    ;  derivative large
	cjbe	derivative+1,#8,setBatFull  ;  derivative very small
	cjbe	newVoltage,#FASTEXITVOLTAGE,batNotFull
	cjbe	derivative+1,#16,setBatFull ;  derivative small
	cjbe	newVoltage,#FASTEXITVOLTAGE+5,batNotFull
	cjbe	derivative+1,#32,setBatFull
	cjbe	newVoltage,#FASTEXITVOLTAGE+10,batNotFull
	cjbe	derivative+1,#64,setBatFull

	cja	newVoltage,#225,setBatFull  ;  voltage > 9.9V
	jmp	batNotFull

setBatFull
	setb	batFull
batNotFull
	clrb	batPresent
	clrb	batOk
	clrb	batLow
	csae	newVoltage,#UPPERVOLTAGE;less than 10.0V ?
	setb	batPresent		;  yes, battery present
	csb	newVoltage,#51		;greater than 6.5V ???
	setb	batOk			;  yes, battery O.K.
	csbe	newVoltage,#138		;less than 8.2V ?
	jmp	Goldilocks		;  no
	setb	batLow			;  yes, battery low ...
	clrb	batFull			;  ... and it's not full
Goldilocks
	clrb	justRight
	call	measureTemp		;taste the porridge
	cjae	temperature,#163,tooHot	;112F
	cjbe	temperature,#141,tooCold
	setb	justRight
	
tooHot
tooCold
;*	call	blipVoltage
	call	realVoltage		;show our reading
	ret
	
;*
;* calculate derivative from voltage and result
;*

calculateDerivative
	mov	oldVoltage,voltage 	;set up for derivative
	mov	oldVoltage+1,voltage+1
	                              
;*	call	outputSmoothVoltage	                              
	call	getSmoothVoltage

	mov	derivative,voltage
	mov	derivative+1,voltage+1
	sub	derivative+1,oldVoltage+1 ;16-bit subtract
	sc				;borrow ?
	dec	derivative		;  yes, dec msb
	sub	derivative,oldVoltage
	
	ret
	
;*
;* smooth voltage management routines
;*

updateSmoothVoltage
	add	smoothVoltage+2,newVoltage+1
	jnc	:usv1
	add	smoothVoltage+1,#1		;this can overflow (!)
	snc
	inc	smoothVoltage
:usv1	add	smoothVoltage+1,newVoltage
	snc
	inc	smoothVoltage
	ret

getSmoothVoltage
	mov	tempCounter,#7
	cjne	rwCounter,#0,fakeUpdate		;realityWait terminated early
	cje	smoothVoltage,#0,doUpdate	;only one sample
	
smoothVoltageLoop
	clc
	rr	smoothVoltage
	rr	smoothVoltage+1
	rr	smoothVoltage+2
	djnz	tempCounter,smoothVoltageLoop

doUpdate	
	mov	voltage,smoothVoltage+1
	mov	voltage+1,smoothVoltage+2
	call	clearSmoothVoltage
	ret
	
fakeUpdate
	mov	voltage,newVoltage
	mov	voltage+1,newVoltage+1
	call	clearSmoothVoltage
	ret	
	
clearSmoothVoltage
	clr	smoothVoltage
	clr	smoothVoltage+1
	clr	smoothVoltage+2
	ret				

;*
;* delay for a few seconds
;*
seconds
	call	second
	djnz	seCounter,seconds
	ret
;*
;* delay for a second
;*
second
	mov	tsCounter,#10
;*
;* delay for a few tenth seconds
;*
tenthSeconds	
	call	tenthSecond
	djnz	tsCounter,tenthSeconds
	ret	
	
;*
;* delay for a tenth of a second
;*
tenthSecond
	mov	msCounter,#100
;*
;* delay for a few milliseconds
;*
milliseconds
	call	millisecond
	djnz	msCounter,milliseconds
	ret	
;*
;* delay for a millisecond
;*
millisecond
	mov	usCounter,#249		;remember call and return
microseconds	
	clrwdt
	djnz	usCounter,microseconds	;4 cycles per loop
	ret

;*
;* show the results of an A/D conversion by sending a pulse train
;*

blipResult
	clr	blipCounter
	mov	blipCounter+1,result
	jmp	doBlips
	
;*
;* show the derivative by sending a pulse train
;*

blipDerivative
	mov	blipCounter,derivative
	mov	blipCounter+1,derivative+1
	jmp	doBlips

;*
;* calculate the voltage in tenths of a millivolt and blip it out
;*
;* volts = voltage * 50000 / 65536 + 55000 (tenth millivolts)
;*

realVoltage

	jmp	industrialVoltage
	
	mov	blipcounter,#195	;50000
	mov	blipCounter+1,#80
	mov	tempCounter,#16		;blipCounter = 
	mov	multiplier,blipCounter  ;  (result * blipCounter) / 65536
	mov	multiplier+1,blipCounter+1
	clr	blipCounter
	clr	blipCounter+1
:rvLoop	rr	multiplier
	rr	multiplier+1
	jnc	:noadd
	add	blipCounter+1,voltage+1
	snc
	inc	blipCounter
	add	blipCounter,voltage
:noadd	rr	blipCounter
	rr	blipCounter+1
	djnz	tempCounter,:rvLoop
	clrb	highOrderBlipBit
	add	blipCounter+1,#216	;55000
	snc
	inc	blipCounter
	add	blipCounter,#214
	snc
	setb	highOrderBlipBit	;17 bits of precision
	jmp	doBlips
	
;*
;* industrial version of real voltage (4-digits)
;*

industrialVoltage
	mov	blipcounter,#19		;5000
	mov	blipCounter+1,#136
	mov	tempCounter,#16		;blipCounter = 
	mov	multiplier,blipCounter  ;  (result * blipCounter) / 65536
	mov	multiplier+1,blipCounter+1
	clr	blipCounter
	clr	blipCounter+1
:rvLoop	rr	multiplier
	rr	multiplier+1
	jnc	:noadd
	add	blipCounter+1,voltage+1
	snc
	inc	blipCounter
	add	blipCounter,voltage
:noadd	rr	blipCounter
	rr	blipCounter+1
	djnz	tempCounter,:rvLoop
	clrb	highOrderBlipBit
	add	blipCounter+1,#124	;5500
	snc
	inc	blipCounter
	add	blipCounter,#21
	snc
	setb	highOrderBlipBit	;17 bits of precision
	jmp	doBlips
	

;*	
;* calculate temperature
;*

realTemperature
	mov	blipcounter,#3		;900
	mov	blipCounter+1,#132
	mov	tempCounter,#16		;blipCounter = 
	mov	multiplier,blipCounter  ;  (result * blipCounter) / 65536
	mov	multiplier+1,blipCounter+1
	clr	blipCounter
	clr	blipCounter+1
:rvLoop	rr	multiplier
	rr	multiplier+1
	jnc	:noadd
	add	blipCounter+1,temperature+1
	snc
	inc	blipCounter
	add	blipCounter,temperature
:noadd	rr	blipCounter
	rr	blipCounter+1
	djnz	tempCounter,:rvLoop
	clrb	highOrderBlipBit
	
	sub	blipCounter+1,#204	;-460
	sc
	dec	blipCounter
	sub	blipCounter,#1		
	jmp	doBlips

;*
;* misc display routines
;*

showDerivative
	mov	blipCounter,derivative
	mov	blipCounter+1,derivative+1
	jmp	doBlips
	
;*
;* show voltage by sending a pulse train on the pulse line
;*

blipVoltage
	mov	blipCounter,voltage	;output the voltage on the pulse line
	mov	blipCounter+1,voltage+1
doBlips
	
	ret				;* ret in industrial version *

	call	clearDisplay
doBlipsAgain	
	cje	blipCounter+1,#0,doUpperBlips
showBlip
	setb	pulse
	clrb	pulse	
	djnz	blipCounter+1,showBlip
	
doUpperBlips	
	cje	blipCounter,#0,blipDone
	
showUpperBlips
	mov	blipCounter+1,#32	;256 blips ...
upperBlipLoop        			; ... 8 at a time
	setb	pulse
	clrb	pulse
	setb	pulse
	clrb	pulse
	setb	pulse
	clrb	pulse
	setb	pulse
	clrb	pulse
	setb	pulse
	clrb	pulse
	setb	pulse
	clrb	pulse
	setb	pulse
	clrb	pulse
	setb	pulse
	clrb	pulse
	clrwdt
	djnz	blipCounter+1,upperBlipLoop
	djnz	blipCounter,showUpperBlips
	
blipDone
	jnb	highOrderBlipBit,blipReallyDone
	clrb	highOrderBlipBit	;extra high order bit set ...
	setb	pulse			; ... this calls for 65536 blips ...
	clrb	pulse			; ... starting with 1 blip ...
	mov	blipCounter,#255	; ... followed with 65535 more 
	mov	blipCounter+1,#255
	jmp	doBlipsAgain
	
blipReallyDone	
	ret
	
;*
;* clear the display
;*
	
clearDisplay
	clrb	trigger
	call	millisecond
	setb	trigger
	call	millisecond
	ret
