function '@start.mr': line=0 args=0 upvalues=0 max_stack=13 (150 instructions)
constants:
  K0: '_com' (string)
  K1: 3629 (int32)
  K2: 2913 (int32)
  K3: '_mr_c_load' (string)
  K4: 'gc_times' (string)
  K5: 0 (int32)
  K6: 'dealevent' (string)
  K7: 'dealtimer' (string)
  K8: 'suspend' (string)
  K9: 'resume' (string)
  K10: 'sysinfo' (string)
  K11: 'GetSysInfo' (string)
  K12: 'hsman' (string)
  K13: 'sdk' (string)
  K14: 'file' (string)
  K15: 'open' (string)
  K16: 'sdk_key.dat' (string)
  K17: 1 (int32)
  K18: 'read' (string)
  K19: 500 (int32)
  K20: 'close' (string)
  K21: '_strCom' (string)
  K22: 501 (int32)
  K23: 'vmver' (string)
  K24: 'string' (string)
  K25: 'sub' (string)
  K26: 'IMEI' (string)
  K27: 3 (int32)
  K28: 2 (int32)
  K29: 7 (int32)
  K30: 'hstype' (string)
  K31: 9 (int32)
  K32: 14 (int32)
  K33: '_error' (string)
  K34: 'cann`t find sdk key!' (string)
  K35: 801 (int32)
  K36: 6 (int32)
  K37: '_gc' (string)
  K38: '' (string)
  K39: '_mr_param' (string)
  K40: 'subV' (string)
  K41: 'pack' (string)
  K42: 'iii' (string)
  K43: 5001 (int32)
  K44: 'Exit' (string)
