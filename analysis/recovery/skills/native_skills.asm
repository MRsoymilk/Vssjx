; Native Online v48 skill record evidence. Data payloads are NOT embedded skill definitions.
; SHA256 e08f93bebe133b700f2305bfbedd994b05cc8d04a5a854262af9ced956afbc03

; skill_record_decoder [0x2fe50,0x2ffae)
0002fe50 f8b5       push     {r3, r4, r5, r6, r7, lr}
0002fe52 5020       movs     r0, #0x50
0002fe54 f7f792fa   bl       #0x2737c
0002fe58 041c       adds     r4, r0, #0
0002fe5a 251c       adds     r5, r4, #0
0002fe5c ff20       movs     r0, #0xff
0002fe5e 2035       adds     r5, #0x20
0002fe60 e870       strb     r0, [r5, #3]
0002fe62 f7f745fd   bl       #0x278f0
0002fe66 2060       str      r0, [r4]
0002fe68 f7f742fd   bl       #0x278f0
0002fe6c 6060       str      r0, [r4, #4]
0002fe6e f7f73ffd   bl       #0x278f0
0002fe72 a060       str      r0, [r4, #8]
0002fe74 f7f7acfc   bl       #0x277d0
0002fe78 2074       strb     r0, [r4, #0x10]
0002fe7a 207c       ldrb     r0, [r4, #0x10]
0002fe7c ff28       cmp      r0, #0xff
0002fe7e 03d1       bne      #0x2fe88
0002fe80 0020       movs     r0, #0
0002fe82 6074       strb     r0, [r4, #0x11]
0002fe84 201c       adds     r0, r4, #0
0002fe86 f8bd       pop      {r3, r4, r5, r6, r7, pc}
0002fe88 f7f7a2fc   bl       #0x277d0
0002fe8c 6074       strb     r0, [r4, #0x11]
0002fe8e f7f719fd   bl       #0x278c4
0002fe92 a081       strh     r0, [r4, #0xc]
0002fe94 f7f79cfc   bl       #0x277d0
0002fe98 e073       strb     r0, [r4, #0xf]
0002fe9a f7f799fc   bl       #0x277d0
0002fe9e a073       strb     r0, [r4, #0xe]
0002fea0 0120       movs     r0, #1
0002fea2 a870       strb     r0, [r5, #2]
0002fea4 f7f794fc   bl       #0x277d0
0002fea8 ff30       adds     r0, #0xff
0002feaa 0706       lsls     r7, r0, #0x18
0002feac 3f16       asrs     r7, r7, #0x18
0002feae 24d4       bmi      #0x2fefa
0002feb0 211c       adds     r1, r4, #0
0002feb2 4031       adds     r1, #0x40
0002feb4 261c       adds     r6, r4, #0
0002feb6 3036       adds     r6, #0x30
0002feb8 0091       str      r1, [sp]
0002feba f7f789fc   bl       #0x277d0
0002febe 0128       cmp      r0, #1
0002fec0 00d0       beq      #0x2fec4
0002fec2 a870       strb     r0, [r5, #2]
0002fec4 0028       cmp      r0, #0
0002fec6 1dd0       beq      #0x2ff04
0002fec8 0128       cmp      r0, #1
0002feca 31d0       beq      #0x2ff30
0002fecc 0328       cmp      r0, #3
0002fece 4ad0       beq      #0x2ff66
0002fed0 0628       cmp      r0, #6
0002fed2 0ed1       bne      #0x2fef2
0002fed4 f7f77cfc   bl       #0x277d0
0002fed8 e870       strb     r0, [r5, #3]
0002feda f7f7f3fc   bl       #0x278c4
0002fede a084       strh     r0, [r4, #0x24]
0002fee0 f7f7f0fc   bl       #0x278c4
0002fee4 e084       strh     r0, [r4, #0x26]
0002fee6 f7f7edfc   bl       #0x278c4
0002feea 2085       strh     r0, [r4, #0x28]
0002feec f7f7eafc   bl       #0x278c4
0002fef0 6085       strh     r0, [r4, #0x2a]
0002fef2 ff37       adds     r7, #0xff
0002fef4 3f06       lsls     r7, r7, #0x18
0002fef6 3f16       asrs     r7, r7, #0x18
0002fef8 dfd5       bpl      #0x2feba
0002fefa a07b       ldrb     r0, [r4, #0xe]
0002fefc 0128       cmp      r0, #1
0002fefe 3cd0       beq      #0x2ff7a
0002ff00 201c       adds     r0, r4, #0
0002ff02 c0e7       b        #0x2fe86
0002ff04 f7f764fc   bl       #0x277d0
0002ff08 e870       strb     r0, [r5, #3]
0002ff0a f7f7dbfc   bl       #0x278c4
0002ff0e a084       strh     r0, [r4, #0x24]
0002ff10 f7f7d8fc   bl       #0x278c4
0002ff14 e084       strh     r0, [r4, #0x26]
0002ff16 f7f7d5fc   bl       #0x278c4
0002ff1a 2085       strh     r0, [r4, #0x28]
0002ff1c f7f7d2fc   bl       #0x278c4
0002ff20 6085       strh     r0, [r4, #0x2a]
0002ff22 f7f755fc   bl       #0x277d0
0002ff26 2873       strb     r0, [r5, #0xc]
0002ff28 f7f7ccfc   bl       #0x278c4
0002ff2c e085       strh     r0, [r4, #0x2e]
0002ff2e e0e7       b        #0x2fef2
0002ff30 f7f74efc   bl       #0x277d0
0002ff34 3070       strb     r0, [r6]
0002ff36 f7f7dbfc   bl       #0x278f0
0002ff3a 6063       str      r0, [r4, #0x34]
0002ff3c f7f748fc   bl       #0x277d0
0002ff40 3072       strb     r0, [r6, #8]
0002ff42 f7f7d5fc   bl       #0x278f0
0002ff46 e063       str      r0, [r4, #0x3c]
0002ff48 f7f7d2fc   bl       #0x278f0
0002ff4c 2064       str      r0, [r4, #0x40]
0002ff4e f7f73ffc   bl       #0x277d0
0002ff52 0099       ldr      r1, [sp]
0002ff54 0871       strb     r0, [r1, #4]
0002ff56 1649       ldr      r1, [pc, #0x58]
0002ff58 7944       add      r1, pc
0002ff5a 1648       ldr      r0, [pc, #0x58]
0002ff5c 7844       add      r0, pc
0002ff5e f0f751ff   bl       #0x20e04
0002ff62 a064       str      r0, [r4, #0x48]
0002ff64 c5e7       b        #0x2fef2
0002ff66 f7f733fc   bl       #0x277d0
0002ff6a e870       strb     r0, [r5, #3]
0002ff6c f7f7aafc   bl       #0x278c4
0002ff70 a084       strh     r0, [r4, #0x24]
0002ff72 f7f7a7fc   bl       #0x278c4
0002ff76 e084       strh     r0, [r4, #0x26]
0002ff78 bbe7       b        #0x2fef2
0002ff7a f7f729fc   bl       #0x277d0
0002ff7e a074       strb     r0, [r4, #0x12]
0002ff80 f7f71afc   bl       #0x277b8
0002ff84 e074       strb     r0, [r4, #0x13]
0002ff86 f7f723fc   bl       #0x277d0
0002ff8a 2075       strb     r0, [r4, #0x14]
0002ff8c f7f720fc   bl       #0x277d0
0002ff90 6075       strb     r0, [r4, #0x15]
0002ff92 f7f7adfc   bl       #0x278f0
0002ff96 a061       str      r0, [r4, #0x18]
0002ff98 f7f71afc   bl       #0x277d0
0002ff9c 2077       strb     r0, [r4, #0x1c]
0002ff9e f7f791fc   bl       #0x278c4
0002ffa2 e083       strh     r0, [r4, #0x1e]
0002ffa4 f7f78efc   bl       #0x278c4
0002ffa8 2084       strh     r0, [r4, #0x20]
0002ffaa 201c       adds     r0, r4, #0
0002ffac 6be7       b        #0x2fe86

; skill_list_bootstrap [0x2e50e,0x2e51e)
0002e50e 2249       ldr      r1, [pc, #0x88]
0002e510 7944       add      r1, pc
0002e512 2248       ldr      r0, [pc, #0x88]
0002e514 7844       add      r0, pc
0002e516 f2f775fc   bl       #0x20e04
0002e51a 2149       ldr      r1, [pc, #0x84]
0002e51c 4944       add      r1, sb

; skill_update [0x2e5f0,0x2e70c)
0002e5f0 f0b5       push     {r4, r5, r6, r7, lr}
0002e5f2 83b0       sub      sp, #0xc
0002e5f4 0020       movs     r0, #0
0002e5f6 0190       str      r0, [sp, #4]
0002e5f8 f9f7def8   bl       #0x277b8
0002e5fc 0090       str      r0, [sp]
0002e5fe 0028       cmp      r0, #0
0002e600 02d0       beq      #0x2e608
0002e602 f9f75ff9   bl       #0x278c4
0002e606 0190       str      r0, [sp, #4]
0002e608 01f022fc   bl       #0x2fe50
0002e60c 404e       ldr      r6, [pc, #0x100]
0002e60e 041c       adds     r4, r0, #0
0002e610 4e44       add      r6, sb
0002e612 3068       ldr      r0, [r6]
0002e614 f2f700fd   bl       #0x21018
0002e618 ff30       adds     r0, #0xff
0002e61a 0506       lsls     r5, r0, #0x18
0002e61c 2d16       asrs     r5, r5, #0x18
0002e61e 63d4       bmi      #0x2e6e8
0002e620 3b4e       ldr      r6, [pc, #0xec]
0002e622 291c       adds     r1, r5, #0
0002e624 4e44       add      r6, sb
0002e626 3068       ldr      r0, [r6]
0002e628 f2f70efc   bl       #0x20e48
0002e62c 0290       str      r0, [sp, #8]
0002e62e 2168       ldr      r1, [r4]
0002e630 0068       ldr      r0, [r0]
0002e632 f8f7b5fd   bl       #0x271a0
0002e636 0028       cmp      r0, #0
0002e638 52d0       beq      #0x2e6e0
0002e63a 364f       ldr      r7, [pc, #0xd8]
0002e63c 4f44       add      r7, sb
0002e63e 3868       ldr      r0, [r7]
0002e640 f2f7eafc   bl       #0x21018
0002e644 ff30       adds     r0, #0xff
0002e646 0606       lsls     r6, r0, #0x18
0002e648 3616       asrs     r6, r6, #0x18
0002e64a 2ad4       bmi      #0x2e6a2
0002e64c 314f       ldr      r7, [pc, #0xc4]
0002e64e 311c       adds     r1, r6, #0
0002e650 4f44       add      r7, sb
0002e652 3868       ldr      r0, [r7]
0002e654 f2f7f8fb   bl       #0x20e48
0002e658 071c       adds     r7, r0, #0
0002e65a 2168       ldr      r1, [r4]
0002e65c 0068       ldr      r0, [r0]
0002e65e f8f79ffd   bl       #0x271a0
0002e662 0028       cmp      r0, #0
0002e664 19d0       beq      #0x2e69a
0002e666 1023       movs     r3, #0x10
0002e668 e056       ldrsb    r0, [r4, r3]
0002e66a f956       ldrsb    r1, [r7, r3]
0002e66c 8842       cmp      r0, r1
0002e66e 02dd       ble      #0x2e676
0002e670 0020       movs     r0, #0
0002e672 c043       mvns     r0, r0
0002e674 00e0       b        #0x2e678
0002e676 0120       movs     r0, #1
0002e678 264f       ldr      r7, [pc, #0x98]
0002e67a b200       lsls     r2, r6, #2
0002e67c 4f44       add      r7, sb
0002e67e 3968       ldr      r1, [r7]
0002e680 0006       lsls     r0, r0, #0x18
0002e682 0968       ldr      r1, [r1]
0002e684 0016       asrs     r0, r0, #0x18
0002e686 8c50       str      r4, [r1, r2]
0002e688 2349       ldr      r1, [pc, #0x8c]
0002e68a 244a       ldr      r2, [pc, #0x90]
0002e68c 4944       add      r1, sb
0002e68e 0c60       str      r4, [r1]
0002e690 4a44       add      r2, sb
0002e692 1168       ldr      r1, [r2]
0002e694 0818       adds     r0, r1, r0
0002e696 1060       str      r0, [r2]
0002e698 03e0       b        #0x2e6a2
0002e69a ff36       adds     r6, #0xff
0002e69c 3606       lsls     r6, r6, #0x18
0002e69e 3616       asrs     r6, r6, #0x18
0002e6a0 d4d5       bpl      #0x2e64c
0002e6a2 02a8       add      r0, sp, #8
0002e6a4 01f088fc   bl       #0x2ffb8
0002e6a8 194e       ldr      r6, [pc, #0x64]
0002e6aa a900       lsls     r1, r5, #2
0002e6ac 4e44       add      r6, sb
0002e6ae 3068       ldr      r0, [r6]
0002e6b0 0068       ldr      r0, [r0]
0002e6b2 4450       str      r4, [r0, r1]
0002e6b4 207c       ldrb     r0, [r4, #0x10]
0002e6b6 ff28       cmp      r0, #0xff
0002e6b8 03d1       bne      #0x2e6c2
0002e6ba 291c       adds     r1, r5, #0
0002e6bc 3068       ldr      r0, [r6]
0002e6be f2f765fc   bl       #0x20f8c
0002e6c2 1748       ldr      r0, [pc, #0x5c]
0002e6c4 4844       add      r0, sb
0002e6c6 0068       ldr      r0, [r0]
0002e6c8 0028       cmp      r0, #0
0002e6ca 00d0       beq      #0x2e6ce
0002e6cc 8047       blx      r0
0002e6ce 0098       ldr      r0, [sp]
0002e6d0 0028       cmp      r0, #0
0002e6d2 03d0       beq      #0x2e6dc
0002e6d4 114a       ldr      r2, [pc, #0x44]
0002e6d6 0198       ldr      r0, [sp, #4]
0002e6d8 4a44       add      r2, sb
0002e6da 1060       str      r0, [r2]
0002e6dc 03b0       add      sp, #0xc
0002e6de f0bd       pop      {r4, r5, r6, r7, pc}
0002e6e0 ff35       adds     r5, #0xff
0002e6e2 2d06       lsls     r5, r5, #0x18
0002e6e4 2d16       asrs     r5, r5, #0x18
0002e6e6 9bd5       bpl      #0x2e620
0002e6e8 211c       adds     r1, r4, #0
0002e6ea 3068       ldr      r0, [r6]
0002e6ec f2f712fb   bl       #0x20d14
0002e6f0 0b48       ldr      r0, [pc, #0x2c]
0002e6f2 4844       add      r0, sb
0002e6f4 0068       ldr      r0, [r0]
0002e6f6 0028       cmp      r0, #0
0002e6f8 00d0       beq      #0x2e6fc
0002e6fa 8047       blx      r0
0002e6fc 0098       ldr      r0, [sp]
0002e6fe 0028       cmp      r0, #0
0002e700 03d0       beq      #0x2e70a
0002e702 064a       ldr      r2, [pc, #0x18]
0002e704 0198       ldr      r0, [sp, #4]
0002e706 4a44       add      r2, sb
0002e708 1060       str      r0, [r2]

; martial_inner_filter [0xed38,0xed9e)
0000ed38 70b5       push     {r4, r5, r6, lr}
0000ed3a 194d       ldr      r5, [pc, #0x64]
0000ed3c 061c       adds     r6, r0, #0
0000ed3e 4d44       add      r5, sb
0000ed40 a869       ldr      r0, [r5, #0x18]
0000ed42 82b0       sub      sp, #8
0000ed44 12f020f8   bl       #0x20d88
0000ed48 0024       movs     r4, #0
0000ed4a e868       ldr      r0, [r5, #0xc]
0000ed4c 12f064f9   bl       #0x21018
0000ed50 0028       cmp      r0, #0
0000ed52 13dd       ble      #0xed7c
0000ed54 211c       adds     r1, r4, #0
0000ed56 e868       ldr      r0, [r5, #0xc]
0000ed58 12f076f8   bl       #0x20e48
0000ed5c 0f23       movs     r3, #0xf
0000ed5e c156       ldrsb    r1, [r0, r3]
0000ed60 b142       cmp      r1, r6
0000ed62 03d1       bne      #0xed6c
0000ed64 011c       adds     r1, r0, #0
0000ed66 a869       ldr      r0, [r5, #0x18]
0000ed68 11f0d4ff   bl       #0x20d14
0000ed6c 0134       adds     r4, #1
0000ed6e 2406       lsls     r4, r4, #0x18
0000ed70 2416       asrs     r4, r4, #0x18
0000ed72 e868       ldr      r0, [r5, #0xc]
0000ed74 12f050f9   bl       #0x21018
0000ed78 a042       cmp      r0, r4
0000ed7a ebdc       bgt      #0xed54
0000ed7c 0020       movs     r0, #0
0000ed7e e861       str      r0, [r5, #0x1c]
0000ed80 a869       ldr      r0, [r5, #0x18]
0000ed82 12f049f9   bl       #0x21018
0000ed86 0090       str      r0, [sp]
0000ed88 0723       movs     r3, #7
0000ed8a 1522       movs     r2, #0x15
0000ed8c 3721       movs     r1, #0x37
0000ed8e 0420       movs     r0, #4
0000ed90 00f08afd   bl       #0xf8a8
0000ed94 0020       movs     r0, #0
0000ed96 00f0a9fd   bl       #0xf8ec
0000ed9a 02b0       add      sp, #8
0000ed9c 70bd       pop      {r4, r5, r6, pc}

; skill_list_draw [0xeba0,0xed16)
0000eba0 f0b5       push     {r4, r5, r6, r7, lr}
0000eba2 5d4d       ldr      r5, [pc, #0x174]
0000eba4 83b0       sub      sp, #0xc
0000eba6 4d44       add      r5, sb
0000eba8 686a       ldr      r0, [r5, #0x24]
0000ebaa 0024       movs     r4, #0
0000ebac fdf79efe   bl       #0xc8ec
0000ebb0 5a49       ldr      r1, [pc, #0x168]
0000ebb2 0022       movs     r2, #0
0000ebb4 0192       str      r2, [sp, #4]
0000ebb6 0091       str      r1, [sp]
0000ebb8 3221       movs     r1, #0x32
0000ebba 9b22       movs     r2, #0x9b
0000ebbc 0220       movs     r0, #2
0000ebbe 584b       ldr      r3, [pc, #0x160]
0000ebc0 17f044f9   bl       #0x25e4c
0000ebc4 574a       ldr      r2, [pc, #0x15c]
0000ebc6 5849       ldr      r1, [pc, #0x160]
0000ebc8 1320       movs     r0, #0x13
0000ebca 00f0cdfb   bl       #0xf368
0000ebce 4a25       movs     r5, #0x4a
0000ebd0 201c       adds     r0, r4, #0
0000ebd2 00f0edfc   bl       #0xf5b0
0000ebd6 0028       cmp      r0, #0
0000ebd8 43d0       beq      #0xec62
0000ebda 4f48       ldr      r0, [pc, #0x13c]
0000ebdc 211c       adds     r1, r4, #0
0000ebde 4844       add      r0, sb
0000ebe0 8069       ldr      r0, [r0, #0x18]
0000ebe2 00f091fc   bl       #0xf508
0000ebe6 061c       adds     r6, r0, #0
0000ebe8 201c       adds     r0, r4, #0
0000ebea 00f0fdfc   bl       #0xf5e8
0000ebee 0028       cmp      r0, #0
0000ebf0 0ed0       beq      #0xec10
0000ebf2 00f0cbfc   bl       #0xf58c
0000ebf6 071c       adds     r7, r0, #0
0000ebf8 083f       subs     r7, #8
0000ebfa 00f0cdfc   bl       #0xf598
0000ebfe 1523       movs     r3, #0x15
0000ec00 3a1c       adds     r2, r7, #0
0000ec02 e91a       subs     r1, r5, r3
0000ec04 12f072f8   bl       #0x20cec
0000ec08 4848       ldr      r0, [pc, #0x120]
0000ec0a 19f0a7f8   bl       #0x27d5c
0000ec0e 02e0       b        #0xec16
0000ec10 4748       ldr      r0, [pc, #0x11c]
0000ec12 19f0a3f8   bl       #0x27d5c
0000ec16 2423       movs     r3, #0x24
0000ec18 2a1c       adds     r2, r5, #0
0000ec1a 1021       movs     r1, #0x10
0000ec1c 7068       ldr      r0, [r6, #4]
0000ec1e 17f0d1fd   bl       #0x267c4
0000ec22 1023       movs     r3, #0x10
0000ec24 f056       ldrsb    r0, [r6, r3]
0000ec26 16f049fb   bl       #0x252bc
0000ec2a 2f20       movs     r0, #0x2f
0000ec2c 16f03afb   bl       #0x252a4
0000ec30 1123       movs     r3, #0x11
0000ec32 f056       ldrsb    r0, [r6, r3]
0000ec34 16f042fb   bl       #0x252bc
0000ec38 3520       movs     r0, #0x35
0000ec3a 11f087fe   bl       #0x2094c
0000ec3e 16f049fb   bl       #0x252d4
0000ec42 17f0efff   bl       #0x26c24
0000ec46 2823       movs     r3, #0x28
0000ec48 2a1c       adds     r2, r5, #0
0000ec4a da21       movs     r1, #0xda
0000ec4c 17f0bafd   bl       #0x267c4
0000ec50 0134       adds     r4, #1
0000ec52 2406       lsls     r4, r4, #0x18
0000ec54 2416       asrs     r4, r4, #0x18
0000ec56 1535       adds     r5, #0x15
0000ec58 201c       adds     r0, r4, #0
0000ec5a 00f0a9fc   bl       #0xf5b0
0000ec5e 0028       cmp      r0, #0
0000ec60 bbd1       bne      #0xebda
0000ec62 00f0c1fb   bl       #0xf3e8
0000ec66 0022       movs     r2, #0
0000ec68 0192       str      r2, [sp, #4]
0000ec6a 2c4c       ldr      r4, [pc, #0xb0]
0000ec6c 5722       movs     r2, #0x57
0000ec6e d021       movs     r1, #0xd0
0000ec70 0220       movs     r0, #2
0000ec72 2b4b       ldr      r3, [pc, #0xac]
0000ec74 0094       str      r4, [sp]
0000ec76 17f0e9f8   bl       #0x25e4c
0000ec7a 274d       ldr      r5, [pc, #0x9c]
0000ec7c 0026       movs     r6, #0
0000ec7e 4d44       add      r5, sb
0000ec80 e869       ldr      r0, [r5, #0x1c]
0000ec82 0028       cmp      r0, #0
0000ec84 1ed0       beq      #0xecc4
0000ec86 8068       ldr      r0, [r0, #8]
0000ec88 16f024fb   bl       #0x252d4
0000ec8c e869       ldr      r0, [r5, #0x1c]
0000ec8e 8089       ldrh     r0, [r0, #0xc]
0000ec90 0028       cmp      r0, #0
0000ec92 07d0       beq      #0xeca4
0000ec94 2620       movs     r0, #0x26
0000ec96 10f0d9fb   bl       #0x1f44c
0000ec9a e969       ldr      r1, [r5, #0x1c]
0000ec9c 0c23       movs     r3, #0xc
0000ec9e c95e       ldrsh    r1, [r1, r3]
0000eca0 16f080fb   bl       #0x253a4
0000eca4 5722       movs     r2, #0x57
0000eca6 d021       movs     r1, #0xd0
0000eca8 0c20       movs     r0, #0xc
0000ecaa 19f047f8   bl       #0x27d3c
0000ecae 17f0b9ff   bl       #0x26c24
0000ecb2 1f4a       ldr      r2, [pc, #0x7c]
0000ecb4 331c       adds     r3, r6, #0
0000ecb6 0092       str      r2, [sp]
0000ecb8 dc22       movs     r2, #0xdc
0000ecba 0c21       movs     r1, #0xc
0000ecbc 17f010f9   bl       #0x25ee0
0000ecc0 18f024ff   bl       #0x27b0c
0000ecc4 ff21       movs     r1, #0xff
0000ecc6 2b31       adds     r1, #0x2b
0000ecc8 1323       movs     r3, #0x13
0000ecca 6d22       movs     r2, #0x6d
0000eccc 4020       movs     r0, #0x40
0000ecce 0094       str      r4, [sp]
0000ecd0 17f0fcfd   bl       #0x268cc
0000ecd4 1b20       movs     r0, #0x1b
0000ecd6 10f0b9fb   bl       #0x1f44c
0000ecda 154a       ldr      r2, [pc, #0x54]
0000ecdc 331c       adds     r3, r6, #0
0000ecde 0092       str      r2, [sp]
0000ece0 ff22       movs     r2, #0xff
0000ece2 2e32       adds     r2, #0x2e
0000ece4 5221       movs     r1, #0x52
0000ece6 17f0fbf8   bl       #0x25ee0
0000ecea 2869       ldr      r0, [r5, #0x10]
0000ecec c117       asrs     r1, r0, #0x1f
0000ecee 16f01bf9   bl       #0x24f28
0000ecf2 104a       ldr      r2, [pc, #0x40]
0000ecf4 331c       adds     r3, r6, #0
0000ecf6 0092       str      r2, [sp]
0000ecf8 ff22       movs     r2, #0xff
0000ecfa 2e32       adds     r2, #0x2e
0000ecfc 8621       movs     r1, #0x86
0000ecfe 17f0eff8   bl       #0x25ee0
0000ed02 686a       ldr      r0, [r5, #0x24]
0000ed04 fdf7f8fd   bl       #0xc8f8
0000ed08 2320       movs     r0, #0x23
0000ed0a 11f01ffe   bl       #0x2094c
0000ed0e 0ef043fe   bl       #0x1d998
0000ed12 03b0       add      sp, #0xc
0000ed14 f0bd       pop      {r4, r5, r6, r7, pc}

; upgrade_downgrade_request [0xdf64,0xdfde)
0000df64 70b5       push     {r4, r5, r6, lr}
0000df66 09f073fe   bl       #0x17c50
0000df6a 1d4c       ldr      r4, [pc, #0x74]
0000df6c 0028       cmp      r0, #0
0000df6e 4c44       add      r4, sb
0000df70 14d1       bne      #0xdf9c
0000df72 2169       ldr      r1, [r4, #0x10]
0000df74 c043       mvns     r0, r0
0000df76 0029       cmp      r1, #0
0000df78 00d1       bne      #0xdf7c
0000df7a 2420       movs     r0, #0x24
0000df7c e169       ldr      r1, [r4, #0x1c]
0000df7e 0a7c       ldrb     r2, [r1, #0x10]
0000df80 497c       ldrb     r1, [r1, #0x11]
0000df82 8a42       cmp      r2, r1
0000df84 01d1       bne      #0xdf8a
0000df86 2520       movs     r0, #0x25
0000df88 01e0       b        #0xdf8e
0000df8a 0028       cmp      r0, #0
0000df8c 06db       blt      #0xdf9c
0000df8e 10f01bfe   bl       #0x1ebc8
0000df92 011c       adds     r1, r0, #0
0000df94 0220       movs     r0, #2
0000df96 08f055f8   bl       #0x16044
0000df9a 70bd       pop      {r4, r5, r6, pc}
0000df9c e069       ldr      r0, [r4, #0x1c]
0000df9e 1023       movs     r3, #0x10
0000dfa0 c056       ldrsb    r0, [r0, r3]
0000dfa2 0725       movs     r5, #7
0000dfa4 2d06       lsls     r5, r5, #0x18
0000dfa6 6e1d       adds     r6, r5, #5
0000dfa8 0128       cmp      r0, #1
0000dfaa 0bdd       ble      #0xdfc4
0000dfac 09f050fe   bl       #0x17c50
0000dfb0 331c       adds     r3, r6, #0
0000dfb2 9a1c       adds     r2, r3, #2
0000dfb4 291c       adds     r1, r5, #0
0000dfb6 11f057fa   bl       #0x1f468
0000dfba e169       ldr      r1, [r4, #0x1c]
0000dfbc 0968       ldr      r1, [r1]
0000dfbe 0af083fd   bl       #0x18ac8
0000dfc2 09e0       b        #0xdfd8
0000dfc4 09f044fe   bl       #0x17c50
0000dfc8 321c       adds     r2, r6, #0
0000dfca 291c       adds     r1, r5, #0
0000dfcc 11f04cfa   bl       #0x1f468
0000dfd0 e169       ldr      r1, [r4, #0x1c]
0000dfd2 0968       ldr      r1, [r1]
0000dfd4 0af078fd   bl       #0x18ac8
0000dfd8 0bf050f8   bl       #0x1907c
0000dfdc 70bd       pop      {r4, r5, r6, pc}

; battle_usable_filter [0x2b30,0x2b76)
00002b30 211c       adds     r1, r4, #0
00002b32 2868       ldr      r0, [r5]
00002b34 1ef088f9   bl       #0x20e48
00002b38 2749       ldr      r1, [pc, #0x9c]
00002b3a 4944       add      r1, sb
00002b3c 0860       str      r0, [r1]
00002b3e 011c       adds     r1, r0, #0
00002b40 807b       ldrb     r0, [r0, #0xe]
00002b42 0128       cmp      r0, #1
00002b44 05d1       bne      #0x2b52
00002b46 2148       ldr      r0, [pc, #0x84]
00002b48 4844       add      r0, sb
00002b4a 0068       ldr      r0, [r0]
00002b4c 1ef0e2f8   bl       #0x20d14
00002b50 11e0       b        #0x2b76
00002b52 081c       adds     r0, r1, #0
00002b54 2030       adds     r0, #0x20
00002b56 8278       ldrb     r2, [r0, #2]
00002b58 032a       cmp      r2, #3
00002b5a 0cd1       bne      #0x2b76
00002b5c 2623       movs     r3, #0x26
00002b5e ca5e       ldrsh    r2, [r1, r3]
00002b60 2423       movs     r3, #0x24
00002b62 c95e       ldrsh    r1, [r1, r3]
00002b64 0323       movs     r3, #3
00002b66 c056       ldrsb    r0, [r0, r3]
00002b68 2cf0c6fb   bl       #0x2f2f8
00002b6c 011c       adds     r1, r0, #0
00002b6e f869       ldr      r0, [r7, #0x1c]
00002b70 c06b       ldr      r0, [r0, #0x3c]
00002b72 1ef0cff8   bl       #0x20d14

; parameter_decoder [0x2fdb0,0x2fe28)
; 2fdcc..2fdd3 is an eight-byte Thumb branch table, not code.
0002fdb0 10b5       push     {r4, lr}
0002fdb2 0820       movs     r0, #8
0002fdb4 f7f7e2fa   bl       #0x2737c
0002fdb8 041c       adds     r4, r0, #0
0002fdba f7f709fd   bl       #0x277d0
0002fdbe 2070       strb     r0, [r4]
0002fdc0 0828       cmp      r0, #8
0002fdc2 2fd2       bhs      #0x2fe24
0002fdc4 01a3       adr      r3, #4
0002fdc6 1b5c       ldrb     r3, [r3, r0]
0002fdc8 5b00       lsls     r3, r3, #1
0002fdca 9f44       add      pc, r3
0002fdd4 f7f7fcfc   bl       #0x277d0
0002fdd8 6070       strb     r0, [r4, #1]
0002fdda 23e0       b        #0x2fe24
0002fddc f7f7f8fc   bl       #0x277d0
0002fde0 6070       strb     r0, [r4, #1]
0002fde2 f7f76ffd   bl       #0x278c4
0002fde6 a080       strh     r0, [r4, #4]
0002fde8 f7f76cfd   bl       #0x278c4
0002fdec e080       strh     r0, [r4, #6]
0002fdee 19e0       b        #0x2fe24
0002fdf0 f7f768fd   bl       #0x278c4
0002fdf4 a080       strh     r0, [r4, #4]
0002fdf6 f7f765fd   bl       #0x278c4
0002fdfa e080       strh     r0, [r4, #6]
0002fdfc 12e0       b        #0x2fe24
0002fdfe f7f7e7fc   bl       #0x277d0
0002fe02 6070       strb     r0, [r4, #1]
0002fe04 f7f7e4fc   bl       #0x277d0
0002fe08 a070       strb     r0, [r4, #2]
0002fe0a f7f75bfd   bl       #0x278c4
0002fe0e e080       strh     r0, [r4, #6]
0002fe10 08e0       b        #0x2fe24
0002fe12 f7f7ddfc   bl       #0x277d0
0002fe16 6070       strb     r0, [r4, #1]
0002fe18 f7f754fd   bl       #0x278c4
0002fe1c a080       strh     r0, [r4, #4]
0002fe1e f7f751fd   bl       #0x278c4
0002fe22 e080       strh     r0, [r4, #6]
0002fe24 201c       adds     r0, r4, #0
0002fe26 10bd       pop      {r4, pc}

; list_decoder [0x20e04,0x20e48)
00020e04 f8b5       push     {r3, r4, r5, r6, r7, lr}
00020e06 071c       adds     r7, r0, #0
00020e08 0e1c       adds     r6, r1, #0
00020e0a 06f0cbfc   bl       #0x277a4
00020e0e 0506       lsls     r5, r0, #0x18
00020e10 2d16       asrs     r5, r5, #0x18
00020e12 0c20       movs     r0, #0xc
00020e14 06f0b2fa   bl       #0x2737c
00020e18 041c       adds     r4, r0, #0
00020e1a 4571       strb     r5, [r0, #5]
00020e1c a800       lsls     r0, r5, #2
00020e1e 06f0adfa   bl       #0x2737c
00020e22 ff35       adds     r5, #0xff
00020e24 2d06       lsls     r5, r5, #0x18
00020e26 2060       str      r0, [r4]
00020e28 a760       str      r7, [r4, #8]
00020e2a 2d16       asrs     r5, r5, #0x18
00020e2c 0ad4       bmi      #0x20e44
00020e2e b047       blx      r6
00020e30 0423       movs     r3, #4
00020e32 011c       adds     r1, r0, #0
00020e34 201c       adds     r0, r4, #0
00020e36 e256       ldrsb    r2, [r4, r3]
00020e38 00f036f8   bl       #0x20ea8
00020e3c ff35       adds     r5, #0xff
00020e3e 2d06       lsls     r5, r5, #0x18
00020e40 2d16       asrs     r5, r5, #0x18
00020e42 f4d5       bpl      #0x20e2e
00020e44 201c       adds     r0, r4, #0
00020e46 f8bd       pop      {r3, r4, r5, r6, r7, pc}

; signed_byte_reader [0x277b8,0x277ca)
000277b8 0449       ldr      r1, [pc, #0x10]
000277ba 0023       movs     r3, #0
000277bc 4944       add      r1, sb
000277be 4868       ldr      r0, [r1, #4]
000277c0 021c       adds     r2, r0, #0
000277c2 0132       adds     r2, #1
000277c4 c056       ldrsb    r0, [r0, r3]
000277c6 4a60       str      r2, [r1, #4]
000277c8 7047       bx       lr

; byte_reader [0x277d0,0x277e2)
000277d0 044a       ldr      r2, [pc, #0x10]
000277d2 4a44       add      r2, sb
000277d4 5168       ldr      r1, [r2, #4]
000277d6 0878       ldrb     r0, [r1]
000277d8 0131       adds     r1, #1
000277da 5160       str      r1, [r2, #4]
000277dc 0006       lsls     r0, r0, #0x18
000277de 0016       asrs     r0, r0, #0x18
000277e0 7047       bx       lr

; signed_short_reader [0x278c4,0x278d6)
000278c4 08b5       push     {r3, lr}
000278c6 6846       mov      r0, sp
000278c8 0221       movs     r1, #2
000278ca fff7a3ff   bl       #0x27814
000278ce 00ab       add      r3, sp, #0
000278d0 0020       movs     r0, #0
000278d2 185e       ldrsh    r0, [r3, r0]
000278d4 08bd       pop      {r3, pc}

; utf16_reader [0x278f0,0x27938)
000278f0 70b5       push     {r4, r5, r6, lr}
000278f2 82b0       sub      sp, #8
000278f4 01a8       add      r0, sp, #4
000278f6 0221       movs     r1, #2
000278f8 fff78cff   bl       #0x27814
000278fc 00ab       add      r3, sp, #0
000278fe 0424       movs     r4, #4
00027900 1c5f       ldrsh    r4, [r3, r4]
00027902 a01c       adds     r0, r4, #2
00027904 fff73afd   bl       #0x2737c
00027908 051c       adds     r5, r0, #0
0002790a 002c       cmp      r4, #0
0002790c 0bdd       ble      #0x27926
0002790e 0a4e       ldr      r6, [pc, #0x28]
00027910 0a4b       ldr      r3, [pc, #0x28]
00027912 4e44       add      r6, sb
00027914 7168       ldr      r1, [r6, #4]
00027916 4b44       add      r3, sb
00027918 1b68       ldr      r3, [r3]
0002791a 221c       adds     r2, r4, #0
0002791c 281c       adds     r0, r5, #0
0002791e 9847       blx      r3
00027920 7068       ldr      r0, [r6, #4]
00027922 0019       adds     r0, r0, r4
00027924 7060       str      r0, [r6, #4]
00027926 e00f       lsrs     r0, r4, #0x1f
00027928 0019       adds     r0, r0, r4
0002792a 4010       asrs     r0, r0, #1
0002792c 4000       lsls     r0, r0, #1
0002792e 0021       movs     r1, #0
00027930 2952       strh     r1, [r5, r0]
00027932 02b0       add      sp, #8
00027934 281c       adds     r0, r5, #0
00027936 70bd       pop      {r4, r5, r6, pc}
