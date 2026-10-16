; MRPGCMAP raw ARM scan. Candidate functions, not validated boundaries.

; candidate 0x500 callers=1 prologue=True
00000500: push     {r4, r5, r6, lr}
00000504: mov      r4, r3
00000508: mov      r5, r2
0000050c: mov      r6, #0
00000510: orrs     ip, r1, r0, lsr #31
00000514: bne      #0x530
00000518: tst      r0, r0
0000051c: beq      #0x838
00000520: clz      r6, r0
00000524: sub      r6, r6, #1
00000528: lsl      ip, r0, r6
0000052c: b        #0x5d4
00000530: tst      r1, #128, #8
00000534: bne      #0x554
00000538: clz      r6, r1
0000053c: sub      r6, r6, #1
00000540: lsl      ip, r1, r6
00000544: rsb      r1, r6, #0x20
00000548: orr      ip, ip, r0, lsr r1
0000054c: lsl      lr, r0, r6
00000550: b        #0x6e4
00000554: mov      ip, r1
00000558: mov      lr, r0
0000055c: b        #0x818
00000560: andeq    r4, r0, r8, ror r7
00000564: mov      r0, #2
00000568: mov      r1, #2
0000056c: b        #0x844
00000570: andeq    r4, r0, r8, ror r7
00000574: push     {r4, r5, r6, lr}
00000578: mov      r4, r1
0000057c: mov      r5, r0
00000580: mov      r6, #0
00000584: orrs     ip, r3, r2, lsr #31
00000588: bne      #0x5a4
0000058c: tst      r2, r2
00000590: beq      #0x838
00000594: clz      r6, r2
00000598: sub      r6, r6, #1
0000059c: lsl      ip, r2, r6
000005a0: b        #0x5d4
000005a4: tst      r3, #128, #8
000005a8: bne      #0x5c8
000005ac: clz      r6, r3
000005b0: sub      r6, r6, #1
000005b4: lsl      ip, r3, r6
000005b8: rsb      r3, r6, #0x20
000005bc: orr      ip, ip, r2, lsr r3
000005c0: lsl      lr, r2, r6
000005c4: b        #0x6e4
000005c8: mov      ip, r3
000005cc: mov      lr, r2
000005d0: b        #0x818
000005d4: mov      r3, #0
000005d8: cmp      r4, ip, lsl #1
000005dc: subhs    r4, r4, ip, lsl #1
000005e0: addhs    r3, r3, #2
000005e4: cmp      r4, ip
000005e8: subhs    r4, r4, ip
000005ec: adcs     r3, r3, #0
000005f0: rsb      ip, ip, #0
000005f4: add      r2, r6, #0x20
000005f8: cmp      r2, #0x20
000005fc: blo      #0x610
00000600: orrs     r0, r4, r5, lsr #30
00000604: moveq    r4, r5
00000608: moveq    r5, #0
0000060c: subeq    r2, r2, #0x20
00000610: clz      r1, r4
00000614: subs     r1, r1, #2
00000618: movmi    r1, #0
0000061c: cmp      r1, r2
00000620: movhi    r1, r2
00000624: lsl      r4, r4, r1
00000628: rsb      r0, r1, #0x20
0000062c: orr      r4, r4, r5, lsr r0
00000630: lsl      r5, r5, r1
00000634: sub      r2, r2, r1
00000638: cmp      r2, #1
0000063c: blo      #0x6c4
00000640: sub      r2, r2, #1
00000644: and      r0, r2, #7
00000648: eor      r0, r0, #7
0000064c: adds     r0, r0, r0, lsl #1
00000650: add      pc, pc, r0, lsl #2
00000654: mov      r0, r0
00000658: adcs     r5, r5, r5
0000065c: adcs     r4, ip, r4, lsl #1
00000660: rsblo    r4, ip, r4
00000664: adcs     r5, r5, r5
00000668: adcs     r4, ip, r4, lsl #1
0000066c: rsblo    r4, ip, r4
00000670: adcs     r5, r5, r5
00000674: adcs     r4, ip, r4, lsl #1
00000678: rsblo    r4, ip, r4
0000067c: adcs     r5, r5, r5
00000680: adcs     r4, ip, r4, lsl #1
00000684: rsblo    r4, ip, r4
00000688: adcs     r5, r5, r5
0000068c: adcs     r4, ip, r4, lsl #1
00000690: rsblo    r4, ip, r4
00000694: adcs     r5, r5, r5
00000698: adcs     r4, ip, r4, lsl #1
0000069c: rsblo    r4, ip, r4
000006a0: adcs     r5, r5, r5
000006a4: adcs     r4, ip, r4, lsl #1
000006a8: rsblo    r4, ip, r4
000006ac: adcs     r5, r5, r5
000006b0: adcs     r4, ip, r4, lsl #1
000006b4: rsblo    r4, ip, r4
000006b8: sub      r2, r2, #8
000006bc: tst      r2, r2
000006c0: bpl      #0x658
000006c4: lsr      r2, r4, r6
000006c8: bic      r4, r4, r2, lsl r6
000006cc: adcs     r0, r5, r5
000006d0: adc      r1, r4, r4
000006d4: add      r1, r1, r3, lsl r6
000006d8: mov      r3, #0
000006dc: pop      {r4, r5, r6, lr}
000006e0: bx       lr

; candidate 0x8 callers=0 prologue=True
00000008: push     {r4, lr}
0000000c: mov      r4, r0
00000010: mov      r0, r4
00000014: blx      #0x2cd64
00000018: pop      {r4, pc}

; candidate 0x80 callers=0 prologue=True
00000080: push     {r4, r5, r6, lr}
00000084: movs     r6, r1
00000088: bpl      #0x94
0000008c: rsbs     r0, r0, #0
00000090: rsc      r1, r1, #0
00000094: subs     r2, r0, #0xa
00000098: sbcs     r3, r1, #0
0000009c: lsr      lr, r0, #2
000000a0: orr      lr, lr, r1, lsl #30
000000a4: subs     r0, r0, lr
000000a8: sbc      r1, r1, r1, lsr #2
000000ac: lsr      lr, r0, #4
000000b0: orr      lr, lr, r1, lsl #28
000000b4: adds     r0, r0, lr
000000b8: adc      r1, r1, r1, lsr #4
000000bc: lsr      lr, r0, #8
000000c0: orr      lr, lr, r1, lsl #24
000000c4: adds     r0, r0, lr
000000c8: adc      r1, r1, r1, lsr #8
000000cc: lsr      lr, r0, #0x10
000000d0: orr      lr, lr, r1, lsl #16
000000d4: adds     r0, r0, lr
000000d8: adc      r1, r1, r1, lsr #16
000000dc: adds     r0, r0, r1
000000e0: adc      r1, r1, #0
000000e4: lsr      r0, r0, #3
000000e8: orr      r0, r0, r1, lsl #29
000000ec: lsr      r1, r1, #3
000000f0: lsl      r4, r1, #2
000000f4: orr      r4, r4, r0, lsr #30
000000f8: adds     r5, r0, r0, lsl #2
000000fc: adc      r4, r4, r1
00000100: adds     r5, r5, r5
00000104: adc      r4, r4, r4
00000108: subs     r2, r2, r5
0000010c: sbcs     r3, r3, r4
00000110: mov      r3, #0
00000114: addmi    r2, r2, #0xa
00000118: bmi      #0x124
0000011c: adds     r0, r0, #1
00000120: adc      r1, r1, #0
00000124: tst      r6, r6
00000128: poppl    {r4, r5, r6, lr}
0000012c: bxpl     lr
00000130: rsbs     r0, r0, #0
00000134: rsc      r1, r1, #0
00000138: rsbs     r2, r2, #0
0000013c: rsc      r3, r3, #0
00000140: pop      {r4, r5, r6, lr}
00000144: bx       lr

; candidate 0x178 callers=0 prologue=True
00000178: push     {r4, lr}
0000017c: asrs     r4, r3, #1
00000180: eor      r4, r4, r1, lsr #1
00000184: bpl      #0x190
00000188: rsbs     r2, r2, #0
0000018c: rsc      r3, r3, #0
00000190: tst      r1, r1
00000194: bpl      #0x1a0
00000198: rsbs     r0, r0, #0
0000019c: rsc      r1, r1, #0
000001a0: bl       #0x500
000001a4: tst      r4, #64, #8
000001a8: beq      #0x1b4
000001ac: rsbs     r0, r0, #0
000001b0: rsc      r1, r1, #0
000001b4: tst      r4, #128, #8
000001b8: beq      #0x1c4
000001bc: rsbs     r2, r2, #0
000001c0: rsc      r3, r3, #0
000001c4: pop      {r4, lr}
000001c8: bx       lr

; candidate 0x1e4 callers=0 prologue=True
000001e4: stmdb    sp!, {lr}
000001e8: mov      r3, r2
000001ec: mov      ip, r2
000001f0: mov      lr, r2
000001f4: subs     r1, r1, #0x20
000001f8: stmhs    r0!, {r2, r3, ip, lr}
000001fc: stmhs    r0!, {r2, r3, ip, lr}
00000200: subshs   r1, r1, #0x20
00000204: bhs      #0x1f8
00000208: lsls     r1, r1, #0x1c
0000020c: stmhs    r0!, {r2, r3, ip, lr}
00000210: stmmi    r0!, {r2, r3}
00000214: ldm      sp!, {lr}
00000218: lsls     r1, r1, #2
0000021c: strhs    r2, [r0], #4
00000220: bxeq     lr
00000224: strbmi   r2, [r0], #1
00000228: strbmi   r2, [r0], #1
0000022c: tst      r1, #64, #8
00000230: strbne   r2, [r0], #1
00000234: bx       lr