locals: [{'name': 'f', 'start': 28, 'end': 108}, {'name': 'key', 'start': 33, 'end': 103}, {'name': 'this_key', 'start': 50, 'end': 103}, {'name': 'p_mr_param', 'start': 135, 'end': 146}, {'name': 'param_len', 'start': 135, 'end': 146}]
instruction listing:
  0000  00000005  GETGLOBAL    R0 K0 ('_com')   ; source_line=2
  0001  01000041  LOADK        R1 K1 (3629)   ; source_line=2
  0002  02000081  LOADK        R2 K2 (2913)   ; source_line=2
  0003  00018059  CALL         A=0 B=3 C=1   ; source_line=2
  0004  00000022  CLOSURE      R0 Bx=0   ; source_line=52
  0005  000000c7  SETGLOBAL    R0 K3 ('_mr_c_load')   ; source_line=40
  0006  00000141  LOADK        R0 K5 (0)   ; source_line=60
  0007  00000107  SETGLOBAL    R0 K4 ('gc_times')   ; source_line=60
  0008  00000062  CLOSURE      R0 Bx=1   ; source_line=96
  0009  00000187  SETGLOBAL    R0 K6 ('dealevent')   ; source_line=68
  0010  000000a2  CLOSURE      R0 Bx=2   ; source_line=101
  0011  000001c7  SETGLOBAL    R0 K7 ('dealtimer')   ; source_line=98
  0012  000000e2  CLOSURE      R0 Bx=3   ; source_line=106
  0013  00000207  SETGLOBAL    R0 K8 ('suspend')   ; source_line=103
  0014  00000122  CLOSURE      R0 Bx=4   ; source_line=111
  0015  00000247  SETGLOBAL    R0 K9 ('resume')   ; source_line=108
  0016  000002c5  GETGLOBAL    R0 K11 ('GetSysInfo')   ; source_line=129
  0017  00008099  CALL         A=0 B=1 C=2   ; source_line=129
  0018  00000287  SETGLOBAL    R0 K10 ('sysinfo')   ; source_line=129
  0019  00000285  GETGLOBAL    R0 K10 ('sysinfo')   ; source_line=132
  0020  00004186  GETTABLE     R0 R0 K12('hsman')   ; source_line=132
  0021  010041d5  EQ           R1 R0 K13('sdk')   ; source_line=132
  0022  00801514  JMP          R0 sBx=+85 goto-PC=108   ; source_line=132
  0023  00000385  GETGLOBAL    R0 K14 ('file')   ; source_line=134
  0024  00004246  GETTABLE     R0 R0 K15('open')   ; source_line=134
  0025  01000401  LOADK        R1 K16 ('sdk_key.dat')   ; source_line=134
  0026  02000441  LOADK        R2 K17 (1)   ; source_line=134
  0027  00018099  CALL         A=0 B=3 C=2   ; source_line=134
  0028  00000018  TEST         A=0 B=0 C=0   ; source_line=135
  0029  00801254  JMP          R0 sBx=+74 goto-PC=104   ; source_line=135
  0030  0100430b  SELF         R1 R0 K18('read')   ; source_line=136
  0031  030004c1  LOADK        R3 K19 (500)   ; source_line=136
  0032  01018099  CALL         A=1 B=3 C=2   ; source_line=136
  0033  0200438b  SELF         R2 R0 K20('close')   ; source_line=137
  0034  02010059  CALL         A=2 B=2 C=1   ; source_line=137
  0035  02000545  GETGLOBAL    R2 K21 ('_strCom')   ; source_line=138
  0036  030004c1  LOADK        R3 K19 (500)   ; source_line=138
  0037  04000545  GETGLOBAL    R4 K21 ('_strCom')   ; source_line=138
  0038  05000581  LOADK        R5 K22 (501)   ; source_line=138
  0039  06000285  GETGLOBAL    R6 K10 ('sysinfo')   ; source_line=138
  0040  06034446  GETTABLE     R6 R6 K23('vmver')   ; source_line=138
  0041  07000605  GETGLOBAL    R7 K24 ('string')   ; source_line=138
  0042  0703c4c6  GETTABLE     R7 R7 K25('sub')   ; source_line=138
  0043  08000285  GETGLOBAL    R8 K10 ('sysinfo')   ; source_line=138
  0044  08044506  GETTABLE     R8 R8 K26('IMEI')   ; source_line=138
  0045  090006c1  LOADK        R9 K27 (3)   ; source_line=138
  0046  07018099  CALL         A=7 B=3 C=2   ; source_line=138
  0047  060301d3  CONCAT       A=6 B=6 C=7   ; source_line=138
  0048  04018019  CALL         A=4 B=3 C=0   ; source_line=138
  0049  02000099  CALL         A=2 B=0 C=2   ; source_line=138
  0050  03010000  MOVE         A=3 B=2 C=0   ; source_line=139
  0051  04000545  GETGLOBAL    R4 K21 ('_strCom')   ; source_line=139
  0052  050004c1  LOADK        R5 K19 (500)   ; source_line=139
  0053  06000545  GETGLOBAL    R6 K21 ('_strCom')   ; source_line=139
  0054  07000581  LOADK        R7 K22 (501)   ; source_line=139
  0055  08000605  GETGLOBAL    R8 K24 ('string')   ; source_line=139
  0056  080444c6  GETTABLE     R8 R8 K25('sub')   ; source_line=139
  0057  09000285  GETGLOBAL    R9 K10 ('sysinfo')   ; source_line=139
  0058  0904c506  GETTABLE     R9 R9 K26('IMEI')   ; source_line=139
  0059  0a000701  LOADK        R10 K28 (2)   ; source_line=139
  0060  0b000741  LOADK        R11 K29 (7)   ; source_line=139
  0061  08020099  CALL         A=8 B=4 C=2   ; source_line=139
  0062  09000285  GETGLOBAL    R9 K10 ('sysinfo')   ; source_line=139
  0063  0904c186  GETTABLE     R9 R9 K12('hsman')   ; source_line=139
  0064  0a000605  GETGLOBAL    R10 K24 ('string')   ; source_line=139
  0065  0a0544c6  GETTABLE     R10 R10 K25('sub')   ; source_line=139
  0066  0b000285  GETGLOBAL    R11 K10 ('sysinfo')   ; source_line=139
  0067  0b05c606  GETTABLE     R11 R11 K30('hstype')   ; source_line=139
  0068  0c000701  LOADK        R12 K28 (2)   ; source_line=139
  0069  0a018099  CALL         A=10 B=3 C=2   ; source_line=139
  0070  08040293  CONCAT       A=8 B=8 C=10   ; source_line=139
  0071  06018019  CALL         A=6 B=3 C=0   ; source_line=139
  0072  04000099  CALL         A=4 B=0 C=2   ; source_line=139
  0073  02018113  CONCAT       A=2 B=3 C=4   ; source_line=139
  0074  03010000  MOVE         A=3 B=2 C=0   ; source_line=140
  0075  04000545  GETGLOBAL    R4 K21 ('_strCom')   ; source_line=140
  0076  050004c1  LOADK        R5 K19 (500)   ; source_line=140
  0077  06000545  GETGLOBAL    R6 K21 ('_strCom')   ; source_line=140
  0078  07000581  LOADK        R7 K22 (501)   ; source_line=140
  0079  08000605  GETGLOBAL    R8 K24 ('string')   ; source_line=140
  0080  080444c6  GETTABLE     R8 R8 K25('sub')   ; source_line=140
  0081  09000285  GETGLOBAL    R9 K10 ('sysinfo')   ; source_line=140
  0082  0904c506  GETTABLE     R9 R9 K26('IMEI')   ; source_line=140
  0083  0a0007c1  LOADK        R10 K31 (9)   ; source_line=140
  0084  0b000801  LOADK        R11 K32 (14)   ; source_line=140
  0085  08020099  CALL         A=8 B=4 C=2   ; source_line=140
  0086  09000605  GETGLOBAL    R9 K24 ('string')   ; source_line=140
  0087  0904c4c6  GETTABLE     R9 R9 K25('sub')   ; source_line=140
  0088  0a000285  GETGLOBAL    R10 K10 ('sysinfo')   ; source_line=140
  0089  0a054606  GETTABLE     R10 R10 K30('hstype')   ; source_line=140
  0090  0b000441  LOADK        R11 K17 (1)   ; source_line=140
  0091  0c0006c1  LOADK        R12 K27 (3)   ; source_line=140
  0092  09020099  CALL         A=9 B=4 C=2   ; source_line=140
  0093  08040253  CONCAT       A=8 B=8 C=9   ; source_line=140
  0094  06018019  CALL         A=6 B=3 C=0   ; source_line=140
  0095  04000099  CALL         A=4 B=0 C=2   ; source_line=140
  0096  02018113  CONCAT       A=2 B=3 C=4   ; source_line=140
  0097  01008095  EQ           R1 R1 R2   ; source_line=142
  0098  00800214  JMP          R0 sBx=+9 goto-PC=108   ; source_line=142
  0099  03000845  GETGLOBAL    R3 K33 ('_error')   ; source_line=143
  0100  04000881  LOADK        R4 K34 ('cann`t find sdk key!')   ; source_line=143
  0101  03010059  CALL         A=3 B=2 C=1   ; source_line=143
  0102  0000801b  RETURN       A=0 B=1 C=0   ; source_line=144
  0103  008000d4  JMP          R0 sBx=+4 goto-PC=108   ; source_line=145
  0104  01000845  GETGLOBAL    R1 K33 ('_error')   ; source_line=147
  0105  02000881  LOADK        R2 K34 ('cann`t find sdk key!')   ; source_line=147
  0106  01010059  CALL         A=1 B=2 C=1   ; source_line=147
  0107  0000801b  RETURN       A=0 B=1 C=0   ; source_line=148
  0108  000000c5  GETGLOBAL    R0 K3 ('_mr_c_load')   ; source_line=157
  0109  00008099  CALL         A=0 B=1 C=2   ; source_line=157
  0110  00003fd5  EQ           R0 R0 K5(0)   ; source_line=157
  0111  00800894  JMP          R0 sBx=+35 goto-PC=147   ; source_line=157
  0112  00000545  GETGLOBAL    R0 K21 ('_strCom')   ; source_line=163
  0113  010008c1  LOADK        R1 K35 (801)   ; source_line=163
  0114  0201000a  NEWTABLE     A=2 B=2 C=0   ; source_line=163
  0115  03000441  LOADK        R3 K17 (1)   ; source_line=163
  0116  04000285  GETGLOBAL    R4 K10 ('sysinfo')   ; source_line=163
  0117  04024446  GETTABLE     R4 R4 K23('vmver')   ; source_line=163
  0118  0200005f  SETLIST      R2 Bx=1   ; source_line=163
  0119  03000901  LOADK        R3 K36 (6)   ; source_line=163
  0120  00020059  CALL         A=0 B=4 C=1   ; source_line=163
  0121  00000945  GETGLOBAL    R0 K37 ('_gc')   ; source_line=165
  0122  00008059  CALL         A=0 B=1 C=1   ; source_line=165
  0123  00000545  GETGLOBAL    R0 K21 ('_strCom')   ; source_line=166
  0124  010008c1  LOADK        R1 K35 (801)   ; source_line=166
  0125  02000981  LOADK        R2 K38 ('')   ; source_line=166
  0126  03000141  LOADK        R3 K5 (0)   ; source_line=166
  0127  00020059  CALL         A=0 B=4 C=1   ; source_line=166
  0128  000009c5  GETGLOBAL    R0 K39 ('_mr_param')   ; source_line=168
  0129  00000018  TEST         A=0 B=0 C=0   ; source_line=168
  0130  00800454  JMP          R0 sBx=+18 goto-PC=149   ; source_line=168
  0131  00000605  GETGLOBAL    R0 K24 ('string')   ; source_line=169
  0132  00004886  GETTABLE     R0 R0 K40('subV')   ; source_line=169
  0133  010009c5  GETGLOBAL    R1 K39 ('_mr_param')   ; source_line=169
  0134  000100d9  CALL         A=0 B=2 C=3   ; source_line=169
  0135  02000545  GETGLOBAL    R2 K21 ('_strCom')   ; source_line=171
  0136  030008c1  LOADK        R3 K35 (801)   ; source_line=171
  0137  04000605  GETGLOBAL    R4 K24 ('string')   ; source_line=171
  0138  040248c6  GETTABLE     R4 R4 K41('pack')   ; source_line=171
  0139  05000a81  LOADK        R5 K42 ('iii')   ; source_line=171
  0140  06000ac1  LOADK        R6 K43 (5001)   ; source_line=171
  0141  07000000  MOVE         A=7 B=0 C=0   ; source_line=171
  0142  08008000  MOVE         A=8 B=1 C=0   ; source_line=171
  0143  04028099  CALL         A=4 B=5 C=2   ; source_line=171
  0144  05000441  LOADK        R5 K17 (1)   ; source_line=171
  0145  02020059  CALL         A=2 B=4 C=1   ; source_line=171
  0146  00800054  JMP          R0 sBx=+2 goto-PC=149   ; source_line=172
  0147  00000b05  GETGLOBAL    R0 K44 ('Exit')   ; source_line=174
  0148  00008059  CALL         A=0 B=1 C=1   ; source_line=174
  0149  0000801b  RETURN       A=0 B=1 C=0   ; source_line=175
