/*
 * Copyright (C) 2008 The Android Open Source Project
 * All rights reserved.
 *
 * Copyright (c) 2009-2011, Code Aurora Forum. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in
 *    the documentation and/or other materials provided with the
 *    distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
 * OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
 * AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
 * OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <machine/cpu-features.h>
#include <machine/asm.h>

#if( defined(SCORPION_NEON_OPTIMIZATION) || defined(CORTEX_CACHE_LINE_32))
	.code 32
	.align 8
	.global memset
	.type memset, %function

	.global bzero
	.type bzero, %function

bzero:
	mov             r2, r1
	mov             r1, #0	
memset:
	push            {r0}

	cmp             r2, #6
	bgt             .Lmemset_gt6
	cmp             r2, #0
	beq             .Lmemset_smallcopy_done
.Lmemset_smallcopy_loop:
	strb            r1, [r0], #1
	subs            r2, r2, #1
	bne             .Lmemset_smallcopy_loop
.Lmemset_smallcopy_done:
	pop             {r0}
	bx              lr

.Lmemset_gt6:
	vdup.8		q0, r1
	vmov		r1, s0

	/*
	 * Decide where to route for the maximum copy sizes.
	 */
	cmp             r2, #4
	blt             .Lmemset_lt4
	cmp             r2, #16
	blt             .Lmemset_lt16
	vmov            q1, q0
	cmp             r2, #128
	blt             .Lmemset_32
.Lmemset_128:
	mov             r12, r2, lsr #7
.Lmemset_128_loop:
	vst1.32         {q0, q1}, [r0]!
	vst1.32         {q0, q1}, [r0]!
	vst1.32         {q0, q1}, [r0]!
	vst1.32         {q0, q1}, [r0]!
	subs            r12, r12, #1
	bne             .Lmemset_128_loop
	ands            r2, r2, #0x7f
	beq             .Lmemset_end
.Lmemset_32:
	movs             r12, r2, lsr #5
	beq              .Lmemset_lt32
.Lmemset_32_loop:
	subs            r12, r12, #1
	vst1.32         {q0, q1}, [r0]!
	bne             .Lmemset_32_loop
	ands            r2, r2, #0x1f
	beq             .Lmemset_end
.Lmemset_lt32:
	cmp             r2, #16
	blt             .Lmemset_lt16
	vst1.64         {q0}, [r0]!
	subs            r2, r2, #16
	beq             .Lmemset_end
.Lmemset_lt16:
	movs            r12, r2, lsl #29
	strcs           r1, [r0], #4
	strcs           r1, [r0], #4
	strmi           r1, [r0], #4
.Lmemset_lt4:
	movs            r2, r2, lsl #31
	strcsh          r1, [r0], #2
	strmib          r1, [r0]
.Lmemset_end:
	pop             {r0}
	bx		lr

	.end
#else   /* !(SCORPION_NEON_OPTIMIZATION || CORTEX_CACHE_LINE_32) */

		/*
		 * Optimized memset() for ARM.
         *
         * memset() returns its first argument.
		 */

#if defined(__ARM_NEON__)
    .fpu    neon
#endif

ENTRY(bzero)
        mov     r2, r1
        mov     r1, #0
END(bzero)

ENTRY(memset)
#if defined(__ARM_NEON__)

#ifdef  NEON_MEMSET_DIVIDER
        cmp         r2, #NEON_MEMSET_DIVIDER
        bhi         11f
#endif
        .save       {r0}
        stmfd       sp!, {r0}

        vdup.8      q0, r1

#ifndef NEON_UNALIGNED_ACCESS
        /* do we have at least 16-bytes to write (needed for alignment below) */
        cmp         r2, #16
        blo         3f

        /* align destination to 16 bytes for the write-buffer */
        rsb         r3, r0, #0
        ands        r3, r3, #0xF
        beq         2f

        /* write up to 15-bytes (count in r3) */
        sub         r2, r2, r3
        movs        ip, r3, lsl #31
        strmib      r1, [r0], #1
        strcsb      r1, [r0], #1
        strcsb      r1, [r0], #1
        movs        ip, r3, lsl #29
        bge         1f

        // writes 4 bytes, 32-bits aligned
        vst1.32     {d0[0]}, [r0, :32]!
