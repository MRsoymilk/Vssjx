; STATIC cache namespace evidence; SHA256 e08f93bebe133b700f2305bfbedd994b05cc8d04a5a854262af9ced956afbc03
; File offsets; bounded excerpts can include literal/table data, not original source code.

; cache_root_initialization [0x24b8c, 0x24bd2)
00024b8c 10b5         push      {r4, lr}
00024b8e 0028         cmp       r0, #0
00024b90 1ed0         beq       #0x24bd0
00024b92 08f07ffc     bl        #0x2d494
00024b96 0f4c         ldr       r4, [pc, #0x3c]
00024b98 1823         movs      r3, #0x18
00024b9a 4c44         add       r4, sb
00024b9c 221c         adds      r2, r4, #0
00024b9e 0121         movs      r1, #1
00024ba0 08f03cf9     bl        #0x2ce1c
00024ba4 0c49         ldr       r1, [pc, #0x30]
00024ba6 221c         adds      r2, r4, #0
00024ba8 7944         add       r1, pc
00024baa 0c4b         ldr       r3, [pc, #0x30]
00024bac 283c         subs      r4, #0x28
00024bae 4b44         add       r3, sb
00024bb0 1b68         ldr       r3, [r3]
00024bb2 201c         adds      r0, r4, #0
00024bb4 9847         blx       r3
00024bb6 201c         adds      r0, r4, #0
00024bb8 08f036fc     bl        #0x2d428
00024bbc 0828         cmp       r0, #8
00024bbe 01d0         beq       #0x24bc4
00024bc0 0120         movs      r0, #1
00024bc2 00e0         b         #0x24bc6
00024bc4 0020         movs      r0, #0
00024bc6 0028         cmp       r0, #0
00024bc8 02d1         bne       #0x24bd0
00024bca 201c         adds      r0, r4, #0
00024bcc 08f05cfe     bl        #0x2d888
00024bd0 10bd         pop       {r4, pc}

; cache_path_join [0x26df8, 0x26e60)
00026df8 f0b5         push      {r4, r5, r6, r7, lr}
00026dfa 051c         adds      r5, r0, #0
00026dfc 1948         ldr       r0, [pc, #0x64]
00026dfe 184a         ldr       r2, [pc, #0x60]
00026e00 0c1c         adds      r4, r1, #0
00026e02 0b1c         adds      r3, r1, #0
00026e04 0029         cmp       r1, #0
00026e06 83b0         sub       sp, #0xc
00026e08 7844         add       r0, pc
00026e0a 4a44         add       r2, sb
00026e0c 00d1         bne       #0x26e10
00026e0e 031c         adds      r3, r0, #0
00026e10 1549         ldr       r1, [pc, #0x54]
00026e12 0293         str       r3, [sp, #8]
00026e14 7944         add       r1, pc
00026e16 124e         ldr       r6, [pc, #0x48]
00026e18 144f         ldr       r7, [pc, #0x50]
00026e1a 4e44         add       r6, sb
00026e1c 4f44         add       r7, sb
00026e1e 3f68         ldr       r7, [r7]
00026e20 503e         subs      r6, #0x50
00026e22 301c         adds      r0, r6, #0
00026e24 b847         blx       r7
00026e26 301c         adds      r0, r6, #0
00026e28 06f0fefa     bl        #0x2d428
00026e2c 0828         cmp       r0, #8
00026e2e 01d0         beq       #0x26e34
00026e30 0120         movs      r0, #1
00026e32 00e0         b         #0x26e36
00026e34 0020         movs      r0, #0
00026e36 0028         cmp       r0, #0
00026e38 02d1         bne       #0x26e40
00026e3a 301c         adds      r0, r6, #0
00026e3c 06f024fd     bl        #0x2d888
00026e40 002d         cmp       r5, #0
00026e42 0ad0         beq       #0x26e5a
00026e44 064a         ldr       r2, [pc, #0x18]
00026e46 0a49         ldr       r1, [pc, #0x28]
00026e48 0095         str       r5, [sp]
00026e4a 4a44         add       r2, sb
00026e4c 7944         add       r1, pc
00026e4e 074f         ldr       r7, [pc, #0x1c]
00026e50 029b         ldr       r3, [sp, #8]
00026e52 4f44         add       r7, sb
00026e54 3c68         ldr       r4, [r7]
00026e56 301c         adds      r0, r6, #0
00026e58 a047         blx       r4
00026e5a 301c         adds      r0, r6, #0
00026e5c 03b0         add       sp, #0xc
00026e5e f0bd         pop       {r4, r5, r6, r7, pc}

; package_header_field_dispatch [0x2ceac, 0x2ced4)
0002ceac 0898         ldr       r0, [sp, #0x20]
0002ceae 0a28         cmp       r0, #0xa
0002ceb0 04d2         bhs       #0x2cebc
0002ceb2 03a3         adr       r3, #0xc
0002ceb4 1b18         adds      r3, r3, r0
0002ceb6 1b5a         ldrh      r3, [r3, r0]
0002ceb8 5b00         lsls      r3, r3, #1
0002ceba 9f44         add       pc, r3
0002cebc 69e0         b         #0x2cf92
0002cebe 0000         movs      r0, r0
0002cec0 e000         lsls      r0, r4, #3
0002cec2 0b00         movs      r3, r1
0002cec4 3b00         movs      r3, r7
0002cec6 4700         lsls      r7, r0, #1
0002cec8 6b00         lsls      r3, r5, #1
0002ceca 8f00         lsls      r7, r1, #2
0002cecc 9b00         lsls      r3, r3, #2
0002cece a700         lsls      r7, r4, #2
0002ced0 c100         lsls      r1, r0, #3
0002ced2 d800         lsls      r0, r3, #3

; package_internal_basename [0x2ced4, 0x2cf34)
0002ced4 0c2e         cmp       r6, #0xc
0002ced6 5cdb         blt       #0x2cf92
0002ced8 0c22         movs      r2, #0xc
0002ceda 0092         str       r2, [sp]
0002cedc 1022         movs      r2, #0x10
0002cede 231c         adds      r3, r4, #0
0002cee0 291c         adds      r1, r5, #0
0002cee2 0598         ldr       r0, [sp, #0x14]
0002cee4 00f0e0f8     bl        #0x2d0a8
0002cee8 071c         adds      r7, r0, #0
0002ceea 201c         adds      r0, r4, #0
0002ceec 0178         ldrb      r1, [r0]
0002ceee 0130         adds      r0, #1
0002cef0 0029         cmp       r1, #0
0002cef2 fbd1         bne       #0x2ceec
0002cef4 0138         subs      r0, #1
0002cef6 a042         cmp       r0, r4
0002cef8 02d0         beq       #0x2cf00
0002cefa 0178         ldrb      r1, [r0]
0002cefc 2e29         cmp       r1, #0x2e
0002cefe f9d1         bne       #0x2cef4
0002cf00 0178         ldrb      r1, [r0]
0002cf02 2e29         cmp       r1, #0x2e
0002cf04 00d0         beq       #0x2cf08
0002cf06 0020         movs      r0, #0
0002cf08 0028         cmp       r0, #0
0002cf0a 09d1         bne       #0x2cf20
0002cf0c 644b         ldr       r3, [pc, #0x190]
0002cf0e c743         mvns      r7, r0
0002cf10 321c         adds      r2, r6, #0
0002cf12 0021         movs      r1, #0
0002cf14 4b44         add       r3, sb
0002cf16 1b68         ldr       r3, [r3]
0002cf18 201c         adds      r0, r4, #0
0002cf1a d3f782f8     bl        #0x22
0002cf1e 38e0         b         #0x2cf92
0002cf20 001b         subs      r0, r0, r4
0002cf22 5f4b         ldr       r3, [pc, #0x17c]
0002cf24 321a         subs      r2, r6, r0
0002cf26 2018         adds      r0, r4, r0
0002cf28 4b44         add       r3, sb
0002cf2a 1b68         ldr       r3, [r3]
0002cf2c 0021         movs      r1, #0
0002cf2e d3f778f8     bl        #0x22
0002cf32 2ee0         b         #0x2cf92