---- nested prototype [0] ----
  function None: line=40 args=0 upvalues=0 max_stack=4 (18 instructions)
  constants:
    K0: '_mr_c_buf' (string)
    K1: '_strCom' (string)
    K2: 601 (int32)
    K3: 'cfunction.ext' (string)
    K4: 800 (int32)
    K5: 0 (int32)
    K6: 1 (int32)
    K7: -1 (int32)
  locals: [{'name': 'ret', 'start': 13, 'end': 14}]
  instruction listing:
    0000  00000045  GETGLOBAL    R0 K1 ('_strCom')   ; source_line=44
    0001  01000081  LOADK        R1 K2 (601)   ; source_line=44
    0002  020000c1  LOADK        R2 K3 ('cfunction.ext')   ; source_line=44
    0003  00018099  CALL         A=0 B=3 C=2   ; source_line=44
    0004  00000007  SETGLOBAL    R0 K0 ('_mr_c_buf')   ; source_line=44
    0005  00000005  GETGLOBAL    R0 K0 ('_mr_c_buf')   ; source_line=46
    0006  00000018  TEST         A=0 B=0 C=0   ; source_line=46
    0007  00800194  JMP          R0 sBx=+7 goto-PC=15   ; source_line=46
    0008  00000045  GETGLOBAL    R0 K1 ('_strCom')   ; source_line=47
    0009  01000101  LOADK        R1 K4 (800)   ; source_line=47
    0010  02000005  GETGLOBAL    R2 K0 ('_mr_c_buf')   ; source_line=47
    0011  03000141  LOADK        R3 K5 (0)   ; source_line=47
    0012  00020099  CALL         A=0 B=4 C=2   ; source_line=47
    0013  0001001b  RETURN       A=0 B=2 C=0   ; source_line=48
    0014  00800054  JMP          R0 sBx=+2 goto-PC=17   ; source_line=48
    0015  000001c1  LOADK        R0 K7 (-1)   ; source_line=50
    0016  0001001b  RETURN       A=0 B=2 C=0   ; source_line=50
    0017  0000801b  RETURN       A=0 B=1 C=0   ; source_line=52
