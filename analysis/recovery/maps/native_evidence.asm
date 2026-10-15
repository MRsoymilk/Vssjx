; Online v48 gameonline.ext; STATIC evidence, no native execution
; SHA256 e08f93bebe133b700f2305bfbedd994b05cc8d04a5a854262af9ced956afbc03
; Addresses = file offsets. Comments are analysis, not recovered source code.
; Bounded excerpts can include literal pools: do not treat data as executable instructions.

; scene_read [0x137c8, 0x138b4) — 编号字符串、名称、行列数、两层字节、图块表、两个字节、交互记录
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

; terrain_draw [0x14670, 0x146c6) — 单元0不绘制，正索引指向图块表；16像素网格
00014670 1d4a         ldr       r2, [pc, #0x74]
00014672 201c         adds      r0, r4, #0
00014674 4a44         add       r2, sb
00014676 803a         subs      r2, #0x80
00014678 d179         ldrb      r1, [r2, #7]
0001467a 4843         muls      r0, r1, r0
0001467c 116f         ldr       r1, [r2, #0x70]
0001467e 4019         adds      r0, r0, r5
00014680 0856         ldrsb     r0, [r1, r0]
00014682 0028         cmp       r0, #0
00014684 1fd0         beq       #0x146c6
00014686 1849         ldr       r1, [pc, #0x60]
00014688 8000         lsls      r0, r0, #2
0001468a 4944         add       r1, sb
0001468c 0969         ldr       r1, [r1, #0x10]
0001468e 0968         ldr       r1, [r1]
00014690 0818         adds      r0, r1, r0
00014692 4038         subs      r0, #0x40
00014694 c36b         ldr       r3, [r0, #0x3c]
00014696 002b         cmp       r3, #0
00014698 15d0         beq       #0x146c6
0001469a 0022         movs      r2, #0
0001469c 0492         str       r2, [sp, #0x10]
0001469e 1022         movs      r2, #0x10
000146a0 0021         movs      r1, #0
000146a2 0220         movs      r0, #2
000146a4 0290         str       r0, [sp, #8]
000146a6 0391         str       r1, [sp, #0xc]
000146a8 0092         str       r2, [sp]
000146aa 0192         str       r2, [sp, #4]
000146ac 9868         ldr       r0, [r3, #8]
000146ae 069a         ldr       r2, [sp, #0x18]
000146b0 2101         lsls      r1, r4, #4
000146b2 8918         adds      r1, r1, r2
000146b4 1831         adds      r1, #0x18
000146b6 0a04         lsls      r2, r1, #0x10
000146b8 0c4f         ldr       r7, [pc, #0x30]
000146ba 0a99         ldr       r1, [sp, #0x28]
000146bc 4f44         add       r7, sb
000146be 3f68         ldr       r7, [r7]
000146c0 1214         asrs      r2, r2, #0x10
000146c2 1023         movs      r3, #0x10
000146c4 b847         blx       r7

; tile_load [0x15618, 0x1569c) — 图块表编号减1后生成tile%d资源名
00015618 f8b5         push      {r3, r4, r5, r6, r7, lr}
0001561a 204e         ldr       r6, [pc, #0x80]
0001561c 1f4d         ldr       r5, [pc, #0x7c]
0001561e 4e44         add       r6, sb
00015620 7069         ldr       r0, [r6, #0x14]
00015622 4d44         add       r5, sb
00015624 0479         ldrb      r4, [r0, #4]
00015626 0020         movs      r0, #0
00015628 803d         subs      r5, #0x80
0001562a a882         strh      r0, [r5, #0x14]
0001562c 3069         ldr       r0, [r6, #0x10]
0001562e 0028         cmp       r0, #0
00015630 04d1         bne       #0x1563c
00015632 2006         lsls      r0, r4, #0x18
00015634 000e         lsrs      r0, r0, #0x18
00015636 15f057f8     bl        #0x2a6e8
0001563a 3061         str       r0, [r6, #0x10]
0001563c 013c         subs      r4, #1
0001563e 2cd4         bmi       #0x1569a
00015640 174f         ldr       r7, [pc, #0x5c]
00015642 4f44         add       r7, sb
00015644 3069         ldr       r0, [r6, #0x10]
00015646 a500         lsls      r5, r4, #2
00015648 0068         ldr       r0, [r0]
0001564a 4059         ldr       r0, [r0, r5]
0001564c 0028         cmp       r0, #0
0001564e 1bd1         bne       #0x15688
00015650 7069         ldr       r0, [r6, #0x14]
00015652 6100         lsls      r1, r4, #1
00015654 0068         ldr       r0, [r0]
00015656 425e         ldrsh     r2, [r0, r1]
00015658 1249         ldr       r1, [pc, #0x48]
0001565a 013a         subs      r2, #1
0001565c 7944         add       r1, pc
0001565e 124b         ldr       r3, [pc, #0x48]
00015660 3868         ldr       r0, [r7]
00015662 4b44         add       r3, sb
00015664 1b68         ldr       r3, [r3]
00015666 9847         blx       r3
00015668 1049         ldr       r1, [pc, #0x40]
0001566a 7944         add       r1, pc
0001566c 3868         ldr       r0, [r7]
0001566e 10f0f1f8     bl        #0x25854
00015672 3169         ldr       r1, [r6, #0x10]
00015674 0028         cmp       r0, #0
00015676 0968         ldr       r1, [r1]
00015678 4851         str       r0, [r1, r5]
0001567a 05d1         bne       #0x15688
0001567c 074d         ldr       r5, [pc, #0x1c]
0001567e 4d44         add       r5, sb
00015680 803d         subs      r5, #0x80
00015682 a88a         ldrh      r0, [r5, #0x14]
00015684 0130         adds      r0, #1
00015686 a882         strh      r0, [r5, #0x14]
00015688 201c         adds      r0, r4, #0
0001568a 0cf0deef     blx       #0x22648
0001568e 0028         cmp       r0, #0
00015690 01d1         bne       #0x15696
00015692 00f025fb     bl        #0x15ce0
00015696 013c         subs      r4, #1
00015698 d4d5         bpl       #0x15644
0001569a f8bd         pop       {r3, r4, r5, r6, r7, pc}

; world_routes_draw [0x21090, 0x210d8) — 原始行列顺序转换为x/y后绘制线段
00021090 1023         movs      r3, #0x10
00021092 fc5e         ldrsh     r4, [r7, r3]
00021094 043c         subs      r4, #4
00021096 1fd4         bmi       #0x210d8
00021098 b86a         ldr       r0, [r7, #0x28]
0002109a 0019         adds      r0, r0, r4
0002109c 0223         movs      r3, #2
0002109e c056         ldrsb     r0, [r0, r3]
000210a0 01f094f8     bl        #0x221cc
000210a4 0290         str       r0, [sp, #8]
000210a6 b86a         ldr       r0, [r7, #0x28]
000210a8 0019         adds      r0, r0, r4
000210aa 0323         movs      r3, #3
000210ac c056         ldrsb     r0, [r0, r3]
000210ae 01f08df8     bl        #0x221cc
000210b2 051c         adds      r5, r0, #0
000210b4 b86a         ldr       r0, [r7, #0x28]
000210b6 0057         ldrsb     r0, [r0, r4]
000210b8 01f088f8     bl        #0x221cc
000210bc 061c         adds      r6, r0, #0
000210be b86a         ldr       r0, [r7, #0x28]
000210c0 0019         adds      r0, r0, r4
000210c2 0123         movs      r3, #1
000210c4 c056         ldrsb     r0, [r0, r3]
000210c6 01f081f8     bl        #0x221cc
000210ca 2a1c         adds      r2, r5, #0
000210cc 311c         adds      r1, r6, #0
000210ce 029b         ldr       r3, [sp, #8]
000210d0 05f08afa     bl        #0x265e8
000210d4 043c         subs      r4, #4
000210d6 dfd5         bpl       #0x21098

; world_nodes_draw [0x21244, 0x212e8) — 记录+2为x、+1为y、+3为节点图标类别
00021244 844f         ldr       r7, [pc, #0x210]
00021246 0e23         movs      r3, #0xe
00021248 4f44         add       r7, sb
0002124a fc5e         ldrsh     r4, [r7, r3]
0002124c 063c         subs      r4, #6
0002124e 4bd4         bmi       #0x212e8
00021250 786a         ldr       r0, [r7, #0x24]
00021252 0019         adds      r0, r0, r4
00021254 0223         movs      r3, #2
00021256 c056         ldrsb     r0, [r0, r3]
00021258 00f0aaff     bl        #0x221b0
0002125c 051c         adds      r5, r0, #0
0002125e 786a         ldr       r0, [r7, #0x24]
00021260 0019         adds      r0, r0, r4
00021262 0123         movs      r3, #1
00021264 c056         ldrsb     r0, [r0, r3]
00021266 00f0a3ff     bl        #0x221b0
0002126a 0022         movs      r2, #0
0002126c 0092         str       r2, [sp]
0002126e 796a         ldr       r1, [r7, #0x24]
00021270 061c         adds      r6, r0, #0
00021272 0323         movs      r3, #3
00021274 0919         adds      r1, r1, r4
00021276 c956         ldrsb     r1, [r1, r3]
00021278 f869         ldr       r0, [r7, #0x1c]
0002127a 0023         movs      r3, #0
0002127c 0068         ldr       r0, [r0]
0002127e 8900         lsls      r1, r1, #2
00021280 4058         ldr       r0, [r0, r1]
00021282 321c         adds      r2, r6, #0
00021284 291c         adds      r1, r5, #0
00021286 04f08dfe     bl        #0x25fa4
0002128a 786a         ldr       r0, [r7, #0x24]
0002128c 0019         adds      r0, r0, r4
0002128e c078         ldrb      r0, [r0, #3]
00021290 0028         cmp       r0, #0
00021292 15d0         beq       #0x212c0
00021294 0a23         movs      r3, #0xa
00021296 f856         ldrsb     r0, [r7, r3]
00021298 c10f         lsrs      r1, r0, #0x1f
0002129a 0818         adds      r0, r1, r0
0002129c 4010         asrs      r0, r0, #1
0002129e 4019         adds      r0, r0, r5
000212a0 0690         str       r0, [sp, #0x18]
000212a2 201c         adds      r0, r4, #0
000212a4 01f002ea     blx       #0x226ac
000212a8 8800         lsls      r0, r1, #2
000212aa 396a         ldr       r1, [r7, #0x20]
000212ac 6e4a         ldr       r2, [pc, #0x1b8]
000212ae 0858         ldr       r0, [r1, r0]
000212b0 6e49         ldr       r1, [pc, #0x1b8]
000212b2 0192         str       r2, [sp, #4]
000212b4 2123         movs      r3, #0x21
000212b6 0091         str       r1, [sp]
000212b8 0699         ldr       r1, [sp, #0x18]
000212ba 321c         adds      r2, r6, #0
000212bc 04f096fc     bl        #0x25bec
000212c0 0823         movs      r3, #8
000212c2 fa56         ldrsb     r2, [r7, r3]
000212c4 0923         movs      r3, #9
000212c6 0092         str       r2, [sp]
000212c8 0192         str       r2, [sp, #4]
000212ca f856         ldrsb     r0, [r7, r3]
000212cc f96b         ldr       r1, [r7, #0x3c]
000212ce 4b68         ldr       r3, [r1, #4]
000212d0 321a         subs      r2, r6, r0
000212d2 0968         ldr       r1, [r1]
000212d4 d31a         subs      r3, r2, r3
000212d6 281a         subs      r0, r5, r0
000212d8 421a         subs      r2, r0, r1
000212da 786a         ldr       r0, [r7, #0x24]
000212dc 0157         ldrsb     r1, [r0, r4]
000212de 0320         movs      r0, #3
000212e0 fcf770ff     bl        #0x1e1c4
000212e4 063c         subs      r4, #6
000212e6 b3d5         bpl       #0x21250

; world_levels [0x2193c, 0x2196e) — 记录+4与+5显示为等级区间
0002193c 38b5         push      {r3, r4, r5, lr}
0002193e 0c4d         ldr       r5, [pc, #0x30]
00021940 041c         adds      r4, r0, #0
00021942 4d44         add       r5, sb
00021944 686a         ldr       r0, [r5, #0x24]
00021946 0019         adds      r0, r0, r4
00021948 0423         movs      r3, #4
0002194a c056         ldrsb     r0, [r0, r3]
0002194c 03f0b6fc     bl        #0x252bc
00021950 7e20         movs      r0, #0x7e
00021952 03f0a7fc     bl        #0x252a4
00021956 686a         ldr       r0, [r5, #0x24]
00021958 0019         adds      r0, r0, r4
0002195a 0523         movs      r3, #5
0002195c c056         ldrsb     r0, [r0, r3]
0002195e 03f0adfc     bl        #0x252bc
00021962 3520         movs      r0, #0x35
00021964 fef7f2ff     bl        #0x2094c
00021968 03f0b4fc     bl        #0x252d4
0002196c 38bd         pop       {r3, r4, r5, pc}

; map_id_lookup [0x221e8, 0x22210) — 以记录首字节匹配原包地图编号
000221e8 0949         ldr       r1, [pc, #0x24]
000221ea 0206         lsls      r2, r0, #0x18
000221ec 4944         add       r1, sb
000221ee c889         ldrh      r0, [r1, #0xe]
000221f0 120e         lsrs      r2, r2, #0x18
000221f2 0638         subs      r0, #6
000221f4 0004         lsls      r0, r0, #0x10
000221f6 0014         asrs      r0, r0, #0x10
000221f8 07d4         bmi       #0x2220a
000221fa 4b6a         ldr       r3, [r1, #0x24]
000221fc 195c         ldrb      r1, [r3, r0]
000221fe 9142         cmp       r1, r2
00022200 05d0         beq       #0x2220e
00022202 0638         subs      r0, #6
00022204 0004         lsls      r0, r0, #0x10
00022206 0014         asrs      r0, r0, #0x10
00022208 f8d5         bpl       #0x221fc
0002220a 0020         movs      r0, #0
0002220c c043         mvns      r0, r0
0002220e 7047         bx        lr

; cache_write [0x25430, 0x25470) — 写入缓存；有校验值时先写4字节再写原始流
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
0002546c 8807         lsls      r0, r1, #0x1e
0002546e 0000         movs      r0, r0

; cache_read [0x27274, 0x27300) — 缓存校验匹配后跳过4字节头
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
000272fa 0000         movs      r0, r0
000272fc 8807         lsls      r0, r1, #0x1e
000272fe 0000         movs      r0, r0

; stream_readers [0x277a4, 0x27980) — 字节、大端短整数、UTF16字符串及数字字符串读取
000277a4 034a         ldr       r2, [pc, #0xc]
000277a6 4a44         add       r2, sb
000277a8 5168         ldr       r1, [r2, #4]
000277aa 0878         ldrb      r0, [r1]
000277ac 0131         adds      r1, #1
000277ae 5160         str       r1, [r2, #4]
000277b0 7047         bx        lr
000277b2 0000         movs      r0, r0
000277b4 8807         lsls      r0, r1, #0x1e
000277b6 0000         movs      r0, r0
000277b8 0449         ldr       r1, [pc, #0x10]
000277ba 0023         movs      r3, #0
000277bc 4944         add       r1, sb
000277be 4868         ldr       r0, [r1, #4]
000277c0 021c         adds      r2, r0, #0
000277c2 0132         adds      r2, #1
000277c4 c056         ldrsb     r0, [r0, r3]
000277c6 4a60         str       r2, [r1, #4]
000277c8 7047         bx        lr
000277ca 0000         movs      r0, r0
000277cc 8807         lsls      r0, r1, #0x1e
000277ce 0000         movs      r0, r0
000277d0 044a         ldr       r2, [pc, #0x10]
000277d2 4a44         add       r2, sb
000277d4 5168         ldr       r1, [r2, #4]
000277d6 0878         ldrb      r0, [r1]
000277d8 0131         adds      r1, #1
000277da 5160         str       r1, [r2, #4]
000277dc 0006         lsls      r0, r0, #0x18
000277de 0016         asrs      r0, r0, #0x18
000277e0 7047         bx        lr
000277e2 0000         movs      r0, r0
000277e4 8807         lsls      r0, r1, #0x1e
000277e6 0000         movs      r0, r0
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
0002780c 8807         lsls      r0, r1, #0x1e
0002780e 0000         movs      r0, r0
00027810 980d         lsrs      r0, r3, #0x16
00027812 0000         movs      r0, r0
00027814 70b5         push      {r4, r5, r6, lr}
00027816 0c4e         ldr       r6, [pc, #0x30]
00027818 051c         adds      r5, r0, #0
0002781a 0c1c         adds      r4, r1, #0
0002781c 0b4b         ldr       r3, [pc, #0x2c]
0002781e 0a1c         adds      r2, r1, #0
00027820 4e44         add       r6, sb
00027822 7168         ldr       r1, [r6, #4]
00027824 4b44         add       r3, sb
00027826 1b68         ldr       r3, [r3]
00027828 9847         blx       r3
0002782a 0020         movs      r0, #0
0002782c 002c         cmp       r4, #0
0002782e 07dd         ble       #0x27840
00027830 2a18         adds      r2, r5, r0
00027832 5378         ldrb      r3, [r2, #1]
00027834 295c         ldrb      r1, [r5, r0]
00027836 2b54         strb      r3, [r5, r0]
00027838 0230         adds      r0, #2
0002783a a042         cmp       r0, r4
0002783c 5170         strb      r1, [r2, #1]
0002783e f7db         blt       #0x27830
00027840 7068         ldr       r0, [r6, #4]
00027842 0019         adds      r0, r0, r4
00027844 7060         str       r0, [r6, #4]
00027846 70bd         pop       {r4, r5, r6, pc}
00027848 8807         lsls      r0, r1, #0x1e
0002784a 0000         movs      r0, r0
0002784c 980d         lsrs      r0, r3, #0x16
0002784e 0000         movs      r0, r0
00027850 074a         ldr       r2, [pc, #0x1c]
00027852 4a44         add       r2, sb
00027854 5168         ldr       r1, [r2, #4]
00027856 0878         ldrb      r0, [r1]
00027858 4b78         ldrb      r3, [r1, #1]
0002785a 0006         lsls      r0, r0, #0x18
0002785c 1b04         lsls      r3, r3, #0x10
0002785e 1843         orrs      r0, r3
00027860 8b78         ldrb      r3, [r1, #2]
00027862 1b02         lsls      r3, r3, #8
00027864 1843         orrs      r0, r3
00027866 cb78         ldrb      r3, [r1, #3]
00027868 1843         orrs      r0, r3
0002786a 0431         adds      r1, #4
0002786c 5160         str       r1, [r2, #4]
0002786e 7047         bx        lr
00027870 8807         lsls      r0, r1, #0x1e
00027872 0000         movs      r0, r0
00027874 70b5         push      {r4, r5, r6, lr}
00027876 051c         adds      r5, r0, #0
00027878 8000         lsls      r0, r0, #2
0002787a fff77ffd     bl        #0x2737c
0002787e 061c         adds      r6, r0, #0
00027880 0024         movs      r4, #0
00027882 002d         cmp       r5, #0
00027884 06dd         ble       #0x27894
00027886 fff7e3ff     bl        #0x27850
0002788a a100         lsls      r1, r4, #2
0002788c 0134         adds      r4, #1
0002788e ac42         cmp       r4, r5
00027890 7050         str       r0, [r6, r1]
00027892 f8db         blt       #0x27886
00027894 301c         adds      r0, r6, #0
00027896 70bd         pop       {r4, r5, r6, pc}
00027898 38b5         push      {r3, r4, r5, lr}
0002789a 094d         ldr       r5, [pc, #0x24]
0002789c 0020         movs      r0, #0
0002789e 4d44         add       r5, sb
000278a0 6c68         ldr       r4, [r5, #4]
000278a2 2179         ldrb      r1, [r4, #4]
000278a4 0906         lsls      r1, r1, #0x18
000278a6 0843         orrs      r0, r1
000278a8 6179         ldrb      r1, [r4, #5]
000278aa 0904         lsls      r1, r1, #0x10
000278ac 0843         orrs      r0, r1
000278ae a179         ldrb      r1, [r4, #6]
000278b0 0902         lsls      r1, r1, #8
000278b2 0843         orrs      r0, r1
000278b4 e179         ldrb      r1, [r4, #7]
000278b6 0843         orrs      r0, r1
000278b8 c117         asrs      r1, r0, #0x1f
000278ba 0834         adds      r4, #8
000278bc 6c60         str       r4, [r5, #4]
000278be 38bd         pop       {r3, r4, r5, pc}
000278c0 8807         lsls      r0, r1, #0x1e
000278c2 0000         movs      r0, r0
000278c4 08b5         push      {r3, lr}
000278c6 6846         mov       r0, sp
000278c8 0221         movs      r1, #2
000278ca fff7a3ff     bl        #0x27814
000278ce 00ab         add       r3, sp, #0
000278d0 0020         movs      r0, #0
000278d2 185e         ldrsh     r0, [r3, r0]
000278d4 08bd         pop       {r3, pc}
000278d6 0000         movs      r0, r0
000278d8 38b5         push      {r3, r4, r5, lr}
000278da 4500         lsls      r5, r0, #1
000278dc 281c         adds      r0, r5, #0
000278de fff74dfd     bl        #0x2737c
000278e2 041c         adds      r4, r0, #0
000278e4 291c         adds      r1, r5, #0
000278e6 fff795ff     bl        #0x27814
000278ea 201c         adds      r0, r4, #0
000278ec 38bd         pop       {r3, r4, r5, pc}
000278ee 0000         movs      r0, r0
000278f0 70b5         push      {r4, r5, r6, lr}
000278f2 82b0         sub       sp, #8
000278f4 01a8         add       r0, sp, #4
000278f6 0221         movs      r1, #2
000278f8 fff78cff     bl        #0x27814
000278fc 00ab         add       r3, sp, #0
000278fe 0424         movs      r4, #4
00027900 1c5f         ldrsh     r4, [r3, r4]
00027902 a01c         adds      r0, r4, #2
00027904 fff73afd     bl        #0x2737c
00027908 051c         adds      r5, r0, #0
0002790a 002c         cmp       r4, #0
0002790c 0bdd         ble       #0x27926
0002790e 0a4e         ldr       r6, [pc, #0x28]
00027910 0a4b         ldr       r3, [pc, #0x28]
00027912 4e44         add       r6, sb
00027914 7168         ldr       r1, [r6, #4]
00027916 4b44         add       r3, sb
00027918 1b68         ldr       r3, [r3]
0002791a 221c         adds      r2, r4, #0
0002791c 281c         adds      r0, r5, #0
0002791e 9847         blx       r3
00027920 7068         ldr       r0, [r6, #4]
00027922 0019         adds      r0, r0, r4
00027924 7060         str       r0, [r6, #4]
00027926 e00f         lsrs      r0, r4, #0x1f
00027928 0019         adds      r0, r0, r4
0002792a 4010         asrs      r0, r0, #1
0002792c 4000         lsls      r0, r0, #1
0002792e 0021         movs      r1, #0
00027930 2952         strh      r1, [r5, r0]
00027932 02b0         add       sp, #8
00027934 281c         adds      r0, r5, #0
00027936 70bd         pop       {r4, r5, r6, pc}
00027938 8807         lsls      r0, r1, #0x1e
0002793a 0000         movs      r0, r0
0002793c 980d         lsrs      r0, r3, #0x16
0002793e 0000         movs      r0, r0
00027940 70b5         push      {r4, r5, r6, lr}
00027942 051c         adds      r5, r0, #0
00027944 8000         lsls      r0, r0, #2
00027946 fff719fd     bl        #0x2737c
0002794a 061c         adds      r6, r0, #0
0002794c 0024         movs      r4, #0
0002794e 002d         cmp       r5, #0
00027950 06dd         ble       #0x27960
00027952 fff7cdff     bl        #0x278f0
00027956 a100         lsls      r1, r4, #2
00027958 0134         adds      r4, #1
0002795a ac42         cmp       r4, r5
0002795c 7050         str       r0, [r6, r1]
0002795e f8db         blt       #0x27952
00027960 301c         adds      r0, r6, #0
00027962 70bd         pop       {r4, r5, r6, pc}
00027964 38b5         push      {r3, r4, r5, lr}
00027966 fff7c3ff     bl        #0x278f0
0002796a 041c         adds      r4, r0, #0
0002796c fdf7e8fb     bl        #0x25140
00027970 051c         adds      r5, r0, #0
00027972 201c         adds      r0, r4, #0
00027974 fff728f9     bl        #0x26bc8
00027978 281c         adds      r0, r5, #0
0002797a 38bd         pop       {r3, r4, r5, pc}
0002797c 70b5         push      {r4, r5, r6, lr}
0002797e 041c         adds      r4, r0, #0

; world_read [0x2b25c, 0x2b2bc) — 三字节头、名称数组、六字节记录、四字节路线记录
0002b25c 1748         ldr       r0, [pc, #0x5c]
0002b25e 10b5         push      {r4, lr}
0002b260 0021         movs      r1, #0
0002b262 7844         add       r0, pc
0002b264 fcf74cf8     bl        #0x27300
0002b268 fcf79cfa     bl        #0x277a4
0002b26c 144c         ldr       r4, [pc, #0x50]
0002b26e 4c44         add       r4, sb
0002b270 e072         strb      r0, [r4, #0xb]
0002b272 fcf797fa     bl        #0x277a4
0002b276 2073         strb      r0, [r4, #0xc]
0002b278 fcf794fa     bl        #0x277a4
0002b27c 2070         strb      r0, [r4]
0002b27e fcf75ffb     bl        #0x27940
0002b282 2062         str       r0, [r4, #0x20]
0002b284 2078         ldrb      r0, [r4]
0002b286 4300         lsls      r3, r0, #1
0002b288 1818         adds      r0, r3, r0
0002b28a 4000         lsls      r0, r0, #1
0002b28c e081         strh      r0, [r4, #0xe]
0002b28e fcf7abfa     bl        #0x277e8
0002b292 6062         str       r0, [r4, #0x24]
0002b294 fcf786fa     bl        #0x277a4
0002b298 8000         lsls      r0, r0, #2
0002b29a 2082         strh      r0, [r4, #0x10]
0002b29c fcf7a4fa     bl        #0x277e8
0002b2a0 a062         str       r0, [r4, #0x28]
0002b2a2 faf707f9     bl        #0x254b4
0002b2a6 1023         movs      r3, #0x10
0002b2a8 e05e         ldrsh     r0, [r4, r3]
0002b2aa fcf767f8     bl        #0x2737c
0002b2ae 1023         movs      r3, #0x10
0002b2b0 e062         str       r0, [r4, #0x2c]
0002b2b2 e05e         ldrsh     r0, [r4, r3]
0002b2b4 fcf762f8     bl        #0x2737c
0002b2b8 2063         str       r0, [r4, #0x30]
0002b2ba 10bd         pop       {r4, pc}

; tile_palette_read [0x2fb50, 0x2fb6e) — 字节数量，随后读取大端短整数数组
0002fb50 38b5         push      {r3, r4, r5, lr}
0002fb52 f7f727fe     bl        #0x277a4
0002fb56 051c         adds      r5, r0, #0
0002fb58 0820         movs      r0, #8
0002fb5a f7f70ffc     bl        #0x2737c
0002fb5e 041c         adds      r4, r0, #0
0002fb60 0571         strb      r5, [r0, #4]
0002fb62 281c         adds      r0, r5, #0
0002fb64 f7f7b8fe     bl        #0x278d8
0002fb68 2060         str       r0, [r4]
0002fb6a 201c         adds      r0, r4, #0
0002fb6c 38bd         pop       {r3, r4, r5, pc}