; candidate 0x2f4 callers=0 prologue=True
000002f4: push     {r4, lr}
000002f8: subs     r2, r2, #0x20
000002fc: blo      #0x318
00000300: ldmhs    r1!, {r3, r4, ip, lr}
00000304: stmhs    r0!, {r3, r4, ip, lr}
00000308: ldmhs    r1!, {r3, r4, ip, lr}
0000030c: stmhs    r0!, {r3, r4, ip, lr}
00000310: subshs   r2, r2, #0x20
00000314: bhs      #0x300
00000318: lsls     ip, r2, #0x1c
0000031c: ldmhs    r1!, {r3, r4, ip, lr}
00000320: stmhs    r0!, {r3, r4, ip, lr}
00000324: ldmmi    r1!, {r3, r4}
00000328: stmmi    r0!, {r3, r4}
0000032c: pop      {r4, lr}
00000330: lsls     ip, r2, #0x1e
00000334: ldrhs    r3, [r1], #4
00000338: strhs    r3, [r0], #4
0000033c: bxeq     lr
00000340: lsls     r2, r2, #0x1f
00000344: ldrbmi   r2, [r1], #1
00000348: ldrbhs   r3, [r1], #1
0000034c: ldrbhs   ip, [r1], #1
00000350: strbmi   r2, [r0], #1
00000354: strbhs   r3, [r0], #1
00000358: strbhs   ip, [r0], #1
0000035c: bx       lr

; candidate 0x574 callers=0 prologue=True
00000574: push     {r4, r5, r6, lr}
00000578: mov      r4, r1
0000057c: mov      r5, r0
00000580: mov      r6, #0
00000584: orrs     ip, r3, r2, lsr #31
00000588: bne      #0x5a4
0000058c: tst      r2, r2
00000590: beq      #0x838
00000594: clz      r6, r2
00000598: sub      r6, r6, #1
0000059c: lsl      ip, r2, r6
000005a0: b        #0x5d4
000005a4: tst      r3, #128, #8
000005a8: bne      #0x5c8
000005ac: clz      r6, r3
000005b0: sub      r6, r6, #1
000005b4: lsl      ip, r3, r6
000005b8: rsb      r3, r6, #0x20
000005bc: orr      ip, ip, r2, lsr r3
000005c0: lsl      lr, r2, r6
000005c4: b        #0x6e4
000005c8: mov      ip, r3
000005cc: mov      lr, r2
000005d0: b        #0x818
000005d4: mov      r3, #0
000005d8: cmp      r4, ip, lsl #1
000005dc: subhs    r4, r4, ip, lsl #1
000005e0: addhs    r3, r3, #2
000005e4: cmp      r4, ip
000005e8: subhs    r4, r4, ip
000005ec: adcs     r3, r3, #0
000005f0: rsb      ip, ip, #0
000005f4: add      r2, r6, #0x20
000005f8: cmp      r2, #0x20
000005fc: blo      #0x610
00000600: orrs     r0, r4, r5, lsr #30
00000604: moveq    r4, r5
00000608: moveq    r5, #0
0000060c: subeq    r2, r2, #0x20
00000610: clz      r1, r4
00000614: subs     r1, r1, #2
00000618: movmi    r1, #0
0000061c: cmp      r1, r2
00000620: movhi    r1, r2
00000624: lsl      r4, r4, r1
00000628: rsb      r0, r1, #0x20
0000062c: orr      r4, r4, r5, lsr r0
00000630: lsl      r5, r5, r1
00000634: sub      r2, r2, r1
00000638: cmp      r2, #1
0000063c: blo      #0x6c4
00000640: sub      r2, r2, #1
00000644: and      r0, r2, #7
00000648: eor      r0, r0, #7
0000064c: adds     r0, r0, r0, lsl #1
00000650: add      pc, pc, r0, lsl #2
00000654: mov      r0, r0
00000658: adcs     r5, r5, r5
0000065c: adcs     r4, ip, r4, lsl #1
00000660: rsblo    r4, ip, r4
00000664: adcs     r5, r5, r5
00000668: adcs     r4, ip, r4, lsl #1
0000066c: rsblo    r4, ip, r4
00000670: adcs     r5, r5, r5
00000674: adcs     r4, ip, r4, lsl #1
00000678: rsblo    r4, ip, r4
0000067c: adcs     r5, r5, r5
00000680: adcs     r4, ip, r4, lsl #1
00000684: rsblo    r4, ip, r4
00000688: adcs     r5, r5, r5
0000068c: adcs     r4, ip, r4, lsl #1
00000690: rsblo    r4, ip, r4
00000694: adcs     r5, r5, r5
00000698: adcs     r4, ip, r4, lsl #1
0000069c: rsblo    r4, ip, r4
000006a0: adcs     r5, r5, r5
000006a4: adcs     r4, ip, r4, lsl #1
000006a8: rsblo    r4, ip, r4
000006ac: adcs     r5, r5, r5
000006b0: adcs     r4, ip, r4, lsl #1
000006b4: rsblo    r4, ip, r4
000006b8: sub      r2, r2, #8
000006bc: tst      r2, r2
000006c0: bpl      #0x658
000006c4: lsr      r2, r4, r6
000006c8: bic      r4, r4, r2, lsl r6
000006cc: adcs     r0, r5, r5
000006d0: adc      r1, r4, r4
000006d4: add      r1, r1, r3, lsl r6
000006d8: mov      r3, #0
000006dc: pop      {r4, r5, r6, lr}
000006e0: bx       lr