---- nested prototype [1] ----
  function None: line=68 args=4 upvalues=0 max_stack=17 (62 instructions)
  constants:
    K0: 'gc_times' (string)
    K1: 20 (int32)
    K2: 'TestCom' (string)
    K3: 403 (int32)
    K4: 0 (int32)
    K5: 1 (int32)
    K6: '_t' (string)
    K7: 'str' (string)
    K8: '' (string)
    K9: 'string' (string)
    K10: 'subV' (string)
    K11: 'd_s' (string)
    K12: 'pack' (string)
    K13: 'iiiii' (string)
    K14: 'iii' (string)
    K15: '_strCom' (string)
    K16: 801 (int32)
  locals: [{'name': 'code', 'start': 0, 'end': 61}, {'name': 'p0', 'start': 0, 'end': 61}, {'name': 'p1', 'start': 0, 'end': 61}, {'name': 'p2', 'start': 0, 'end': 61}, {'name': 'p00', 'start': 21, 'end': 42}, {'name': 'p10', 'start': 24, 'end': 42}, {'name': 'pContent', 'start': 28, 'end': 42}, {'name': 'clen', 'start': 28, 'end': 42}, {'name': 'pNum', 'start': 32, 'end': 42}, {'name': 'nlen', 'start': 32, 'end': 42}, {'name': 'v', 'start': 60, 'end': 61}, {'name': 'ret', 'start': 60, 'end': 61}]
  instruction listing:
    0000  04000005  GETGLOBAL    R4 K0 ('gc_times')   ; source_line=69
    0001  007d8116  LT           R0 K1(20) R4   ; source_line=69
    0002  00800194  JMP          R0 sBx=+7 goto-PC=10   ; source_line=69
    0003  04000085  GETGLOBAL    R4 K2 ('TestCom')   ; source_line=70
    0004  050000c1  LOADK        R5 K3 (403)   ; source_line=70
    0005  06000101  LOADK        R6 K4 (0)   ; source_line=70
    0006  04018059  CALL         A=4 B=3 C=1   ; source_line=70
    0007  04000101  LOADK        R4 K4 (0)   ; source_line=71
    0008  04000007  SETGLOBAL    R4 K0 ('gc_times')   ; source_line=71
    0009  00800094  JMP          R0 sBx=+3 goto-PC=13   ; source_line=71
    0010  04000005  GETGLOBAL    R4 K0 ('gc_times')   ; source_line=73
    0011  04023fcc  ADD          R4 R4 K5(1)   ; source_line=73
    0012  04000007  SETGLOBAL    R4 K0 ('gc_times')   ; source_line=73
    0013  04000185  GETGLOBAL    R4 K6 ('_t')   ; source_line=79
    0014  05008000  MOVE         A=5 B=1 C=0   ; source_line=79
    0015  04010099  CALL         A=4 B=2 C=2   ; source_line=79
    0016  00024055  EQ           R0 R4 K7('str')   ; source_line=79
    0017  00800614  JMP          R0 sBx=+25 goto-PC=43   ; source_line=79
    0018  04008000  MOVE         A=4 B=1 C=0   ; source_line=80
    0019  05000201  LOADK        R5 K8 ('')   ; source_line=80
    0020  04020153  CONCAT       A=4 B=4 C=5   ; source_line=80
    0021  05010000  MOVE         A=5 B=2 C=0   ; source_line=81
    0022  06000201  LOADK        R6 K8 ('')   ; source_line=81
    0023  05028193  CONCAT       A=5 B=5 C=6   ; source_line=81
    0024  06000245  GETGLOBAL    R6 K9 ('string')   ; source_line=83
    0025  06034106  GETTABLE     R6 R6 K10('subV')   ; source_line=83
    0026  07020000  MOVE         A=7 B=4 C=0   ; source_line=83
    0027  060100d9  CALL         A=6 B=2 C=3   ; source_line=83
    0028  08000245  GETGLOBAL    R8 K9 ('string')   ; source_line=87
    0029  08044106  GETTABLE     R8 R8 K10('subV')   ; source_line=87
    0030  09028000  MOVE         A=9 B=5 C=0   ; source_line=87
    0031  080100d9  CALL         A=8 B=2 C=3   ; source_line=87
    0032  0a000245  GETGLOBAL    R10 K9 ('string')   ; source_line=88
    0033  0a054186  GETTABLE     R10 R10 K12('pack')   ; source_line=88
    0034  0b000341  LOADK        R11 K13 ('iiiii')   ; source_line=88
    0035  0c000000  MOVE         A=12 B=0 C=0   ; source_line=88
    0036  0d030000  MOVE         A=13 B=6 C=0   ; source_line=88
    0037  0e040000  MOVE         A=14 B=8 C=0   ; source_line=88
    0038  0f018000  MOVE         A=15 B=3 C=0   ; source_line=88
    0039  10038000  MOVE         A=16 B=7 C=0   ; source_line=88
    0040  0a038099  CALL         A=10 B=7 C=2   ; source_line=88
    0041  0a0002c7  SETGLOBAL    R10 K11 ('d_s')   ; source_line=88
    0042  008002d4  JMP          R0 sBx=+12 goto-PC=55   ; source_line=88
    0043  04000245  GETGLOBAL    R4 K9 ('string')   ; source_line=90
    0044  04024186  GETTABLE     R4 R4 K12('pack')   ; source_line=90
    0045  05000381  LOADK        R5 K14 ('iii')   ; source_line=90
    0046  06000000  MOVE         A=6 B=0 C=0   ; source_line=90
    0047  07008058  TEST         A=7 B=1 C=1   ; source_line=90
    0048  00800014  JMP          R0 sBx=+1 goto-PC=50   ; source_line=90
    0049  07000101  LOADK        R7 K4 (0)   ; source_line=90
    0050  08010058  TEST         A=8 B=2 C=1   ; source_line=90
    0051  00800014  JMP          R0 sBx=+1 goto-PC=53   ; source_line=90
    0052  08000101  LOADK        R8 K4 (0)   ; source_line=90
    0053  04028099  CALL         A=4 B=5 C=2   ; source_line=90
    0054  040002c7  SETGLOBAL    R4 K11 ('d_s')   ; source_line=90
    0055  040003c5  GETGLOBAL    R4 K15 ('_strCom')   ; source_line=93
    0056  05000401  LOADK        R5 K16 (801)   ; source_line=93
    0057  060002c5  GETGLOBAL    R6 K11 ('d_s')   ; source_line=93
    0058  07000141  LOADK        R7 K5 (1)   ; source_line=93
    0059  040200d9  CALL         A=4 B=4 C=3   ; source_line=93
    0060  0501001b  RETURN       A=5 B=2 C=0   ; source_line=95
    0061  0000801b  RETURN       A=0 B=1 C=0   ; source_line=96
