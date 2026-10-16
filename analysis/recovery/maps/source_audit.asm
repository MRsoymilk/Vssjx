; STATIC Online map input/cache evidence; SHA256 e08f93bebe133b700f2305bfbedd994b05cc8d04a5a854262af9ced956afbc03
; Original file offsets. Not original source code.

; scene_payload_and_cache_write [0x137c8, 0x138b4)
000137c8 f8b5         push      {r3, r4, r5, r6, r7, lr}
000137ca 704f         ldr       r7, [pc, #0x1c0]
000137cc 7049         ldr       r1, [pc, #0x1c0]
000137ce 4f44         add       r7, sb
000137d0 7944         add       r1, pc
000137d2 7048         ldr       r0, [pc, #0x1c0]
000137d4 704b         ldr       r3, [pc, #0x1c0]
000137d6 4844         add       r0, sb
000137d8 0068         ldr       r0, [r0]
000137da ba6e         ldr       r2, [r7, #0x68]
000137dc 4b44         add       r3, sb
000137de 1b68         ldr       r3, [r3]
000137e0 9847         blx       r3
000137e2 6c48         ldr       r0, [pc, #0x1b0]
000137e4 6d49         ldr       r1, [pc, #0x1b4]
000137e6 4844         add       r0, sb
000137e8 0068         ldr       r0, [r0]
000137ea 4944         add       r1, sb
000137ec 0a68         ldr       r2, [r1]
000137ee 6c49         ldr       r1, [pc, #0x1b0]
000137f0 7944         add       r1, pc
000137f2 11f01dfe     bl        #0x25430
000137f6 02f073fa     bl        #0x15ce0
000137fa 14f0b3f8     bl        #0x27964
000137fe b866         str       r0, [r7, #0x68]
00013800 14f076f8     bl        #0x278f0
00013804 f866         str       r0, [r7, #0x6c]
00013806 13f0e3ff     bl        #0x277d0
0001380a 3872         strb      r0, [r7, #8]
0001380c 13f0e0ff     bl        #0x277d0
00013810 0006         lsls      r0, r0, #0x18
00013812 000e         lsrs      r0, r0, #0x18
00013814 f871         strb      r0, [r7, #7]
00013816 3c7a         ldrb      r4, [r7, #8]
00013818 4443         muls      r4, r0, r4
0001381a 201c         adds      r0, r4, #0
0001381c 13f0e4ff     bl        #0x277e8
00013820 3867         str       r0, [r7, #0x70]
00013822 201c         adds      r0, r4, #0
00013824 13f0e0ff     bl        #0x277e8
00013828 7867         str       r0, [r7, #0x74]
0001382a 201c         adds      r0, r4, #0
0001382c 13f0a6fd     bl        #0x2737c
00013830 5c4d         ldr       r5, [pc, #0x170]
00013832 4d44         add       r5, sb
00013834 2860         str       r0, [r5]
00013836 201c         adds      r0, r4, #0
00013838 13f0a0fd     bl        #0x2737c
0001383c 6860         str       r0, [r5, #4]
0001383e 201c         adds      r0, r4, #0
00013840 13f09cfd     bl        #0x2737c
00013844 a860         str       r0, [r5, #8]
00013846 201c         adds      r0, r4, #0
00013848 13f098fd     bl        #0x2737c
0001384c e860         str       r0, [r5, #0xc]
0001384e 1cf07ff9     bl        #0x2fb50
00013852 803d         subs      r5, #0x80
00013854 6861         str       r0, [r5, #0x14]
00013856 13f0bbff     bl        #0x277d0
0001385a b872         strb      r0, [r7, #0xa]
0001385c 13f0b8ff     bl        #0x277d0
00013860 7872         strb      r0, [r7, #9]
00013862 13f0b5ff     bl        #0x277d0
00013866 061c         adds      r6, r0, #0
00013868 0025         movs      r5, #0
0001386a 0028         cmp       r0, #0
0001386c 20dd         ble       #0x138b0
0001386e 0c20         movs      r0, #0xc
00013870 13f084fd     bl        #0x2737c
00013874 041c         adds      r4, r0, #0
00013876 14f03bf8     bl        #0x278f0
0001387a 2060         str       r0, [r4]
0001387c 14f038f8     bl        #0x278f0
00013880 6060         str       r0, [r4, #4]
00013882 13f0a5ff     bl        #0x277d0
00013886 6072         strb      r0, [r4, #9]
00013888 13f0a2ff     bl        #0x277d0
0001388c 2072         strb      r0, [r4, #8]
0001388e fa79         ldrb      r2, [r7, #7]
00013890 011c         adds      r1, r0, #0
00013892 0923         movs      r3, #9
00013894 5143         muls      r1, r2, r1
00013896 e256         ldrsb     r2, [r4, r3]
00013898 281c         adds      r0, r5, #0
0001389a 2030         adds      r0, #0x20
0001389c 8918         adds      r1, r1, r2
0001389e 7a6f         ldr       r2, [r7, #0x74]
000138a0 5054         strb      r0, [r2, r1]
000138a2 386d         ldr       r0, [r7, #0x50]
000138a4 211c         adds      r1, r4, #0
000138a6 0df035fa     bl        #0x20d14
000138aa 0135         adds      r5, #1
000138ac b542         cmp       r5, r6
000138ae dedb         blt       #0x1386e
000138b0 11f000fe     bl        #0x254b4

; cache_hit_or_missing_request [0x13ab2, 0x13b14)
00013ab2 02f015f9     bl        #0x15ce0
00013ab6 174f         ldr       r7, [pc, #0x5c]
00013ab8 1949         ldr       r1, [pc, #0x64]
00013aba 4f44         add       r7, sb
00013abc 7944         add       r1, pc
00013abe 194c         ldr       r4, [pc, #0x64]
00013ac0 194b         ldr       r3, [pc, #0x64]
00013ac2 4c44         add       r4, sb
00013ac4 2068         ldr       r0, [r4]
00013ac6 ba6e         ldr       r2, [r7, #0x68]
00013ac8 4b44         add       r3, sb
00013aca 1b68         ldr       r3, [r3]
00013acc 9847         blx       r3
00013ace 2068         ldr       r0, [r4]
00013ad0 1249         ldr       r1, [pc, #0x48]
00013ad2 4944         add       r1, sb
00013ad4 0a68         ldr       r2, [r1]
00013ad6 1549         ldr       r1, [pc, #0x54]
00013ad8 7944         add       r1, pc
00013ada 13f0cbfb     bl        #0x27274
00013ade 0028         cmp       r0, #0
00013ae0 14d0         beq       #0x13b0c
00013ae2 fff771fe     bl        #0x137c8
00013ae6 f8bd         pop       {r3, r4, r5, r6, r7, pc}
00013ae8 0c20         movs      r0, #0xc
00013aea 13f047fc     bl        #0x2737c
00013aee 051c         adds      r5, r0, #0
00013af0 13f062fe     bl        #0x277b8
00013af4 6872         strb      r0, [r5, #9]
00013af6 13f06bfe     bl        #0x277d0
00013afa 2872         strb      r0, [r5, #8]
00013afc 13f0f8fe     bl        #0x278f0
00013b00 2860         str       r0, [r5]
00013b02 13f0f5fe     bl        #0x278f0
00013b06 6860         str       r0, [r5, #4]
00013b08 e562         str       r5, [r4, #0x2c]
00013b0a c2e7         b         #0x13a92
00013b0c 0848         ldr       r0, [pc, #0x20]
00013b0e 04f099ff     bl        #0x18a44
00013b12 e8e7         b         #0x13ae6

; map_response_selector [0x17fd0, 0x17fea)
00017fd0 0598         ldr       r0, [sp, #0x14]
00017fd2 7b4b         ldr       r3, [pc, #0x1ec]
00017fd4 9842         cmp       r0, r3
00017fd6 74d0         beq       #0x180c2
00017fd8 74dc         bgt       #0x180c4
00017fda 7a4b         ldr       r3, [pc, #0x1e8]
00017fdc 9842         cmp       r0, r3
00017fde 72d0         beq       #0x180c6
00017fe0 72dc         bgt       #0x180c8
00017fe2 794b         ldr       r3, [pc, #0x1e4]
00017fe4 9842         cmp       r0, r3
00017fe6 70d0         beq       #0x180ca
00017fe8 3cdc         bgt       #0x18064

; map_response_branch [0x180c6, 0x180ce)
000180c6 5ee2         b         #0x18586
000180c8 04e0         b         #0x180d4
000180ca 1fe2         b         #0x1850c
000180cc 97e3         b         #0x187fe

; map_response_calls [0x184f8, 0x18512)
000184f8 fcf774ff     bl        #0x153e4
000184fc 201c         adds      r0, r4, #0
000184fe 0899         ldr       r1, [sp, #0x20]
00018500 039a         ldr       r2, [sp, #0xc]
00018502 00f0a3fb     bl        #0x18c4c
00018506 fbf751fa     bl        #0x139ac
0001850a 14e1         b         #0x18736
0001850c fbf75cf9     bl        #0x137c8
00018510 11e1         b         #0x18736

; bind_message_stream [0x18c4c, 0x18c5e)
00018c4c 08b5         push      {r3, lr}
00018c4e 8018         adds      r0, r0, r2
00018c50 0ef026fa     bl        #0x270a0
00018c54 0249         ldr       r1, [pc, #8]
00018c56 0020         movs      r0, #0
00018c58 4944         add       r1, sb
00018c5a 0870         strb      r0, [r1]
00018c5c 08bd         pop       {r3, pc}

; write_cache_stream [0x25430, 0x2546c)
00025430 37b5         push      {r0, r1, r2, r4, r5, lr}
00025432 0e4d         ldr       r5, [pc, #0x38]
00025434 4d44         add       r5, sb
00025436 2a78         ldrb      r2, [r5]
00025438 002a         cmp       r2, #0
0002543a 15d1         bne       #0x25468
0002543c 01f0dcfc     bl        #0x26df8
00025440 0a21         movs      r1, #0xa
00025442 08f02bfa     bl        #0x2d89c
00025446 041c         adds      r4, r0, #0
00025448 0298         ldr       r0, [sp, #8]
0002544a 0028         cmp       r0, #0
0002544c 04db         blt       #0x25458
0002544e 0422         movs      r2, #4
00025450 201c         adds      r0, r4, #0
00025452 02a9         add       r1, sp, #8
00025454 08f04afe     bl        #0x2e0ec
00025458 6968         ldr       r1, [r5, #4]
0002545a ea68         ldr       r2, [r5, #0xc]
0002545c 201c         adds      r0, r4, #0
0002545e 08f045fe     bl        #0x2e0ec
00025462 201c         adds      r0, r4, #0
00025464 07f07cfe     bl        #0x2d160
00025468 03b0         add       sp, #0xc
0002546a 30bd         pop       {r4, r5, pc}

; cache_token_comparison [0x27274, 0x272fa)
00027274 f0b5         push      {r4, r5, r6, r7, lr}
00027276 83b0         sub       sp, #0xc
00027278 161c         adds      r6, r2, #0
0002727a fff7bdfd     bl        #0x26df8
0002727e 041c         adds      r4, r0, #0
00027280 06f0d2f8     bl        #0x2d428
00027284 0828         cmp       r0, #8
00027286 01d0         beq       #0x2728c
00027288 0120         movs      r0, #1
0002728a 00e0         b         #0x2728e
0002728c 0020         movs      r0, #0
0002728e 0028         cmp       r0, #0
00027290 31d0         beq       #0x272f6
00027292 1a4f         ldr       r7, [pc, #0x68]
00027294 731c         adds      r3, r6, #1
00027296 4f44         add       r7, sb
00027298 0cd1         bne       #0x272b4
0002729a 02a9         add       r1, sp, #8
0002729c 201c         adds      r0, r4, #0
0002729e 06f08bfb     bl        #0x2d9b8
000272a2 0299         ldr       r1, [sp, #8]
000272a4 7860         str       r0, [r7, #4]
000272a6 b860         str       r0, [r7, #8]
000272a8 f960         str       r1, [r7, #0xc]
000272aa 0220         movs      r0, #2
000272ac 3870         strb      r0, [r7]
000272ae 0120         movs      r0, #1
000272b0 03b0         add       sp, #0xc
000272b2 f0bd         pop       {r4, r5, r6, r7, pc}
000272b4 0121         movs      r1, #1
000272b6 201c         adds      r0, r4, #0
000272b8 06f0f0fa     bl        #0x2d89c
000272bc 051c         adds      r5, r0, #0
000272be 0422         movs      r2, #4
000272c0 02a9         add       r1, sp, #8
000272c2 06f06ffb     bl        #0x2d9a4
000272c6 281c         adds      r0, r5, #0
000272c8 05f04aff     bl        #0x2d160
000272cc 0298         ldr       r0, [sp, #8]
000272ce 8642         cmp       r6, r0
000272d0 0cd1         bne       #0x272ec
000272d2 01a9         add       r1, sp, #4
000272d4 201c         adds      r0, r4, #0
000272d6 06f06ffb     bl        #0x2d9b8
000272da 0199         ldr       r1, [sp, #4]
000272dc b860         str       r0, [r7, #8]
000272de f960         str       r1, [r7, #0xc]
000272e0 0430         adds      r0, #4
000272e2 7860         str       r0, [r7, #4]
000272e4 0220         movs      r0, #2
000272e6 3870         strb      r0, [r7]
000272e8 0120         movs      r0, #1
000272ea e1e7         b         #0x272b0
000272ec 201c         adds      r0, r4, #0
000272ee 06f0d3fb     bl        #0x2da98
000272f2 0020         movs      r0, #0
000272f4 dce7         b         #0x272b0
000272f6 0020         movs      r0, #0
000272f8 dae7         b         #0x272b0

; stream_pointer_binding [0x270a0, 0x270ac)
000270a0 024a         ldr       r2, [pc, #8]
000270a2 4a44         add       r2, sb
000270a4 5060         str       r0, [r2, #4]
000270a6 9060         str       r0, [r2, #8]
000270a8 d160         str       r1, [r2, #0xc]
000270aa 7047         bx        lr

; copy_terrain_bytes [0x277e8, 0x2780c)
000277e8 70b5         push      {r4, r5, r6, lr}
000277ea 041c         adds      r4, r0, #0
000277ec fff7c6fd     bl        #0x2737c
000277f0 064e         ldr       r6, [pc, #0x18]
000277f2 074b         ldr       r3, [pc, #0x1c]
000277f4 4e44         add       r6, sb
000277f6 7168         ldr       r1, [r6, #4]
000277f8 4b44         add       r3, sb
000277fa 1b68         ldr       r3, [r3]
000277fc 051c         adds      r5, r0, #0
000277fe 221c         adds      r2, r4, #0
00027800 9847         blx       r3
00027802 7068         ldr       r0, [r6, #4]
00027804 0019         adds      r0, r0, r4
00027806 7060         str       r0, [r6, #4]
00027808 281c         adds      r0, r5, #0
0002780a 70bd         pop       {r4, r5, r6, pc}

; bundle_version_reader [0x9904, 0x9998)
00009904 f8b5         push      {r3, r4, r5, r6, r7, lr}
00009906 3020         movs      r0, #0x30
00009908 1df038fd     bl        #0x2737c
0000990c 3a4d         ldr       r5, [pc, #0xe8]
0000990e 4d44         add       r5, sb
00009910 6862         str       r0, [r5, #0x24]
00009912 0520         movs      r0, #5
00009914 1df07afd     bl        #0x2740c
00009918 a861         str       r0, [r5, #0x18]
0000991a 1420         movs      r0, #0x14
0000991c 1df02efd     bl        #0x2737c
00009920 e861         str       r0, [r5, #0x1c]
00009922 3648         ldr       r0, [pc, #0xd8]
00009924 0021         movs      r1, #0
00009926 7844         add       r0, pc
00009928 25f0c2fb     bl        #0x2f0b0
0000992c 0028         cmp       r0, #0
0000992e 0dd0         beq       #0x994c
00009930 0424         movs      r4, #4
00009932 25f01ffc     bl        #0x2f174
00009936 a969         ldr       r1, [r5, #0x18]
00009938 a600         lsls      r6, r4, #2
0000993a 8851         str       r0, [r1, r6]
0000993c 25f002fc     bl        #0x2f144
00009940 e969         ldr       r1, [r5, #0x1c]
00009942 013c         subs      r4, #1
00009944 8851         str       r0, [r1, r6]
00009946 f4d5         bpl       #0x9932
00009948 25f098fb     bl        #0x2f07c
0000994c 2c4e         ldr       r6, [pc, #0xb0]
0000994e 0024         movs      r4, #0
00009950 7e44         add       r6, pc
00009952 a000         lsls      r0, r4, #2
00009954 0019         adds      r0, r0, r4
00009956 8000         lsls      r0, r0, #2
00009958 8019         adds      r0, r0, r6
0000995a a862         str       r0, [r5, #0x28]
0000995c 1df08afa     bl        #0x26e74
00009960 1df0aefb     bl        #0x270c0
00009964 0028         cmp       r0, #0
00009966 03d1         bne       #0x9970
00009968 201c         adds      r0, r4, #0
0000996a fff741fc     bl        #0x91f0
0000996e a862         str       r0, [r5, #0x28]
00009970 a86a         ldr       r0, [r5, #0x28]
00009972 1df07ffa     bl        #0x26e74
00009976 1df0adf9     bl        #0x26cd4
0000997a 0028         cmp       r0, #0
0000997c 05dd         ble       #0x998a
0000997e a86a         ldr       r0, [r5, #0x28]
00009980 1df078fa     bl        #0x26e74
00009984 1df0a6f9     bl        #0x26cd4
00009988 00e0         b         #0x998c
0000998a 0020         movs      r0, #0
0000998c a100         lsls      r1, r4, #2
0000998e ea69         ldr       r2, [r5, #0x1c]
00009990 0134         adds      r4, #1
00009992 052c         cmp       r4, #5
00009994 5050         str       r0, [r2, r1]
00009996 dcdb         blt       #0x9952

; allocate_zeroed_work_array [0x2737c, 0x273a6)
0002737c 38b5         push      {r3, r4, r5, lr}
0002737e 0028         cmp       r0, #0
00027380 01dc         bgt       #0x27386
00027382 0020         movs      r0, #0
00027384 38bd         pop       {r3, r4, r5, pc}
00027386 0138         subs      r0, #1
00027388 0011         asrs      r0, r0, #4
0002738a 0130         adds      r0, #1
0002738c 0401         lsls      r4, r0, #4
0002738e 201c         adds      r0, r4, #0
00027390 06f060fa     bl        #0x2d854
00027394 044b         ldr       r3, [pc, #0x10]
00027396 051c         adds      r5, r0, #0
00027398 4b44         add       r3, sb
0002739a 1b68         ldr       r3, [r3]
0002739c 221c         adds      r2, r4, #0
0002739e 0021         movs      r1, #0
000273a0 9847         blx       r3
000273a2 281c         adds      r0, r5, #0
000273a4 eee7         b         #0x27384