; candidate 0x844 callers=0 prologue=True
00000844: push     {r4, lr}
00000848: blx      #0x860
0000084c: cmp      r0, #0
00000850: popeq    {r4, lr}
00000854: bxeq     lr
00000858: pop      {r4, lr}
0000085c: b        #0x8a8
00000860: mcrmi    p5, #0, fp, c14, c0, #3
00000864: .byte    0x0d, 0x1c, 0x01, 0x1c
00000868: ldrbtmi  r1, [lr], #-0xc04
0000086c: .byte    0x30, 0x1c, 0x00, 0xf0
00000870: .byte    0x00, 0xf8, 0x02, 0x1c
00000874: strhle   r4, [r6, -r0]
00000878: stcne    p12, c1, [r0], #-0xa4
0000087c: .byte    0x00, 0xf0, 0x20, 0xf8
00000880: .byte    0x70, 0xbc, 0x08, 0xbc
00000884: stmdami  r6, {r3, r4, r8, sb, sl, lr}
00000888: addmi    r4, r2, #120, #8
0000088c: stcne    p0, c13, [sb], #-0xc
00000890: .byte    0x20, 0x1c, 0xff, 0xf7
00000894: andhs    pc, r0, r5, asr #23
00000898: strdeq   lr, pc, [r0], -r2
0000089c: .byte    0x99, 0xf7, 0xf7, 0xff
000008a0: .byte    0x79, 0xf7, 0xf7, 0xff
000008a4: andeq    r4, r0, r8, ror r7
000008a8: mov      r0, #0x18
000008ac: ldr      r1, [pc, #8]
000008b0: svc      #0x123456
000008b4: bx       lr

; candidate 0x214c callers=0 prologue=True
0000214c: stmdb    sl, {r1, r2, r3, r4, r5, r6, r7, r8, sb, sl, ip, sp, lr, pc}
00002150: strne    r0, [r0], -r0, lsl #12
00002154: .byte    0x20, 0x71, 0x61, 0x71
00002158: .byte    0x00, 0x21, 0xa1, 0x71
0000215c: strbtpl  r2, [r1], r1, lsl #6
00002160: blle     #0x92b88
00002164: andlo    r1, r1, r0, asr #20
00002168: ldclt    p1, c7, [r0, #-0x280]
0000216c: muleq    r0, ip, r2
00002170: .byte    0x10, 0xb5, 0x17, 0x4c
00002174: strbmi   r2, [ip], #-0x100
00002178: strbvs   r6, [r1, #-0x520]!
0000217c: andle    r2, fp, r0, lsl r8
00002180: andsle   r2, ip, r1, lsl r8
00002184: andsle   r2, lr, r2, lsl r8
00002188: .byte    0x13, 0x28, 0x02, 0xd1
0000218c: .byte    0x11, 0x48, 0x16, 0xf0
00002190: .byte    0x59, 0xfc, 0x16, 0xf0
00002194: ldclt    p15, c15, [r0, #-0x1cc]
00002198: .byte    0x0f, 0x48, 0x16, 0xf0
0000219c: movwhs   pc, #0x8d45
000021a0: andhs    r5, r1, r1, ror #13
000021a4: andle    r2, r0, r0, lsl #18
000021a8: .byte    0x00, 0x20, 0x16, 0xf0
000021ac: bvs      #0xff8411a8
000021b0: .byte    0x3a, 0x23, 0xc0, 0x56
000021b4: blx      #0xffe3e216
000021b8: ldc2     p0, c15, [ip], {0x16}
000021bc: stmdami  r7, {r0, r3, r5, r6, r7, r8, sb, sl, sp, lr, pc}
000021c0: mcrr2    p0, #1, pc, r0, c6
000021c4: stmdami  r6, {r0, r2, r5, r6, r7, r8, sb, sl, sp, lr, pc}
000021c8: ldc2     p0, c15, [ip], #-0x58
000021cc: andeq    lr, r0, r1, ror #15
000021d0: muleq    r0, ip, r2
000021d4: streq    r0, [r0], -r0, lsr #32
000021d8: .byte    0x1d, 0x00, 0x00, 0x06
000021dc: .byte    0x1e, 0x00, 0x00, 0x06
000021e0: .byte    0x1f, 0x00, 0x00, 0x06
000021e4: .byte    0x70, 0xb5, 0x09, 0x4c
000021e8: addlt    r1, r2, sp, lsl #24
000021ec: strbvs   r4, [r0, #0x44c]!
000021f0: andhs    r1, r4, #0x1600
000021f4: cmphs    r6, r0
000021f8: andshs   r2, ip, r5, lsl #6
000021fc: stc2     p7, c15, [r2, #0x3fc]!
00002200: rscvs    r2, r0, #0
00002204: .byte    0xe5, 0x72, 0x26, 0x73
00002208: ldcllt   p0, c11, [r0, #-8]!
0000220c: muleq    r0, ip, r2
00002210: stmdami  ip!, {r0, r1, r2, r3, r4, r5, r6, r7, r8, sl, ip, sp, pc}
00002214: .byte    0x0e, 0x1c, 0x17, 0x1c
00002218: stmdbvs  r0, {r3, r6, sl, lr} ^
0000221c: addlt    r2, r1, r0, lsl #10
00002220: blx      #0xff73e2ac
00002224: movwhs   r4, #0x5827
00002228: stmdbvs  r0, {r3, r6, sl, lr}
0000222c: strbpl   r2, [r0], r0, lsl #8
00002230: ldcle    p8, c2, [r3, #-0]!
00002234: stcne    p8, c4, [r1], #-0x8c
00002238: stmdbvs  r0, {r3, r6, sl, lr}
0000223c: blx      #0xfee3e2ca
00002240: stmdahs  r0, {r5, r8, fp, lr}
00002244: addvs    r4, r8, #0x49000000
00002248: stmdbls  r1, {r1, r2, r3, r4, ip, lr, pc}
0000224c: andle    r1, r4, fp, asr #24
00002250: .byte    0x18, 0x23, 0xc1, 0x56
00002254: addsmi   sb, r1, #0x1000
00002258: .byte    0x16, 0xdb, 0x73, 0x1c
0000225c: tsths    r8, #3
00002260: adcsmi   r5, r1, #0xc100000
00002264: ldclne   p12, c13, [fp], #-0x40
00002268: tsths    sb, #3
0000226c: adcsmi   r5, sb, #0xc100000
00002270: ldmdbmi  r4, {r1, r3, r8, ip, lr, pc}
00002274: strbmi   r1, [sb], #-0xc2b
00002278: stmdavs  sl, {r0, r3, r6, r8, fp, sp, lr}
0000227c: streq    r1, [sb], -sb, ror #24
00002280: .byte    0x09, 0x16, 0x0d, 0x1c
00002284: .byte    0x99, 0x00, 0x50, 0x50
00002288: movwhs   r4, #0x590e
0000228c: stmdbvs  r8, {r0, r3, r6, sl, lr}
00002290: strbpl   r3, [r0], r1, lsl #8
00002294: strtne   r0, [r4], -r4, lsr #12
00002298: stclle   p2, c4, [fp], {0xa0}
0000229c: movwhs   r4, #0x5c09
000022a0: stmdbvs  r2!, {r2, r3, r6, sl, lr} ^
000022a4: strbvs   r2, [r2, #0x156]!
000022a8: andhs    sb, r4, #0, #4
000022ac: .byte    0x1c, 0x20, 0xff, 0xf7
000022b0: andhs    pc, r0, sb, asr #26
000022b4: stmdals  r4, {r5, r6, r7, sb, sp, lr}
000022b8: stmdals  sl, {r5, r6, r7, sb, ip, sp, lr}
000022bc: andlt    r7, r5, r0, lsr #6
000022c0: strdeq   fp, ip, [r0], -r0
000022c4: muleq    r0, ip, r2
000022c8: svcmi    #0x24b5ff
000022cc: strbmi   r1, [pc], #-0xc16
000022d0: strhs    r6, [r0, #-0x978]
000022d4: .byte    0x81, 0xb0, 0x21, 0xf0
000022d8: ldmdbvs  r8!, {r0, r7, sb, fp, ip, sp, lr, pc}
000022dc: strbpl   r2, [r0], r5, lsl #6
000022e0: stmdahs  r0, {sl, sp}
000022e4: stcne    p13, c13, [r1], #-0xa8
000022e8: .byte    0x38, 0x69, 0x21, 0xf0
000022ec: adcsvs   pc, r8, #0x18400
000022f0: andsle   r2, fp, r0, lsl #16
000022f4: .byte    0x18, 0x23, 0xc1, 0x56
000022f8: addsmi   sb, r1, #0x1000
000022fc: bls      #0xb8f5c
00002300: .byte    0x91, 0x42, 0x13, 0xdc
00002304: andle    r1, r3, r3, ror ip
00002308: .byte    0x19, 0x23, 0xc1, 0x56
0000230c: strhle   r4, [sp, -r1]
00002310: .byte    0x3a, 0x21, 0x09, 0x56
00002314: addsmi   sb, r1, #4, #20
00002318: ldmdbvs  sb!, {r3, ip, lr, pc} ^
0000231c: stmdavs  sl, {r0, r1, r3, r5, sl, fp, ip}
00002320: streq    r1, [sb], -sb, ror #24
00002324: .byte    0x09, 0x16, 0x0d, 0x1c
00002328: .byte    0x99, 0x00, 0x50, 0x50
0000232c: movwhs   r6, #0x5938
00002330: strlo    r5, [r1], #-0x6c0
00002334: strtne   r0, [r4], -r4, lsr #12
00002338: ldclle   p2, c4, [r4], {0xa0}
0000233c: movwhs   r6, #0x597a
00002340: andls    r6, r0, #0x3e800000
00002344: cmphs    r6, r4, lsl #4
00002348: .byte    0x1c, 0x20, 0xff, 0xf7
0000234c: .byte    0xfb, 0xfc, 0x00, 0x20
00002350: rscsvc   r6, r8, #248, #4
00002354: teqvc    r8, #1
00002358: ldcllt   p0, c11, [r0, #0x14]!
0000235c: muleq    r0, ip, r2
00002360: .byte    0xf3, 0xb5, 0x00, 0x26
00002364: strhs    r2, [r0], #-0x500
00002368: strhs    r1, [r0, -r8, lsl #24]
0000236c: strls    fp, [r0, -r1, lsl #1]
00002370: blx      #0x123e3fe
00002374: strbmi   r4, [sb], #-0x99d
00002378: bls      #0x5aea0
0000237c: stmdbls  r1, {r1, r3, r6, r7, sl, sp, lr}
00002380: andsle   r2, r6, r0, lsl #18
00002384: rsbsle   r2, r1, r1, lsl #18
00002388: rsbsle   r2, r0, r2, lsl #18
0000238c: .byte    0x03, 0x29, 0x6f, 0xd1
00002390: .byte    0x0c, 0x20, 0x24, 0xf0
00002394: blmi     #0xfe582368
00002398: strbmi   r1, [fp], #-0xc04
0000239c: stmdahs  r0, {r3, r4, r6, r7, sb, fp, sp, lr}
000023a0: eorslo   sp, r0, r7, rrx
000023a4: andshs   r7, r8, r1, asr #21
000023a8: rsbsle   r2, r1, r0, lsl #18
000023ac: eorvs    r2, r0, r1, lsl #12
000023b0: svcmi    #0x8ee10d
000023b4: strbmi   r2, [pc], #-0x800
000023b8: strhs    sp, [r1], -r6, lsl #2
000023bc: ldcne    p1, c2, [r0], #-0x18
000023c0: stc2     p0, c15, [ip], {0x1c}
000023c4: adc      r1, sp, r4, lsl #24
000023c8: .byte    0x21, 0xf0, 0x4a, 0xf9
000023cc: andshs   r1, r4, r6, lsl #24
000023d0: .byte    0x24, 0xf0, 0xd4, 0xff
000023d4: bvs      #0xffe093ec
000023d8: .byte    0x18, 0x23, 0xc1, 0x56
000023dc: blle     #0xcc85c
000023e0: .byte    0x27, 0x29, 0x01, 0xdc
000023e4: .byte    0x01, 0x21, 0x00, 0x91
000023e8: stmdbhs  r0, {r8, fp, ip, pc}
000023ec: eorslo   sp, r0, r4, lsr #32
000023f0: stmdahs  r1, {r6, r7, sb, fp, ip, sp, lr}
000023f4: strhs    sp, [r1, #-1]
000023f8: andhs    r6, r0, r5, lsr #32
000023fc: adcpl    r0, r0, sl, lsr #1
00002400: .byte    0xf8, 0x6a, 0x69, 0x1c
00002404: bvc      #0xff00e4cc
00002408: strne    r0, [sb], -sb, lsl #12
0000240c: andle    r2, r6, r0, lsl #16
00002410: ldreq    r1, [r2], -sl, asr #24
00002414: andhs    r1, r5, r2, lsl r6
00002418: rsbpl    r0, r0, sb, lsl #1

; candidate 0x82e4 callers=0 prologue=True
000082e4: stmdb    sl, {r1, r3, r4, ip, sp, lr, pc} ^
000082e8: and      r1, ip, sp, ror #16
000082ec: .byte    0x1f, 0x98, 0x00, 0x2c
000082f0: movwhs   sp, #7
000082f4: ldmdbne  r8!, {r0, r1, r3, r4, r6, r7, r8, sb, lr}
000082f8: cmnmi    r0, #192, #12
000082fc: ldm      r8, {r1, r3, r4, ip, sp, lr, pc} ^
00008300: .byte    0x48, 0x19, 0x05, 0x1c
00008304: ldmdbls  r8, {r1, r3, r8, sl, ip, sp}
00008308: andle    r2, r5, r0, lsl #18
0000830c: addeq    sb, r8, r5, lsl sb
00008310: stmdapl  sl, {r3, r4, r8, fp, ip, pc}
00008314: .byte    0x00, 0x2a, 0x00, 0xd1
00008318: stmdals  r2!, {r2, r4, sb, fp, ip, pc}
0000831c: bvs      #0x2cb24
00008320: movwhs   sb, #0x8915
00008324: stmdapl  r0, {r0, r3, r7} ^
00008328: .byte    0x1e, 0x99, 0xc9, 0x56
0000832c: .byte    0x1c, 0x9a, 0x0b, 0x1c
00008330: .byte    0x29, 0x1c, 0x1d, 0xf0
00008334: ldmdals  sl, {r0, r2, r4, r6, r7, r8, sl, fp, ip, sp, lr, pc}
00008338: addmi    r3, r4, #0x1000000
0000833c: ldmdals  r7, {r0, r1, r2, r4, r5, r7, r8, sb, fp, ip, lr, pc}
00008340: andsls   r3, r7, r1
00008344: rfedb    #4!
00008348: orrsle   r2, r4, r0, lsl #16
0000834c: ldrb     lr, [pc, r0]!
00008350: strhs    sb, [r0, #-0x822]
00008354: .byte    0x40, 0x79, 0xed, 0x43
00008358: ldmdble  sp!, {r0, fp, sp}
0000835c: movwhs   sb, #0x2822
00008360: stmvs    r1, {fp, sp, lr} ^
00008364: strbpl   sb, [r0], r1, lsr #16
00008368: movwhs   sb, #0x6a19
0000836c: bls      #0x6d90b4
00008370: stmdals  r1!, {r2, r3, fp, ip}
00008374: andls    r5, r1, #0xc100000
00008378: subshs   sb, pc, #0x190000
0000837c: ldcne    p8, c1, [r3], #-0x98
00008380: .byte    0x10, 0x3b, 0x00, 0x91
00008384: stmdals  r2!, {r0, r3, r5, sl, fp, ip}
00008388: .byte    0x00, 0xf0, 0x6e, 0xf8
0000838c: stmdbvc  r1, {r1, r5, fp, ip, pc} ^
00008390: andlo    r7, r1, r0, lsl #18
00008394: .byte    0x17, 0xf0, 0x8a, 0xf8
00008398: .byte    0x11, 0x9a, 0x21, 0x23
0000839c: ldcne    p2, c9, [r2], #-0
000083a0: .byte    0x78, 0x21, 0x1d, 0xf0
000083a4: stmdals  r1!, {r0, r2, r3, r4, r7, r8, sl, fp, ip, sp, lr, pc}
000083a8: bls      #0x6d0fc4
000083ac: andls    r5, r1, #0xc100000
000083b0: stcne    p4, c3, [r3], #-0x18
000083b4: .byte    0x10, 0x22, 0x00, 0x91
000083b8: stmdals  r2!, {r0, r1, r4, r5, r8, sp}
000083bc: .byte    0x00, 0xf0, 0x54, 0xf8
000083c0: movwhs   sb, #0x4821
000083c4: .byte    0x1b, 0x9a, 0xc1, 0x56
000083c8: adchs    sb, lr, #0x10000000
000083cc: .byte    0x23, 0x1c, 0x00, 0x91
000083d0: stmdals  r2!, {r2, r4, r5, r8, sp}
000083d4: .byte    0x00, 0xf0, 0x48, 0xf8
000083d8: .byte    0x07, 0xf0, 0x06, 0xf8
000083dc: .byte    0x00, 0x20, 0x07, 0xf0
000083e0: stmdals  r2!, {r0, r2, r7, sb, fp, ip, sp, lr, pc}
000083e4: stmdahs  r0, {r6, r7, r8, fp, sp, lr}
000083e8: eorhs    sp, r3, r4
000083ec: blx      #0xfebc4454
000083f0: blx      #0x94444e
000083f4: .byte    0x0f, 0xf0, 0x00, 0xf8
000083f8: andsle   r2, r2, r0, lsl #16
000083fc: rscshs   r2, pc, r0, asr r1
00008400: .byte    0x79, 0x30, 0x0e, 0xf0
00008404: .byte    0xb5, 0xfe, 0x04, 0x1c
00008408: .byte    0x6f, 0x20, 0x18, 0xf0
0000840c: .byte    0x9f, 0xfa, 0x01, 0x1c
00008410: stmdavs  r2, {r0, r1, r4, sp, pc} ^
00008414: stmdavs  r3, {sb, ip, pc}
00008418: stcne    p12, c1, [sl], #-0x80
0000841c: .byte    0x1a, 0x30, 0x0e, 0xf0
00008420: eorlt    pc, r3, pc, lsr lr
00008424: strdeq   fp, ip, [r0], -r0
00008428: eoreq    r7, sb, sl, ror #30
0000842c: umaaleq  sp, r5, lr, r6
00008430: rsbseq   r4, r3, r4, lsr #10
00008434: ldrshteq pc, [pc], #0xff
00008438: sbceq    pc, pc, sl, lsr #30
0000843c: eorseq   r2, ip, sb, lsl r4
00008440: ldrsheq  sp, [r5], #-0x5f
00008444: adcseq   fp, r7, sl, asr #2
00008448: ldrhteq  pc, [pc], #0x6c
0000844c: sbcseq   ip, sp, r7, lsl #11
00008450: smlalseq sp, r5, fp, pc
00008454: subeq    r2, r0, r8, lsl r7
00008458: rscseq   pc, pc, sp, lsl #2
0000845c: rsceq    sb, fp, r6, lsr lr
00008460: .byte    0xff, 0xff, 0xff, 0xff
00008464: .byte    0xff, 0xff, 0xff, 0xff
00008468: strdlt   fp, ip, [sb], r0
0000846c: stmdbls  lr, {r0, r1, r2, r3, sl, fp, ip}
00008470: .byte    0x1e, 0x1c, 0x15, 0x1c
00008474: blle     #0x169287c
00008478: .byte    0x31, 0x23, 0xc0, 0x56
0000847c: addmi    r2, r8, #0x1000000
00008480: strhs    sp, [r0], #-0
00008484: andle    r2, r5, r0, lsl #24
00008488: eorshs   r2, r2, #0x48000000
0000848c: stcne    p12, c1, [r8], #-0xc4
00008490: stc2     p0, c15, [ip], #-0x60
00008494: stmdage  r5, {r0, r1, r2, r3, r8, fp, ip, pc}
00008498: andle    r2, sp, r0, lsl #18
0000849c: .byte    0x03, 0x29, 0x2a, 0xd1
000084a0: andsle   r2, pc, r0, lsl #24
000084a4: stmdbmi  r4!, {r0, r1, r5, sb, fp, lr}
000084a8: .byte    0x01, 0x92, 0x00, 0x91
000084ac: bmi      #0x9108c4
000084b0: .byte    0x22, 0x4b, 0x17, 0xf0
000084b4: ldrh     pc, [lr], -r7
000084b8: andle    r2, sb, r0, lsl #24
000084bc: stmdbmi  r2!, {r0, r5, sb, fp, lr}
000084c0: .byte    0x01, 0x92, 0x0a, 0x1c
000084c4: .byte    0x00, 0x91, 0x04, 0x21
000084c8: .byte    0x20, 0x4b, 0x17, 0xf0
000084cc: ands     pc, r2, fp, lsr #17
000084d0: ldmdbmi  pc, {sb, sp}
000084d4: .byte    0x01, 0x92, 0x00, 0x91
000084d8: bmi      #0x7d08f0
000084dc: .byte    0x1d, 0x4b, 0x17, 0xf0
000084e0: and      pc, r8, r1, lsr #17
000084e4: ldmdbmi  sp, {sb, sp}
000084e8: .byte    0x01, 0x92, 0x00, 0x91
000084ec: bmi      #0x690904
000084f0: .byte    0x1b, 0x4b, 0x17, 0xf0
000084f4: andhs    pc, r0, #0x970000
000084f8: stmdbls  r8, {r0, r1, sb, ip, pc}
000084fc: stmdals  r7, {r1, r2, sb, fp, ip, pc}
00008500: andls    sb, r0, #0x80000000
00008504: ldcne    p2, c2, [r1], #-0xc8
00008508: andls    r2, r1, r2, lsl r3
0000850c: .byte    0x28, 0x1c, 0x1d, 0xf0
00008510: ldclne   p12, c15, [fp], #-0x1dc
00008514: ldcne    p13, c13, [r8], #-0x2c
00008518: blx      #0x644580
0000851c: .byte    0x05, 0x9a, 0x21, 0x23
00008520: ldcne    p2, c9, [r2], #-0
00008524: stcne    p2, c3, [sb], #-0x44
00008528: .byte    0x19, 0x31, 0x1d, 0xf0
0000852c: .byte    0xd9, 0xfc, 0x09, 0xb0
00008530: strdeq   fp, ip, [r0], -r0
00008534: subseq   ip, r0, lr, ror #10
00008538: eoreq    r6, r0, r2, asr r2
0000853c: sbceq    pc, pc, sl, lsr #30
00008540: rsbeq    r3, r6, r5, lsr #28
00008544: ldrhteq  pc, [pc], #0x6c
00008548: rsbeq    r3, r4, sb, lsl r0
0000854c: rscseq   fp, lr, r6, lsr sb
00008550: sbcseq   ip, sp, r7, lsl #11
00008554: smlalseq sp, r5, fp, pc
00008558: rsbseq   r4, r3, r4, lsr #10
0000855c: eoreq    r7, sb, sl, ror #30
00008560: umaaleq  sp, r5, lr, r6
00008564: stmdavs  r4, {r4, r5, r6, r7, r8, sl, ip, sp, pc}
00008568: stmvs    r0!, {r1, r2, sl, fp, ip} ^
0000856c: addslt   r6, r1, r5, lsr #17
00008570: bvs      #0x8ec5a8
00008574: movwls   r6, #0xb9e7
00008578: usatpl   r2, #0, r4, lsl #6
0000857c: suble    r2, r2, #0xa0000
00008580: .byte    0x01, 0xa3, 0x1b, 0x5c
00008584: ldrmi    r0, [pc], #0x5b
00008588: mrcmi    p2, #1, r2, c14, c14, #1
0000858c: mcrlo    p13, #0, r5, c4, c1, #1
00008590: bmi      #0x18181e4
00008594: andls    r4, r3, #96, #18
00008598: stmdami  r0!, {r0, r5, r6, sb, fp, lr} ^
0000859c: andls    sb, r0, #0x80000000
000085a0: stmdage  r5, {r0, ip, pc}
000085a4: .byte    0x60, 0x4a, 0x06, 0x21
000085a8: .byte    0x5e, 0x4b, 0x17, 0xf0
000085ac: eor      pc, sl, fp, lsr r8
000085b0: ldmdbmi  pc, {r1, r2, r3, r4, r6, sb, fp, lr} ^

; candidate 0x1aeb0 callers=0 prologue=True
0001aeb0: stmdb    r2!, {r0, r2, r5, r6, r7, r8, sb, sl, ip, sp, lr, pc} ^
0001aeb4: .byte    0x11, 0xa4, 0x0c, 0xcc
0001aeb8: .byte    0x08, 0x3c, 0xe5, 0xf7
0001aebc: ble      #0x951ec
0001aec0: and      ip, ip, r3, lsl #24
0001aec4: movwhs   r4, #0xc0b
0001aec8: strbtpl  r4, [r0], ip, asr #8
0001aecc: blx      #0xcd6f20
0001aed0: ldmdavs  r8!, {r1, sl, fp, ip}
0001aed4: stmdbvs  r0, {r0, r1, r3, sl, fp, ip} ^
0001aed8: .byte    0xc1, 0x17, 0xe5, 0xf7
0001aedc: stcne    p9, c14, [fp], #-0x138
0001aee0: mrshs    r1, apsr
0001aee4: .byte    0x01, 0x20, 0xfc, 0xf7
0001aee8: ldr      pc, [sb, r3, lsr #20]
0001aeec: andeq    r0, r0, ip, lsl #13
0001aef0: andeq    r0, r0, r8, asr #5
0001aef4: andeq    r0, r0, r4, asr #10
0001aef8: andeq    r0, r0, ip, lsr #5
0001aefc: andeq    r0, r0, r3, rrx
0001af00: andeq    r0, r0, r0
0001af04: andshs   fp, r0, r8, lsr r5
0001af08: blx      #0xe56f40
0001af0c: ldmdami  r2, {r2, sl, fp, ip}
0001af10: stmdavs  r0, {r3, r6, sl, lr}
0001af14: mrsle    r2, apsr
0001af18: and      r2, r0, r5
0001af1c: .byte    0x04, 0x20, 0x06, 0x21
0001af20: rsbvs    r6, r1, r0, lsr #32
0001af24: movwhs   r4, #0x90d
0001af28: strbpl   r4, [sb], sb, asr #8
0001af2c: strhs    r2, [r2, #-4]
0001af30: .byte    0x01, 0x29, 0x04, 0xd1
0001af34: andhs    r2, r7, #8, #2
0001af38: adcvs    r6, r2, r1, ror #1
0001af3c: stcne    p12, c1, [r1], #-0x14
0001af40: .byte    0x28, 0x1c, 0x03, 0xf0
0001af44: blmi     #0x1da920
0001af48: ldrbtmi  r1, [fp], #-0xc01
0001af4c: stcne    p12, c1, [r8], #-0x88
0001af50: mcr2     p7, #5, pc, c12, c12, #7
0001af54: andeq    fp, r0, r8, lsr sp
0001af58: andeq    r0, r0, ip, lsl #13
0001af5c: andeq    r0, r0, r4, asr #10
0001af60: .byte    0x4b, 0xfa, 0xff, 0xff
0001af64: .byte    0x10, 0xb5, 0x12, 0x4c
0001af68: strbmi   r2, [ip], #-0
0001af6c: .byte    0x60, 0x71, 0x60, 0x63
0001af70: mvnvc    r7, r0, lsr #3
0001af74: andhs    r6, r5, r0, lsr #5
0001af78: andhs    r6, sl, r0, lsr #7
0001af7c: b        #0xfe256fa0
0001af80: blmi     #0x333f08
0001af84: strbmi   r4, [fp], #-0x80a
0001af88: andhs    r6, sl, #0x1b0000
0001af8c: strbmi   r2, [r8], #-0x100
0001af90: .byte    0x78, 0x30, 0x98, 0x47
0001af94: stmdami  r8, {r8, sp}
0001af98: .byte    0x78, 0x44, 0x0a, 0xf0
0001af9c: stmdbmi  r7, {r0, r1, r2, r4, r8, sl, fp, ip, sp, lr, pc}
0001afa0: strbtvs  r4, [r0], #-0x479
0001afa4: strbmi   r4, [r8], #-0x802
0001afa8: .byte    0x48, 0x30, 0x04, 0xf0
0001afac: vldrlt   d15, [r0, #-0xa4]
0001afb0: andeq    r0, r0, r0, asr #6
0001afb4: andeq    r0, r0, r4, asr #27
0001afb8: ldrdeq   r5, r6, [r1], -r4
0001afbc: andeq    r5, r1, r4, asr #23
0001afc0: ldclmi   p5, c11, [r4, #-0x3e0]
0001afc4: strbmi   r2, [sp], #-0x307
0001afc8: movwhs   r5, #0x86ee
0001afcc: strhs    r5, [r0], #-0x6e8
0001afd0: andsle   r2, r7, r0, lsl #16
0001afd4: rsble    r2, pc, r1, lsl #16
0001afd8: tstle    r2, r5, lsl #16
0001afdc: .byte    0xff, 0x23, 0xe1, 0x33
0001afe0: smlabbhs r0, r2, r1, r0
0001afe4: .byte    0x00, 0x20, 0x09, 0xf0
0001afe8: stmdahs  r0, {r0, r1, r2, r4, r5, r7, sb, sl, fp, ip, sp, lr, pc}
0001afec: andhs    sp, r1, r5, lsl #2
0001aff0: .byte    0x40, 0x04, 0x09, 0xf0
0001aff4: stmdahs  r0, {r0, r1, r2, r5, sb, sl, fp, ip, sp, lr, pc}
0001aff8: andhs    sp, r0, r3
0001affc: .byte    0x28, 0x72, 0x09, 0xf0
0001b000: ldcllt   p12, c15, [r8, #0x14c]!
0001b004: stmdami  r5, {r2, r6, r8, sb, sl, fp, lr} ^
0001b008: smlsdxpl r0, r8, r4, r4
0001b00c: subeq    r2, r1, ip, asr #6
0001b010: stmdami  r3, {r0, r3, fp, ip} ^
0001b014: ldrbtmi  r0, [r8], #-0x109
0001b018: teqlo    r0, r0, lsl #14
0001b01c: teqhs    r0, #88, #6
0001b020: subhs    r3, ip, #6
0001b024: cdp2     p0, #9, c15, c8, c9, #0
0001b028: andle    r2, r8, r0, lsl #16
0001b02c: strne    r0, [r0], -r0, lsr #12
0001b030: .byte    0xe8, 0x71, 0xa8, 0x71
0001b034: smlabble r2, r6, r2, r4
0001b038: .byte    0x38, 0x1c, 0x0a, 0xf0
0001b03c: strlo    pc, [r1], #-0x8cb
0001b040: blle     #0xff826070
0001b044: streq    r2, [r0], #-1
0001b048: ldc2l    p0, c15, [ip, #0x24]!
0001b04c: andle    r2, r5, r0, lsl #16
0001b050: .byte    0x34, 0x48, 0xfd, 0xf7
0001b054: .byte    0xf7, 0xfc, 0xfe, 0xf7
0001b058: bfi      pc, r1, #0x10, #3
0001b05c: .byte    0x38, 0x1c, 0x09, 0xf0
0001b060: stmdahs  r0, {r0, r4, r5, r6, r7, r8, sl, fp, ip, sp, lr, pc}
0001b064: movwhs   sp, #0x7008
0001b068: stcvs    p6, c5, [r8], #-0x3a4
0001b06c: stc2     p0, c15, [r0], #0x20
0001b070: .byte    0x00, 0x68, 0x08, 0xf0
0001b074: strb     pc, [r4, r7, asr #22]
0001b078: movweq   r2, #1
0001b07c: stc2l    p0, c15, [r2, #0x24]!
0001b080: andle    r2, sl, r0, lsl #16
0001b084: rscslo   r7, pc, r8, ror #19
0001b088: strne    r0, [r0], -r0, lsl #12
0001b08c: strle    r7, [r1, #-0x1e8]
0001b090: mvnvc    r2, sb
0001b094: .byte    0xe8, 0x79, 0xa8, 0x71
0001b098: strhhs   lr, [r1], -r3
0001b09c: .byte    0x40, 0x03, 0x09, 0xf0
0001b0a0: stmdahs  r0, {r0, r4, r6, r7, r8, sl, fp, ip, sp, lr, pc}
0001b0a4: stmibvc  r8!, {r0, r3, ip, lr, pc} ^
0001b0a8: streq    r3, [r0], -r1
0001b0ac: .byte    0x00, 0x16, 0x07, 0xf0
0001b0b0: strdvc   lr, pc, [r8, #0x90]!
0001b0b4: str      r7, [r4, r8, lsr #3]!
0001b0b8: ldmdami  fp, {r0, r3, r4, sp, lr, pc}
0001b0bc: stmdavs  r0, {r3, r4, r5, r6, sl, lr}
0001b0c0: stc2     p0, c15, [lr, #0x24]
0001b0c4: andle    r2, fp, r0, lsl #16
0001b0c8: strbtpl  r2, [r8], r4, lsl #6
0001b0cc: ldcle    p8, c2, [r8]
0001b0d0: .byte    0x16, 0x48, 0xfd, 0xf7
0001b0d4: .byte    0xa9, 0xfd, 0xfd, 0xf7
0001b0d8: .byte    0x0d, 0xfd, 0xfd, 0xf7
0001b0dc: ldr      pc, [r0, pc, asr #31]
0001b0e0: stc2     p0, c15, [r4, #0x24]!
0001b0e4: addle    r2, ip, r0, lsl #16
0001b0e8: blx      #0x359098
0001b0ec: ldmdami  r0, {r0, r3, r7, r8, sb, sl, sp, lr, pc}
0001b0f0: stmdavs  r0, {r3, r4, r5, r6, sl, lr} ^
0001b0f4: ldc2l    p0, c15, [r4, #-0x24]!
0001b0f8: addle    r2, r2, r0, lsl #16
0001b0fc: strbtpl  r2, [r8], r8, lsl #6
0001b100: .byte    0x01, 0x28, 0xaa, 0xd1
0001b104: eorvc    r2, r8, #2
0001b108: .byte    0x0a, 0x48, 0xfd, 0xf7
0001b10c: .byte    0x8d, 0xfd, 0xfd, 0xf7
0001b110: .byte    0xf1, 0xfc, 0x76, 0xe7
0001b114: andeq    r0, r0, r0, asr #6
0001b118: andeq    r0, r4, r0, lsr #32
0001b11c: andeq    r5, r1, sl, lsr #22
0001b120: andeq    r5, r1, r2, lsl fp
0001b124: .byte    0x02, 0x00, 0x00, 0x11
0001b128: strdeq   r5, r6, [r1], -r0
0001b12c: .byte    0x04, 0x00, 0x00, 0x11
0001b130: strheq   r5, [r1], -ip
0001b134: .byte    0x01, 0x00, 0x00, 0x11
0001b138: stcmi    p5, c11, [fp], #-0x3fc
0001b13c: strbmi   r1, [ip], #-0xc15
0001b140: .byte    0x22, 0x6c, 0x0f, 0x1c
0001b144: addlt    r2, r3, r0, lsl #20
0001b148: movwhs   sp, #0x4030
0001b14c: stmdbhs  r0, {r0, r4, r6, r7, sb, sl, ip, lr}
0001b150: .byte    0x2c, 0xdd, 0x01, 0x1c
0001b154: .byte    0x10, 0x1c, 0x08, 0xf0
0001b158: andhs    pc, r0, #0x2b00
0001b15c: stcne    p2, c9, [sl], #-0
0001b160: ldcne    p12, c1, [sb], #-0x10
0001b164: eorlo    r3, r0, #0x80000009
0001b168: .byte    0x21, 0x23, 0x0e, 0x1c
0001b16c: .byte    0x40, 0x6a, 0x0a, 0xf0
0001b170: stcne    p15, c15, [r8], #-0x64
0001b174: eorlo    sb, r2, r6, lsl #18
0001b178: stmdbhs  r1, {r0, r4, r8, sb, sp}
0001b17c: bmi      #0x70f5e4

; candidate 0x213b4 callers=0 prologue=True
000213b4: stmdb    sl!, {r0, ip, sp, lr, pc} ^
000213b8: stmdane  r8, {r0, r6, r7, r8, sb, sl, fp}
000213bc: subne    sb, r0, r3, lsl #18
000213c0: andls    r2, r0, #0, #4
000213c4: ldmdavs  r0!, {r0, r3, sb, fp, ip}
000213c8: stmdbvs  r0, {r0, r5, r8, sb, sp}
000213cc: stmdavs  r0, {r1, r5, r8, sl, fp, ip}
000213d0: stmvs    r0, {fp, sp, lr}
000213d4: stc2l    p0, c15, [r6, #0x10]!
000213d8: strbmi   r4, [r8], #-0x81f
000213dc: stmvc    r0, {r2, r3, r6, ip, sp} ^
000213e0: andsle   r2, sl, r0, lsl #16
000213e4: ldrbtpl  r2, [r8], sl, lsl #6
000213e8: stmdane  r8, {r0, r6, r7, r8, sb, sl, fp}
000213ec: stmdbne  r5, {r6, ip} ^
000213f0: strbmi   r4, [r8], #-0x81c
000213f4: .byte    0x00, 0x68, 0x01, 0xf0
000213f8: svceq    #0xc1e94a
000213fc: subne    r1, r0, r8, lsl #16
00021400: andls    r2, r0, #0, #4
00021404: ldmdavs  r0!, {r0, r3, r5, fp, ip}
00021408: stmdbvs  r0, {r0, r1, r8, ip, sp}
0002140c: stmdavs  r0, {r0, r5, r8, sb, sp}
00021410: stmdavs  r0, {r1, r5, r8, sl, fp, ip}
00021414: .byte    0xc0, 0x68, 0x04, 0xf0
00021418: andhs    pc, r1, r5, asr #27
0002141c: ldc2l    p0, c15, [r0], #0x18
00021420: ldrbtpl  r2, [r8], r3, lsl #6
00021424: cdp2     p0, #0xd, c15, c2, c0, #0
00021428: movwhs   r1, #0x2c05
0002142c: .byte    0xf8, 0x56, 0x00, 0xf0
00021430: cdpmi    p14, #0, c15, c12, c13, #6
00021434: strbmi   r1, [lr], #-0xc04
00021438: .byte    0x30, 0x68, 0xc1, 0x17
0002143c: stmdane  sb, {r0, r3, r6, r7, sb, sl, fp}
00021440: .byte    0x49, 0x11, 0x49, 0x01
00021444: subeq    r1, r3, r0, asr #20
00021448: andlo    r1, r1, r8, lsl r8
0002144c: ble      #0x5eb574
00021450: blmi     #0x221560
00021454: andeq    lr, r0, r0, lsl r0
00021458: andeq    r0, r0, r4, ror #24
0002145c: ldrshteq pc, [pc], #0xff
00021460: ldrsbteq lr, [pc], #0x83
00021464: andeq    r0, r0, r8, asr #9
00021468: eorseq   r2, sp, ip, lsl r4
0002146c: rscseq   pc, pc, sp, lsl #2
00021470: strheq   r0, [r0], -ip
00021474: andeq    pc, pc, r0, lsl #30
00021478: stcne    p12, c1, [r8], #-0x84
0002147c: blx      #0x1bdd496
00021480: stcne    p8, c4, [r2], #-0x188
00021484: .byte    0x0b, 0x3a, 0x29, 0x1c
00021488: stmdavs  r0, {r3, r6, sl, lr}
0002148c: .byte    0x0f, 0x39, 0x08, 0xf0
00021490: .byte    0x35, 0xfd, 0x05, 0xf0
00021494: ldmdami  lr, {r0, r1, r2, r6, r7, r8, sb, fp, ip, sp, lr, pc} ^
00021498: stmdavs  r0, {r3, r6, sl, lr}
0002149c: teqle    r4, r2, lsl r8
000214a0: stmdahs  r0, {r3, r4, r5, r7, r8, sl, fp, sp, lr}
000214a4: stmdbvc  r0, {r0, r4, r5, ip, lr, pc}
000214a8: eorle    r2, lr, r0, lsl #16
000214ac: strhs    r6, [r0], #-0xdf8
000214b0: stmdahs  r0, {r8, fp, ip, sp, lr}
000214b4: ldclvs   p13, c13, [r8, #0xa4]!
000214b8: stmdbne  r0, {fp, sp, lr}
000214bc: strbpl   r2, [r0], r1, lsl #6
000214c0: cdp2     p0, #7, c15, c6, c0, #0
000214c4: ldclvs   p12, c1, [r8, #0x14]!
000214c8: strpl    r6, [r0, -r0, lsl #16]
000214cc: cdp2     p0, #7, c15, c0, c0, #0
000214d0: ldmdavs  r0!, {r0, sl, fp, ip}
000214d4: strbne   r2, [r2, r1, lsr #6]
000214d8: ldmdane  r0, {r1, r4, r7, r8, sb, sl, fp}
000214dc: svceq    #0xc21080
000214e0: subsne   r1, r2, r2, lsl r8
000214e4: bne      #0xfe021634
000214e8: andhs    r1, r0, #0x410000
000214ec: ldmibvs  r8!, {sb, ip, pc} ^
000214f0: .byte    0x0c, 0x31, 0x0a, 0x1c
000214f4: stcne    p8, c6, [sb], #-0
000214f8: stmvs    r0, {r4, r8, ip, sp} ^
000214fc: ldc2l    p0, c15, [r2, #-0x10]
00021500: strlo    r6, [r2], #-0xdf8
00021504: adcmi    r7, r0, #0, #18
00021508: .byte    0xd5, 0xdc, 0x06, 0xf0
0002150c: movwhs   pc, #0x6b0f
00021510: movwhs   r5, #0x86fa
00021514: movwhs   r5, #0x96f9
00021518: movtmi   r5, #0xa6f8
0002151c: blvs     #0xffea7570
00021520: ldmdavs  r4, {r0, r1, r8, sb, ip, sp}
00021524: blne     #0x77b674
00021528: ldrbtpl  r2, [ip], r5, lsl #6
0002152c: movtmi   r2, #0xc30a
00021530: stmdane  r3!, {r0, r3, r4, r5, r6, r7, sb, sl, ip, lr} ^
00021534: bne      #0xfe730148
00021538: ldmdane  r0, {r1, r6, r7, r8, sb, sl, fp}
0002153c: subne    r6, r0, r2, lsr r8
00021540: svceq    #0x9b17d3
00021544: umullsne r1, r2, sl, r8
00021548: ldmne    fp, {r0, r1, r4, r6, r7, r8, sb, sl, fp}
0002154c: subseq   r1, fp, fp, asr r0
00021550: stmdbne  r0, {r1, r4, r6, r7, sb, fp, ip}
00021554: svceq    #0xc81886
00021558: subne    r1, r0, r0, asr #16
0002155c: stmdami  sp!, {r0, r6, r8, fp, ip}
00021560: andls    r2, r0, #0, #4
00021564: stmdavs  r0, {r3, r6, sl, lr}
00021568: stmdavs  r0, {r0, r5, r8, sb, sp}
0002156c: stclvs   p12, c1, [r0, #0xc8]
00021570: ldc2     p0, c15, [r8, #-0x10]
00021574: mrcpl    p3, #7, r2, c8, c10, #0
00021578: ldm      r8, {r0, ip, sp, lr, pc}
0002157c: bvs      #0xe617a4
00021580: .byte    0x08, 0x58, 0x03, 0xf0
00021584: andhs    pc, sl, r7, lsr #29
00021588: cdp2     p0, #8, c15, c12, c3, #0
0002158c: mrcpl    p3, #7, r2, c14, c10, #0
00021590: stmibne  r0, {r3, r4, r5, r6, sb, fp, sp, lr}
00021594: strbpl   r2, [r0], r4, lsl #6
00021598: cdp2     p0, #9, c15, c0, c3, #0
0002159c: .byte    0x7e, 0x20, 0x03, 0xf0
000215a0: bvs      #0x1e60fac
000215a4: movwhs   r1, #0x5980
000215a8: .byte    0xc0, 0x56, 0x03, 0xf0
000215ac: eorshs   pc, r5, r7, lsl #29
000215b0: .byte    0xff, 0xf7, 0xcc, 0xf9
000215b4: cdp2     p0, #8, c15, c14, c3, #0
000215b8: mrcpl    p3, #7, r2, c8, c10, #0
000215bc: ldmda    r6!, {r0, ip, sp, lr, pc} ^
000215c0: bvs      #0xe617e8
000215c4: .byte    0x08, 0x58, 0x05, 0xf0
000215c8: andslo   pc, r0, sp, asr #25
000215cc: ble      #0x6b6d4
000215d0: and      r2, sl, r0, asr #6
000215d4: mrcpl    p3, #7, r2, c8, c10, #0
000215d8: stmda    r8!, {r0, ip, sp, lr, pc} ^
000215dc: bvs      #0xe61804
000215e0: .byte    0x08, 0x58, 0x05, 0xf0
000215e4: .byte    0xbf, 0xfc, 0x03, 0x1c
000215e8: .byte    0x10, 0x33, 0x1e, 0x1c
000215ec: blx      #0x6dd60a
000215f0: .byte    0x09, 0x4a, 0x07, 0x1c
000215f4: andls    r2, r2, #2
000215f8: andls    r1, r0, r2, lsr #24
000215fc: stcne    p12, c1, [sb], #-0xcc
00021600: strls    r1, [r1], #-0xc38
00021604: mrrc2    p7, #0xf, pc, sl, c13
00021608: ldcllt   p0, c11, [r0, #0x1c]!
0002160c: andeq    r0, r0, r8, asr #8
00021610: andeq    r0, r0, r8, lsl #13
00021614: andeq    r0, r0, r0, lsl #13
00021618: subeq    r2, r0, r8, lsl r7
0002161c: .byte    0x10, 0xb5, 0x14, 0x4c
00021620: strbmi   r2, [ip], #-0x800
00021624: .byte    0x08, 0xd0, 0x0d, 0xf0
00021628: mvnvs    pc, #0x3c400
0002162c: blx      #0xffbdd66a
00021630: .byte    0x20, 0x64, 0x09, 0xf0
00021634: ldclt    p14, c15, [r0, #-0x4c]
00021638: strbmi   r4, [r8], #-0x80d
0002163c: .byte    0x3c, 0x30, 0x0d, 0xf0
00021640: stmdami  fp, {r0, r4, r5, r6, sl, fp, ip, sp, lr, pc}
00021644: sublo    r4, r0, r8, asr #8
00021648: stc2l    p0, c15, [ip], #-0x34
0002164c: bvs      #0x83f6d8
00021650: blx      #0x55d670
00021654: .byte    0x60, 0x6a, 0x05, 0xf0
00021658: bvs      #0xfe86013c
0002165c: blx      #0xfed5d678
00021660: .byte    0xe0, 0x6a, 0x05, 0xf0
00021664: blvs     #0x860130
00021668: blx      #0xfebdd684
0002166c: andeq    fp, r0, r0, lsl sp
00021670: andeq    r0, r0, r4, ror #24
00021674: .byte    0x10, 0xb5, 0x03, 0xf0
00021678: stmdahs  r0, {r0, r3, r4, r6, r7, sb, fp, ip, sp, lr, pc}
0002167c: andhs    sp, r8, r4, lsl #2
00021680: blx      #0xff85d694

; candidate 0x860 callers=1 prologue=False
00000860: mcrmi    p5, #0, fp, c14, c0, #3
00000864: .byte    0x0d, 0x1c, 0x01, 0x1c
00000868: ldrbtmi  r1, [lr], #-0xc04
0000086c: .byte    0x30, 0x1c, 0x00, 0xf0
00000870: .byte    0x00, 0xf8, 0x02, 0x1c
00000874: strhle   r4, [r6, -r0]
00000878: stcne    p12, c1, [r0], #-0xa4
0000087c: .byte    0x00, 0xf0, 0x20, 0xf8
00000880: .byte    0x70, 0xbc, 0x08, 0xbc
00000884: stmdami  r6, {r3, r4, r8, sb, sl, lr}
00000888: addmi    r4, r2, #120, #8
0000088c: stcne    p0, c13, [sb], #-0xc
00000890: .byte    0x20, 0x1c, 0xff, 0xf7
00000894: andhs    pc, r0, r5, asr #23
00000898: strdeq   lr, pc, [r0], -r2
0000089c: .byte    0x99, 0xf7, 0xf7, 0xff
000008a0: .byte    0x79, 0xf7, 0xf7, 0xff
000008a4: andeq    r4, r0, r8, ror r7
000008a8: mov      r0, #0x18
000008ac: ldr      r1, [pc, #8]
000008b0: svc      #0x123456
000008b4: bx       lr

; candidate 0x2cd64 callers=1 prologue=False
0002cd64: mcrmi    p5, #1, fp, c9, c0, #3
0002cd68: ldcne    p4, c4, [r4], #-0x1f8
0002cd6c: blvs     #0xfe83be74
0002cd70: mcrvs    p1, #2, r2, c2, c4, #0
0002cd74: ldrbtmi  r4, [r8], #-0x826
0002cd78: strhs    r4, [r0, #-0x790]
0002cd7c: adcmi    r4, r8, #0xb4000003
0002cd80: stcne    p1, c13, [r8], #-4
0002cd84: blvs     #0xff89c34c
0002cd88: addvs    r2, r8, r1
0002cd8c: ldrbtmi  r4, [r8], #-0x821
0002cd90: strbvs   r6, [r8, r1, lsr #23]
0002cd94: ldrbtmi  r4, [r8], #-0x820
0002cd98: orrlo    r6, r0, r1, lsr #23
0002cd9c: .byte    0x08, 0x60, 0xd3, 0xf7
0002cda0: blvs     #0xff8a8650
0002cda4: blvs     #0xfe884ecc
0002cda8: stmdavs  sb, {r2, ip, sp}
0002cdac: blvs     #0xff87ebd4
0002cdb0: andvs    r2, r8, r0, lsl #16
0002cdb4: andle    r6, r5, r1, ror #23
0002cdb8: andvs    r6, r1, sb, asr #16
0002cdbc: stmdavs  r1, {r5, r6, r7, r8, sb, fp, sp, lr}
0002cdc0: andvs    r3, r1, r4, lsl #2
0002cdc4: stmdavs  r0, {r5, r6, r7, r8, sb, fp, sp, lr}
0002cdc8: andsle   r2, ip, r0, lsl #16
0002cdcc: mcr      p7, #1, pc, c2, c3, #6
0002cdd0: .byte    0x05, 0x1c, 0xd3, 0xf7
0002cdd4: stmibne  r1, {r1, r2, r5, sb, sl, fp, sp, lr, pc}
0002cdd8: blvs     #0xfe8c7d60
0002cddc: ldmvs    r3, {fp, sp, lr} ^
0002cde0: ldrmi    r1, [r8, sl, lsr #24]
0002cde4: mrc      p7, #0, apsr_nzcv, c6, c3, #6
0002cde8: stmdavs  sb, {r0, r5, r6, r7, r8, sb, fp, sp, lr} ^
0002cdec: .byte    0x0d, 0x1a, 0xd3, 0xf7
0002cdf0: blvs     #0xff8a8640
0002cdf4: stmdane  r0, {r0, r3, fp, sp, lr} ^
0002cdf8: .byte    0xa1, 0x6b, 0x2a, 0x1c
0002cdfc: smlabbhs r0, fp, fp, r6
0002ce00: mulhs    r0, r8, r7
0002ce04: stcne    p13, c11, [r8], #-0x1c0
0002ce08: andeq    fp, r0, r0, ror sp
0002ce0c: .byte    0x9c, 0x32, 0xfd, 0xff
0002ce10: andeq    r0, r0, fp, lsr fp
0002ce14: andeq    r0, r0, r3, asr #12
0002ce18: andeq    r0, r0, r3, ror #12
0002ce1c: .byte    0xff, 0xb5, 0x00, 0x27
0002ce20: .byte    0x00, 0x21, 0xff, 0x43
0002ce24: .byte    0x87, 0xb0, 0x1e, 0x1c
0002ce28: stmdahs  r0, {r2, r4, sl, fp, ip}
0002ce2c: andle    sb, r6, r5, lsl #2
0002ce30: andle    r2, r4, r0, lsl #24
0002ce34: andle    r2, r2, r0, lsl #28
0002ce38: stmdbhs  sl, {r3, r8, fp, ip, pc}
0002ce3c: andhs    sp, r0, r5, lsl #18
0002ce40: andlt    r4, fp, r0, asr #7
0002ce44: .byte    0xf0, 0xbc, 0x08, 0xbc
0002ce48: stmdavc  r1, {r3, r4, r8, sb, sl, lr}
0002ce4c: ldrbtmi  r4, [sl], #-0xa93
0002ce50: stmdbhs  sl!, {r1, r2, sb, ip, pc}
0002ce54: mrshs    sp, apsr
0002ce58: .byte    0x06, 0x9a, 0x05, 0x91
0002ce5c: stmdavc  r0, {r0, r4, r7, r8, sb, fp, sp, lr} ^
0002ce60: stmdavs  sb, {r0, r3, r6, r7, r8, sl, fp, sp, lr}
0002ce64: stmdane  r8, {r7}
0002ce68: stmdalo  r1, {r0, r1, r2, r3, r4, r5, r6, r7, fp, ip, sp} ^
0002ce6c: ands     r6, r1, r0, asr #23
0002ce70: .byte    0x24, 0x29, 0x08, 0xd1
0002ce74: bls      #0x1b4e80
0002ce78: blvs     #0xfe450e94
0002ce7c: strdlo   r3, r4, [r1], pc
0002ce80: stmdavs  r0, {sb, fp, sp, lr}
0002ce84: bls      #0x1e4ea4
0002ce88: .byte    0x91, 0x6b, 0x80, 0x31
0002ce8c: .byte    0x0a, 0x6a, 0x01, 0x21
0002ce90: .byte    0xd3, 0xf7, 0xc6, 0xf8
0002ce94: mrsle    r1, apsr
0002ce98: ldrb     r4, [r2, r0, asr #7]
0002ce9c: .byte    0x80, 0x4b, 0x32, 0x1c
0002cea0: strbmi   r2, [fp], #-0x100
0002cea4: stcne    p8, c6, [r0], #-0x6c
0002cea8: rfeia    #1!
0002ceac: stmdahs  sl, {r3, fp, ip, pc}
0002ceb0: movwge   sp, #0x3204
0002ceb4: bpl      #0x6f2f28
0002ceb8: ldrmi    r0, [pc], #0x5b
0002cebc: andeq    lr, r0, sb, rrx
0002cec0: andeq    r0, fp, r0, ror #1
0002cec4: subeq    r0, r7, fp, lsr r0
0002cec8: addeq    r0, pc, fp, rrx
0002cecc: umlaleq  r0, r7, fp, r0
0002ced0: sbcseq   r0, r8, r1, asr #1
0002ced4: blle     #0x173870c
0002ced8: andls    r2, r0, #12, #4
0002cedc: stcne    p2, c2, [r3], #-0x40
0002cee0: stmdals  r5, {r0, r3, r5, sl, fp, ip}
0002cee4: .byte    0x00, 0xf0, 0xe0, 0xf8
0002cee8: stcne    p12, c1, [r0], #-0x1c
0002ceec: andlo    r7, r1, r1, lsl #16
0002cef0: mvnsle   r2, r0, lsl #18
0002cef4: adcmi    r3, r0, #0x10000
0002cef8: stmdavc  r1, {r1, ip, lr, pc}
0002cefc: mvnsle   r2, lr, lsr #18
0002cf00: stmdbhs  lr!, {r0, fp, ip, sp, lr}
0002cf04: andhs    sp, r0, r0
0002cf08: mrsle    r2, apsr
0002cf0c: bicmi    r4, r7, #100, #22
0002cf10: .byte    0x32, 0x1c, 0x00, 0x21
0002cf14: ldmdavs  fp, {r0, r1, r3, r6, sl, lr}
0002cf18: .byte    0x20, 0x1c, 0xd3, 0xf7
0002cf1c: eors     pc, r8, r2, lsl #17
0002cf20: blmi     #0x17f3b28
0002cf24: stmdane  r0!, {r1, r4, r5, sb, fp, ip}
0002cf28: ldmdavs  fp, {r0, r1, r3, r6, sl, lr}
0002cf2c: .byte    0x00, 0x21, 0xd3, 0xf7
0002cf30: eor      pc, lr, r8, ror r8
0002cf34: blle     #0xb3879c
0002cf38: andls    r2, r0, #24, #4
0002cf3c: stcne    p2, c2, [r3], #-0x70
0002cf40: stmdals  r5, {r0, r3, r5, sl, fp, ip}
0002cf44: rfeia    #1!
0002cf48: eor      r1, r2, r7, lsl #24
0002cf4c: blle     #0x838764
0002cf50: andls    r2, r0, #4, #4
0002cf54: stcne    p2, c2, [r3], #-0x300
0002cf58: stmdals  r5, {r0, r3, r5, sl, fp, ip}
0002cf5c: .byte    0x00, 0xf0, 0xa4, 0xf8
0002cf60: stmdavs  r0!, {r0, r1, r2, sl, fp, ip}
0002cf64: andls    sl, r3, r0, lsl #22
0002cf68: andhs    sb, r0, r2
0002cf6c: bvc      #0xff650f78
0002cf70: stmdbge  r3, {r2, sb, sp}
0002cf74: bvc      #0xfe6493dc
0002cf78: bvc      #0x16494e0
0002cf7c: bvc      #0x6495e4
0002cf80: stmdals  r1, {r3, r4, r6, r7, r8, ip, sp, lr}
0002cf84: andls    r4, r3, r7, asr #22
0002cf88: ldmdavs  fp, {r0, r1, r3, r6, sl, lr}
0002cf8c: .byte    0x20, 0x1c, 0xd3, 0xf7
0002cf90: subs     pc, r4, r8, asr #16
0002cf94: blle     #0x14b87ac
0002cf98: andls    r2, r0, #4, #4
0002cf9c: stcne    p2, c2, [r3], #-0x310
0002cfa0: stmdals  r5, {r0, r3, r5, sl, fp, ip}
0002cfa4: .byte    0x00, 0xf0, 0x80, 0xf8
0002cfa8: stmdavs  r0!, {r0, r1, r2, sl, fp, ip}
0002cfac: andls    sl, r3, r0, lsl #22
0002cfb0: andhs    sb, r0, r2
0002cfb4: bvc      #0xff650fc0
0002cfb8: stmdbge  r3, {r2, sb, sp}
0002cfbc: bvc      #0xfe649424
0002cfc0: bvc      #0x1649528
0002cfc4: bvc      #0x64962c
0002cfc8: stmdals  r1, {r3, r4, r6, r7, r8, ip, sp, lr}
0002cfcc: andls    r4, r3, r5, lsr fp
0002cfd0: ldmdavs  fp, {r0, r1, r3, r6, sl, lr}
0002cfd4: .byte    0x20, 0x1c, 0xd3, 0xf7
0002cfd8: eors     pc, r0, r4, lsr #16
0002cfdc: blle     #0xbb8884
0002cfe0: andls    r2, r0, #40, #4
0002cfe4: stcne    p2, c2, [r3], #-0x160
0002cfe8: stmdals  r5, {r0, r3, r5, sl, fp, ip}
0002cfec: .byte    0x00, 0xf0, 0x5c, 0xf8
0002cff0: eor      r1, r4, r7, lsl #24
0002cff4: blle     #0x8b88fc
0002cff8: andls    r2, r0, #64, #4
0002cffc: stcne    p2, c2, [r3], #-0x200
0002d000: stmdals  r5, {r0, r3, r5, sl, fp, ip}
0002d004: .byte    0x00, 0xf0, 0x50, 0xf8
0002d008: ands     r1, r8, r7, lsl #24
0002d00c: blle     #0x5b881c
0002d010: andls    r2, r0, #0x20000000
0002d014: stcne    p2, c2, [r3], #-0x320
0002d018: stmdals  r5, {r0, r3, r5, sl, fp, ip}
0002d01c: .byte    0x00, 0xf0, 0x44, 0xf8
0002d020: stmdavc  r0!, {r0, r1, r2, sl, fp, ip}
0002d024: blge     #0x4b1b0
0002d028: stmdane  r0, {sb} ^
0002d02c: blmi     #0x78d894
0002d030: strbmi   r2, [fp], #-0x202