1:      bcc         2f

        // writes 8 bytes, 64-bits aligned
        vst1.8      {d0}, [r0, :64]!
2:
#endif
        /* make sure we have at least 32 bytes to write */
        subs        r2, r2, #32
        blo         2f
        vmov        q1, q0

1:      /* The main loop writes 32 bytes at a time */
        subs        r2, r2, #32
#ifndef NEON_UNALIGNED_ACCESS
        vst1.8      {d0 - d3}, [r0, :128]!
#else
        vst1.8      {d0 - d3}, [r0]!
#endif
        bhs         1b

2:      /* less than 32 left */
        add         r2, r2, #32
        tst         r2, #0x10
        beq         3f

        // writes 16 bytes, 128-bits aligned
#ifndef NEON_UNALIGNED_ACCESS
        vst1.8      {d0, d1}, [r0, :128]!
#else
        vst1.8      {d0, d1}, [r0]!
#endif
3:      /* write up to 15-bytes (count in r2) */
        movs        ip, r2, lsl #29
        bcc         1f
        vst1.8      {d0}, [r0]!
1:      bge         2f
        vst1.32     {d0[0]}, [r0]!
2:      movs        ip, r2, lsl #31
        strmib      r1, [r0], #1
        strcsb      r1, [r0], #1
        strcsb      r1, [r0], #1
        ldmfd       sp!, {r0}
        bx          lr
11:
#endif

        /*
         * Optimized memset() for ARM.
         *
         * memset() returns its first argument.
         */

		/* compute the offset to align the destination
		 * offset = (4-(src&3))&3 = -src & 3
		 */

        .save       {r0, r4-r7, lr}
		stmfd		sp!, {r0, r4-r7, lr}
		rsb			r3, r0, #0
		ands		r3, r3, #3
        cmp         r3, r2
        movhi       r3, r2

        /* splat r1 */
        mov         r1, r1, lsl #24
        orr         r1, r1, r1, lsr #8
        orr         r1, r1, r1, lsr #16

		movs		r12, r3, lsl #31
		strcsb		r1, [r0], #1    /* can't use strh (alignment unknown) */
		strcsb		r1, [r0], #1
		strmib		r1, [r0], #1
		subs		r2, r2, r3
        ldmlsfd     sp!, {r0, r4-r7, lr}   /* return */
        bxls        lr

		/* align the destination to a cache-line */
        mov         r12, r1
        mov         lr, r1
        mov         r4, r1
        mov         r5, r1
        mov         r6, r1
        mov         r7, r1

		rsb         r3, r0, #0
		ands		r3, r3, #0x1C
		beq         3f
		cmp         r3, r2
		andhi		r3, r2, #0x1C
		sub         r2, r2, r3

		/* conditionally writes 0 to 7 words (length in r3) */
		movs		r3, r3, lsl #28
		stmcsia		r0!, {r1, lr}
		stmcsia		r0!, {r1, lr}
		stmmiia		r0!, {r1, lr}
		movs		r3, r3, lsl #2
        strcs       r1, [r0], #4

3:
        subs        r2, r2, #32
        mov         r3, r1
        bmi         2f
1:      subs        r2, r2, #32
        stmia		r0!, {r1,r3,r4,r5,r6,r7,r12,lr}
        bhs         1b
2:      add         r2, r2, #32

		/* conditionally stores 0 to 31 bytes */
		movs		r2, r2, lsl #28
		stmcsia		r0!, {r1,r3,r12,lr}
		stmmiia		r0!, {r1, lr}
		movs		r2, r2, lsl #2
        strcs       r1, [r0], #4
		strmih		r1, [r0], #2
		movs		r2, r2, lsl #2
		strcsb		r1, [r0]
        ldmfd		sp!, {r0, r4-r7, lr}
        bx          lr
END(memset)
    
#endif  /* SCORPION_NEON_OPTIMIZATION */
