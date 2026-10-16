; STATIC ONLY; SHA256 e08f93bebe133b700f2305bfbedd994b05cc8d04a5a854262af9ced956afbc03
; File offsets. Dispatch tables/literals are data, not instructions.

; reverse_ani_tables [0x22d74, 0x22e42)
00022d74 f8b5         push      {r3, r4, r5, r6, r7, lr}
00022d76 041c         adds      r4, r0, #0
00022d78 04f014fd     bl        #0x277a4
00022d7c 2070         strb      r0, [r4]
00022d7e 04f0dffd     bl        #0x27940
00022d82 6060         str       r0, [r4, #4]
00022d84 04f00efd     bl        #0x277a4
00022d88 2072         strb      r0, [r4, #8]
00022d8a 04f0f7fd     bl        #0x2797c
00022d8e e060         str       r0, [r4, #0xc]
00022d90 04f008fd     bl        #0x277a4
00022d94 051c         adds      r5, r0, #0
00022d96 2075         strb      r0, [r4, #0x14]
00022d98 4000         lsls      r0, r0, #1
00022d9a 04f0effa     bl        #0x2737c
00022d9e a061         str       r0, [r4, #0x18]
00022da0 a800         lsls      r0, r5, #2
00022da2 04f0ebfa     bl        #0x2737c
00022da6 6a1e         subs      r2, r5, #1
00022da8 e061         str       r0, [r4, #0x1c]
00022daa 0092         str       r2, [sp]
00022dac 2ed4         bmi       #0x22e0c
00022dae 04f0f9fc     bl        #0x277a4
00022db2 a169         ldr       r1, [r4, #0x18]
00022db4 009a         ldr       r2, [sp]
00022db6 8600         lsls      r6, r0, #2
00022db8 5200         lsls      r2, r2, #1
00022dba 8e52         strh      r6, [r1, r2]
00022dbc c000         lsls      r0, r0, #3
00022dbe 04f0ddfa     bl        #0x2737c
00022dc2 e169         ldr       r1, [r4, #0x1c]
00022dc4 009a         ldr       r2, [sp]
00022dc6 9500         lsls      r5, r2, #2
00022dc8 4851         str       r0, [r1, r5]
00022dca 371f         subs      r7, r6, #4
00022dcc 1ad4         bmi       #0x22e04
00022dce 04f0e9fc     bl        #0x277a4
00022dd2 e169         ldr       r1, [r4, #0x1c]
00022dd4 7e00         lsls      r6, r7, #1
00022dd6 4959         ldr       r1, [r1, r5]
00022dd8 8853         strh      r0, [r1, r6]
00022dda 04f073fd     bl        #0x278c4
00022dde e169         ldr       r1, [r4, #0x1c]
00022de0 4959         ldr       r1, [r1, r5]
00022de2 8919         adds      r1, r1, r6
00022de4 4880         strh      r0, [r1, #2]
00022de6 04f06dfd     bl        #0x278c4
00022dea e169         ldr       r1, [r4, #0x1c]
00022dec 4959         ldr       r1, [r1, r5]
00022dee 8919         adds      r1, r1, r6
00022df0 8880         strh      r0, [r1, #4]
00022df2 04f0d7fc     bl        #0x277a4
00022df6 e169         ldr       r1, [r4, #0x1c]
00022df8 0002         lsls      r0, r0, #8
00022dfa 4959         ldr       r1, [r1, r5]
00022dfc 8919         adds      r1, r1, r6
00022dfe c880         strh      r0, [r1, #6]
00022e00 043f         subs      r7, #4
00022e02 e4d5         bpl       #0x22dce
00022e04 009a         ldr       r2, [sp]
00022e06 013a         subs      r2, #1
00022e08 0092         str       r2, [sp]
00022e0a d0d5         bpl       #0x22dae
00022e0c 04f0cafc     bl        #0x277a4
00022e10 051c         adds      r5, r0, #0
00022e12 2020         movs      r0, #0x20
00022e14 0555         strb      r5, [r0, r4]
00022e16 281c         adds      r0, r5, #0
00022e18 04f0b0fa     bl        #0x2737c
00022e1c 6062         str       r0, [r4, #0x24]
00022e1e a800         lsls      r0, r5, #2
00022e20 04f0acfa     bl        #0x2737c
00022e24 a062         str       r0, [r4, #0x28]
00022e26 013d         subs      r5, #1
00022e28 0ad4         bmi       #0x22e40
00022e2a 04f0bbfc     bl        #0x277a4
00022e2e 616a         ldr       r1, [r4, #0x24]
00022e30 4855         strb      r0, [r1, r5]
00022e32 04f0a3fd     bl        #0x2797c
00022e36 aa00         lsls      r2, r5, #2
00022e38 a16a         ldr       r1, [r4, #0x28]
00022e3a 013d         subs      r5, #1
00022e3c 8850         str       r0, [r1, r2]
00022e3e f4d5         bpl       #0x22e2a
00022e40 f8bd         pop       {r3, r4, r5, r6, r7, pc}

; event_mask_loading [0x22b78, 0x22bd8)
00022b78 70b5         push      {r4, r5, r6, lr}
00022b7a 061c         adds      r6, r0, #0
00022b7c 5020         movs      r0, #0x50
00022b7e 04f0fdfb     bl        #0x2737c
00022b82 041c         adds      r4, r0, #0
00022b84 0120         movs      r0, #1
00022b86 04f0f9fb     bl        #0x2737c
00022b8a e064         str       r0, [r4, #0x4c]
00022b8c 201c         adds      r0, r4, #0
00022b8e 00f0f1f8     bl        #0x22d74
00022b92 04f0e9fa     bl        #0x27168
00022b96 0028         cmp       r0, #0
00022b98 06d1         bne       #0x22ba8
00022b9a 04f003fe     bl        #0x277a4
00022b9e 4021         movs      r1, #0x40
00022ba0 0855         strb      r0, [r1, r4]
00022ba2 04f067fe     bl        #0x27874
00022ba6 6064         str       r0, [r4, #0x44]
00022ba8 04f0defa     bl        #0x27168
00022bac 0028         cmp       r0, #0
00022bae 07d1         bne       #0x22bc0
00022bb0 04f0f8fd     bl        #0x277a4
00022bb4 251c         adds      r5, r4, #0
00022bb6 4035         adds      r5, #0x40
00022bb8 2872         strb      r0, [r5, #8]
00022bba 04f0f3fd     bl        #0x277a4
00022bbe 6872         strb      r0, [r5, #9]
00022bc0 02f078fc     bl        #0x254b4
00022bc4 311c         adds      r1, r6, #0
00022bc6 201c         adds      r0, r4, #0
00022bc8 00f03cf9     bl        #0x22e44
00022bcc 0249         ldr       r1, [pc, #8]
00022bce 0020         movs      r0, #0
00022bd0 4944         add       r1, sb
00022bd2 0870         strb      r0, [r1]
00022bd4 201c         adds      r0, r4, #0
00022bd6 70bd         pop       {r4, r5, r6, pc}

; event_mask_trigger [0x22aa8, 0x22b3c)
00022aa8 011c         adds      r1, r0, #0
00022aaa 426c         ldr       r2, [r0, #0x44]
00022aac 2030         adds      r0, #0x20
00022aae 3031         adds      r1, #0x30
00022ab0 002a         cmp       r2, #0
00022ab2 10d0         beq       #0x22ad6
00022ab4 497b         ldrb      r1, [r1, #0xd]
00022ab6 0029         cmp       r1, #0
00022ab8 09d1         bne       #0x22ace
00022aba 017b         ldrb      r1, [r0, #0xc]
00022abc 8900         lsls      r1, r1, #2
00022abe 5158         ldr       r1, [r2, r1]
00022ac0 427b         ldrb      r2, [r0, #0xd]
00022ac2 0120         movs      r0, #1
00022ac4 9040         lsls      r0, r2
00022ac6 0140         ands      r1, r0
00022ac8 01d0         beq       #0x22ace
00022aca 0120         movs      r0, #1
00022acc 00e0         b         #0x22ad0
00022ace 0020         movs      r0, #0
00022ad0 0006         lsls      r0, r0, #0x18
00022ad2 0016         asrs      r0, r0, #0x18
00022ad4 7047         bx        lr
00022ad6 097b         ldrb      r1, [r1, #0xc]
00022ad8 407b         ldrb      r0, [r0, #0xd]
00022ada 4908         lsrs      r1, r1, #1
00022adc 0139         subs      r1, #1
00022ade 8142         cmp       r1, r0
00022ae0 01d1         bne       #0x22ae6
00022ae2 0120         movs      r0, #1
00022ae4 7047         bx        lr
00022ae6 0020         movs      r0, #0
00022ae8 7047         bx        lr
00022aea 0000         movs      r0, r0
00022aec 0028         cmp       r0, #0
00022aee 03d0         beq       #0x22af8
00022af0 2030         adds      r0, #0x20
00022af2 0078         ldrb      r0, [r0]
00022af4 0028         cmp       r0, #0
00022af6 01d1         bne       #0x22afc
00022af8 0120         movs      r0, #1
00022afa 00e0         b         #0x22afe
00022afc 0020         movs      r0, #0
00022afe 0006         lsls      r0, r0, #0x18
00022b00 0016         asrs      r0, r0, #0x18
00022b02 7047         bx        lr
00022b04 031c         adds      r3, r0, #0
00022b06 2033         adds      r3, #0x20
00022b08 597b         ldrb      r1, [r3, #0xd]
00022b0a 426c         ldr       r2, [r0, #0x44]
00022b0c 002a         cmp       r2, #0
00022b0e 0bd0         beq       #0x22b28
00022b10 187b         ldrb      r0, [r3, #0xc]
00022b12 0131         adds      r1, #1
00022b14 8000         lsls      r0, r0, #2
00022b16 1058         ldr       r0, [r2, r0]
00022b18 0122         movs      r2, #1
00022b1a 8a40         lsls      r2, r1
00022b1c 9042         cmp       r0, r2
00022b1e 01da         bge       #0x22b24
00022b20 0120         movs      r0, #1
00022b22 7047         bx        lr
00022b24 0020         movs      r0, #0
00022b26 7047         bx        lr
00022b28 3030         adds      r0, #0x30
00022b2a 007b         ldrb      r0, [r0, #0xc]
00022b2c 4008         lsrs      r0, r0, #1
00022b2e 0138         subs      r0, #1
00022b30 8842         cmp       r0, r1
00022b32 01d1         bne       #0x22b38
00022b34 0120         movs      r0, #1
00022b36 7047         bx        lr
00022b38 0020         movs      r0, #0
00022b3a 7047         bx        lr

; native_sequence_selection [0x22fc8, 0x2301c)
00022fc8 f0b4         push      {r4, r5, r6, r7}
00022fca 0028         cmp       r0, #0
00022fcc 0ad0         beq       #0x22fe4
00022fce 0029         cmp       r1, #0
00022fd0 08db         blt       #0x22fe4
00022fd2 041c         adds      r4, r0, #0
00022fd4 2034         adds      r4, #0x20
00022fd6 2378         ldrb      r3, [r4]
00022fd8 8b42         cmp       r3, r1
00022fda 03dd         ble       #0x22fe4
00022fdc 456a         ldr       r5, [r0, #0x24]
00022fde 6b5c         ldrb      r3, [r5, r1]
00022fe0 002b         cmp       r3, #0
00022fe2 02d1         bne       #0x22fea
00022fe4 0020         movs      r0, #0
00022fe6 f0bc         pop       {r4, r5, r6, r7}
00022fe8 7047         bx        lr
00022fea 2173         strb      r1, [r4, #0xc]
00022fec 836a         ldr       r3, [r0, #0x28]
00022fee 8e00         lsls      r6, r1, #2
00022ff0 9b59         ldr       r3, [r3, r6]
00022ff2 0026         movs      r6, #0
00022ff4 8363         str       r3, [r0, #0x38]
00022ff6 6d5c         ldrb      r5, [r5, r1]
00022ff8 011c         adds      r1, r0, #0
00022ffa 3031         adds      r1, #0x30
00022ffc 0d73         strb      r5, [r1, #0xc]
00022ffe 1b78         ldrb      r3, [r3]
00023000 c569         ldr       r5, [r0, #0x1c]
00023002 9f00         lsls      r7, r3, #2
00023004 ed59         ldr       r5, [r5, r7]
00023006 5b00         lsls      r3, r3, #1
00023008 0563         str       r5, [r0, #0x30]
0002300a 8569         ldr       r5, [r0, #0x18]
0002300c eb5a         ldrh      r3, [r5, r3]
0002300e 8386         strh      r3, [r0, #0x34]
00023010 6673         strb      r6, [r4, #0xd]
00023012 4e73         strb      r6, [r1, #0xd]
00023014 8a73         strb      r2, [r1, #0xe]
00023016 0120         movs      r0, #1
00023018 c873         strb      r0, [r1, #0xf]
0002301a e4e7         b         #0x22fe6

; state_dispatch_and_target_origin [0x245c0, 0x24694)
000245c0 f8b5         push      {r3, r4, r5, r6, r7, lr}
000245c2 041c         adds      r4, r0, #0
000245c4 481f         subs      r0, r1, #5
000245c6 0027         movs      r7, #0
000245c8 0e1c         adds      r6, r1, #0
000245ca 0d1c         adds      r5, r1, #0
000245cc 0f28         cmp       r0, #0xf
000245ce 12d2         bhs       #0x245f6
000245d0 01a3         adr       r3, #4
000245d2 1b5c         ldrb      r3, [r3, r0]
000245d4 5b00         lsls      r3, r3, #1
000245d6 9f44         add       pc, r3
000245d8 0707         lsls      r7, r0, #0x1c
000245da 0707         lsls      r7, r0, #0x1c
000245dc 070e         lsrs      r7, r0, #0x18
000245de 0e0e         lsrs      r6, r1, #0x18
000245e0 0907         lsls      r1, r1, #0x1c
000245e2 071d         adds      r7, r0, #4
000245e4 070e         lsrs      r7, r0, #0x18
000245e6 0700         movs      r7, r0
000245e8 0127         movs      r7, #1
000245ea 04e0         b         #0x245f6
000245ec a17b         ldrb      r1, [r4, #0xe]
000245ee 0127         movs      r7, #1
000245f0 0d29         cmp       r1, #0xd
000245f2 00d1         bne       #0x245f6
000245f4 0027         movs      r7, #0
000245f6 0f28         cmp       r0, #0xf
000245f8 3bd2         bhs       #0x24672
000245fa 02a3         adr       r3, #8
000245fc 1b5c         ldrb      r3, [r3, r0]
000245fe 5b00         lsls      r3, r3, #1
00024600 9f44         add       pc, r3
00024602 0000         movs      r0, r0
00024604 192f         cmp       r7, #0x19
00024606 3737         adds      r7, #0x37
00024608 3737         adds      r7, #0x37
0002460a 3737         adds      r7, #0x37
0002460c 2424         movs      r4, #0x24
0002460e 3837         adds      r7, #0x38
00024610 1714         asrs      r7, r2, #0x10
00024612 2200         movs      r2, r4
00024614 1020         movs      r0, #0x10
00024616 a073         strb      r0, [r4, #0xe]
00024618 0122         movs      r2, #1
0002461a 0021         movs      r1, #0
0002461c e06a         ldr       r0, [r4, #0x2c]
0002461e fef7d3fc     bl        #0x22fc8
00024622 0921         movs      r1, #9
00024624 e06a         ldr       r0, [r4, #0x2c]
00024626 fef705fd     bl        #0x23034
0002462a f8bd         pop       {r3, r4, r5, r6, r7, pc}
0002462c 0025         movs      r5, #0
0002462e ed43         mvns      r5, r5
00024630 1fe0         b         #0x24672
00024632 3220         movs      r0, #0x32
00024634 0557         ldrsb     r5, [r0, r4]
00024636 a06c         ldr       r0, [r4, #0x48]
00024638 fcf714fc     bl        #0x20e64
0002463c 211c         adds      r1, r4, #0
0002463e 1831         adds      r1, #0x18
00024640 1030         adds      r0, #0x10
00024642 0af0ddfb     bl        #0x2ee00
00024646 14e0         b         #0x24672
00024648 0725         movs      r5, #7
0002464a 12e0         b         #0x24672
0002464c 6068         ldr       r0, [r4, #4]
0002464e 05f037fd     bl        #0x2a0c0
00024652 0028         cmp       r0, #0
00024654 01d0         beq       #0x2465a
00024656 0320         movs      r0, #3
00024658 00e0         b         #0x2465c
0002465a 0120         movs      r0, #1
0002465c 0506         lsls      r5, r0, #0x18
0002465e 2d16         asrs      r5, r5, #0x18
00024660 07e0         b         #0x24672
00024662 a07b         ldrb      r0, [r4, #0xe]
00024664 0828         cmp       r0, #8
00024666 03d0         beq       #0x24670
00024668 0a28         cmp       r0, #0xa
0002466a 01d0         beq       #0x24670
0002466c 0928         cmp       r0, #9
0002466e 00d1         bne       #0x24672
00024670 0926         movs      r6, #9
00024672 00e0         b         #0x24676
00024674 0025         movs      r5, #0
00024676 a673         strb      r6, [r4, #0xe]
00024678 6068         ldr       r0, [r4, #4]
0002467a 016b         ldr       r1, [r0, #0x30]
0002467c 0968         ldr       r1, [r1]
0002467e 0029         cmp       r1, #0
00024680 01d1         bne       #0x24686
00024682 e06a         ldr       r0, [r4, #0x2c]
00024684 00e0         b         #0x24688
00024686 c06c         ldr       r0, [r0, #0x4c]
00024688 3a1c         adds      r2, r7, #0
0002468a 291c         adds      r1, r5, #0
0002468c fef79cfc     bl        #0x22fc8
00024690 cbe7         b         #0x2462a
00024692 0000         movs      r0, r0

; attack_event_delivery [0x39d0, 0x3a68)
000039d0 f8b5         push      {r3, r4, r5, r6, r7, lr}
000039d2 041c         adds      r4, r0, #0
000039d4 406c         ldr       r0, [r0, #0x44]
000039d6 0e1c         adds      r6, r1, #0
000039d8 1af00af9     bl        #0x1dbf0
000039dc 051c         adds      r5, r0, #0
000039de 2bd0         beq       #0x3a38
000039e0 2d20         movs      r0, #0x2d
000039e2 805d         ldrb      r0, [r0, r6]
000039e4 6f68         ldr       r7, [r5, #4]
000039e6 0128         cmp       r0, #1
000039e8 0cd1         bne       #0x3a04
000039ea 291c         adds      r1, r5, #0
000039ec 381c         adds      r0, r7, #0
000039ee 20f0edfc     bl        #0x243cc
000039f2 0028         cmp       r0, #0
000039f4 06d0         beq       #0x3a04
000039f6 6068         ldr       r0, [r4, #4]
000039f8 c06c         ldr       r0, [r0, #0x4c]
000039fa 3030         adds      r0, #0x30
000039fc 007b         ldrb      r0, [r0, #0xc]
000039fe 4008         lsrs      r0, r0, #1
00003a00 2521         movs      r1, #0x25
00003a02 4855         strb      r0, [r1, r5]
00003a04 301c         adds      r0, r6, #0
00003a06 1ff04ff8     bl        #0x22aa8
00003a0a 0028         cmp       r0, #0
00003a0c 14d0         beq       #0x3a38
00003a0e 2878         ldrb      r0, [r5]
00003a10 0328         cmp       r0, #3
00003a12 12d1         bne       #0x3a3a
00003a14 287a         ldrb      r0, [r5, #8]
00003a16 0028         cmp       r0, #0
00003a18 0fd1         bne       #0x3a3a
00003a1a 1348         ldr       r0, [pc, #0x4c]
00003a1c 0021         movs      r1, #0
00003a1e 4844         add       r0, sb
00003a20 c06a         ldr       r0, [r0, #0x2c]
00003a22 1ff001fb     bl        #0x23028
00003a26 301c         adds      r0, r6, #0
00003a28 1ff06cf8     bl        #0x22b04
00003a2c 0028         cmp       r0, #0
00003a2e 04d1         bne       #0x3a3a
00003a30 0621         movs      r1, #6
00003a32 381c         adds      r0, r7, #0
00003a34 20f0c4fd     bl        #0x245c0
00003a38 f8bd         pop       {r3, r4, r5, r6, r7, pc}
00003a3a 606c         ldr       r0, [r4, #0x44]
00003a3c 1af0c4f8     bl        #0x1dbc8
00003a40 0028         cmp       r0, #0
00003a42 f9d1         bne       #0x3a38
00003a44 084e         ldr       r6, [pc, #0x20]
00003a46 4e44         add       r6, sb
00003a48 606c         ldr       r0, [r4, #0x44]
00003a4a 1af0dbf8     bl        #0x1dc04
00003a4e 051c         adds      r5, r0, #0
00003a50 20f006fa     bl        #0x23e60
00003a54 291c         adds      r1, r5, #0
00003a56 306d         ldr       r0, [r6, #0x50]
00003a58 1df05cf9     bl        #0x20d14
00003a5c 606c         ldr       r0, [r4, #0x44]
00003a5e 1af0b3f8     bl        #0x1dbc8
00003a62 0028         cmp       r0, #0
00003a64 f0d0         beq       #0x3a48
00003a66 e7e7         b         #0x3a38

; action_completion [0x2be4, 0x2c38)
00002be4 38b5         push      {r3, r4, r5, lr}
00002be6 041c         adds      r4, r0, #0
00002be8 0e23         movs      r3, #0xe
00002bea c056         ldrsb     r0, [r0, r3]
00002bec 0025         movs      r5, #0
00002bee ed43         mvns      r5, r5
00002bf0 0538         subs      r0, #5
00002bf2 0f28         cmp       r0, #0xf
00002bf4 40d2         bhs       #0x2c78
00002bf6 02a3         adr       r3, #8
00002bf8 1b5c         ldrb      r3, [r3, r0]
00002bfa 5b00         lsls      r3, r3, #1
00002bfc 9f44         add       pc, r3
00002bfe 0000         movs      r0, r0
00002c00 1257         ldrsb     r2, [r2, r4]
00002c02 1c59         ldr       r4, [r3, r4]
00002c04 593c         subs      r4, #0x59
00002c06 3c3c         subs      r4, #0x3c
00002c08 5f5b         ldrh      r7, [r3, r5]
00002c0a 083c         subs      r4, #8
00002c0c 3c3c         subs      r4, #0x3c
00002c0e 4300         lsls      r3, r0, #1
00002c10 3348         ldr       r0, [pc, #0xcc]
00002c12 1025         movs      r5, #0x10
00002c14 4844         add       r0, sb
00002c16 c06b         ldr       r0, [r0, #0x3c]
00002c18 8442         cmp       r4, r0
00002c1a 2fd1         bne       #0x2c7c
00002c1c 201c         adds      r0, r4, #0
00002c1e 00f041f9     bl        #0x2ea4
00002c22 2be0         b         #0x2c7c
00002c24 211c         adds      r1, r4, #0
00002c26 1831         adds      r1, #0x18
00002c28 201c         adds      r0, r4, #0
00002c2a 1030         adds      r0, #0x10
00002c2c 2cf0e8f8     bl        #0x2ee00
00002c30 201c         adds      r0, r4, #0
00002c32 00f037f9     bl        #0x2ea4
00002c36 38bd         pop       {r3, r4, r5, pc}

; restore_home_and_ready [0x2ea4, 0x2ed6)
00002ea4 10b5         push      {r4, lr}
00002ea6 011c         adds      r1, r0, #0
00002ea8 1831         adds      r1, #0x18
00002eaa 041c         adds      r4, r0, #0
00002eac 1030         adds      r0, #0x10
00002eae 2bf0a7ff     bl        #0x2ee00
00002eb2 201c         adds      r0, r4, #0
00002eb4 21f0bafa     bl        #0x2442c
00002eb8 0028         cmp       r0, #0
00002eba 04d1         bne       #0x2ec6
00002ebc 0421         movs      r1, #4
00002ebe e173         strb      r1, [r4, #0xf]
00002ec0 201c         adds      r0, r4, #0
00002ec2 21f07dfb     bl        #0x245c0
00002ec6 0448         ldr       r0, [pc, #0x10]
00002ec8 0021         movs      r1, #0
00002eca 4844         add       r0, sb
00002ecc 8163         str       r1, [r0, #0x38]
00002ece 8179         ldrb      r1, [r0, #6]
00002ed0 0131         adds      r1, #1
00002ed2 8171         strb      r1, [r0, #6]
00002ed4 10bd         pop       {r4, pc}

; copy_coordinates_source_to_destination [0x2ee00, 0x2ee0a)
0002ee00 0268         ldr       r2, [r0]
0002ee02 0a60         str       r2, [r1]
0002ee04 4068         ldr       r0, [r0, #4]
0002ee06 4860         str       r0, [r1, #4]
0002ee08 7047         bx        lr