---- nested prototype [2] ----
  function None: line=98 args=0 upvalues=0 max_stack=4 (10 instructions)
  constants:
    K0: 't_v' (string)
    K1: 't_ret' (string)
    K2: '_strCom' (string)
    K3: 801 (int32)
    K4: '' (string)
    K5: 2 (int32)
  locals: []
  instruction listing:
    0000  00000085  GETGLOBAL    R0 K2 ('_strCom')   ; source_line=99
    0001  010000c1  LOADK        R1 K3 (801)   ; source_line=99
    0002  02000101  LOADK        R2 K4 ('')   ; source_line=99
    0003  03000141  LOADK        R3 K5 (2)   ; source_line=99
    0004  000200d9  CALL         A=0 B=4 C=3   ; source_line=99
    0005  01000047  SETGLOBAL    R1 K1 ('t_ret')   ; source_line=99
    0006  00000007  SETGLOBAL    R0 K0 ('t_v')   ; source_line=99
    0007  00000045  GETGLOBAL    R0 K1 ('t_ret')   ; source_line=100
    0008  0001001b  RETURN       A=0 B=2 C=0   ; source_line=100
    0009  0000801b  RETURN       A=0 B=1 C=0   ; source_line=101
---- nested prototype [3] ----
  function None: line=103 args=0 upvalues=0 max_stack=4 (10 instructions)
  constants:
    K0: 's_v' (string)
    K1: 's_ret' (string)
    K2: '_strCom' (string)
    K3: 801 (int32)
    K4: '' (string)
    K5: 4 (int32)
  locals: []
  instruction listing:
    0000  00000085  GETGLOBAL    R0 K2 ('_strCom')   ; source_line=104
    0001  010000c1  LOADK        R1 K3 (801)   ; source_line=104
    0002  02000101  LOADK        R2 K4 ('')   ; source_line=104
    0003  03000141  LOADK        R3 K5 (4)   ; source_line=104
    0004  000200d9  CALL         A=0 B=4 C=3   ; source_line=104
    0005  01000047  SETGLOBAL    R1 K1 ('s_ret')   ; source_line=104
    0006  00000007  SETGLOBAL    R0 K0 ('s_v')   ; source_line=104
    0007  00000045  GETGLOBAL    R0 K1 ('s_ret')   ; source_line=105
    0008  0001001b  RETURN       A=0 B=2 C=0   ; source_line=105
    0009  0000801b  RETURN       A=0 B=1 C=0   ; source_line=106
---- nested prototype [4] ----
  function None: line=108 args=0 upvalues=0 max_stack=4 (10 instructions)
  constants:
    K0: 'r_v' (string)
    K1: 'r_ret' (string)
    K2: '_strCom' (string)
    K3: 801 (int32)
    K4: '' (string)
    K5: 5 (int32)
  locals: []
  instruction listing:
    0000  00000085  GETGLOBAL    R0 K2 ('_strCom')   ; source_line=109
    0001  010000c1  LOADK        R1 K3 (801)   ; source_line=109
    0002  02000101  LOADK        R2 K4 ('')   ; source_line=109
    0003  03000141  LOADK        R3 K5 (5)   ; source_line=109
    0004  000200d9  CALL         A=0 B=4 C=3   ; source_line=109
    0005  01000047  SETGLOBAL    R1 K1 ('r_ret')   ; source_line=109
    0006  00000007  SETGLOBAL    R0 K0 ('r_v')   ; source_line=109
    0007  00000045  GETGLOBAL    R0 K1 ('r_ret')   ; source_line=110
    0008  0001001b  RETURN       A=0 B=2 C=0   ; source_line=110
    0009  0000801b  RETURN       A=0 B=1 C=0   ; source_line=111
