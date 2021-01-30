#!/usr/bin/env perl
#
# these tests determine if the opcodes for each instruction, in each
# addressing mode, are correct.
#
# The following list is used to construct the tests. The key is the
# mneumonic and the value is a list of address mode characters as follows
#
# R: register/inherent
# I: immediate
# E: extended
# D: direct
# i: indexed
# r: register to register (TFR, etc.)
# p: psh/pul
# BB: bit/bit
# LD: logical direct
# Li: logical indexed
# LE: logical extended
# T#: tfm
# each letter is followed by an = and the 2 or 4 digit opcode in hex
# each entry is separated by a comma

$lwasm = './lwasm/lwasm';

%insnlist = (
	'adcd' => 'I=1089,D=1099,i=10A9,E=10B9',
	'adcr' => 'r=1031',
	'adde' => 'I=118B,D=119B,i=11AB,E=11BB',
	'addf' => 'I=11CB,D=11DB,i=11EB,E=11FB',
	'addw' => 'I=108B,D=109B,i=10AB,E=10BB',
	'addr' => 'r=1030',
	'aim' => 'LD=02,Li=62,LE=72',
	'andd' => 'I=1084,D=1094,i=10A4,E=10B4',
	'andr' => 'r=1034',
	'asld' => 'R=1048',
	'asrd' => 'R=1047',
	'band' => 'BB=1130',
	'beor' => 'BB=1134',
	'biand' => 'BB=1131',
	'bieor' => 'BB=1135',
	'bior' => 'BB=1133',
	'bitd' => 'I=1085,D=1095,i=10A5,E=10B5',
	'bitmd' => 'I=113C',
	'bor' => 'BB=1132',
	'clrd' => 'R=104F',
	'clre' => 'R=114F',
	'clrf' => 'R=115F',
	'clrw' => 'R=105F',
	'cmpe' => 'I=1181,D=1191,i=11A1,E=11B1',
	'cmpf' => 'I=11C1,D=11D1,i=11E1,E=11F1',
	'cmpw' => 'I=1081,D=1091,i=10A1,E=10B1',
	'cmpr' => 'r=1037',
	'comd' => 'R=1043',
	'come' => 'R=1143',
	'comf' => 'R=1153',
	'comw' => 'R=1053',
	'decd' => 'R=104A',
	'dece' => 'R=114A',
	'decf' => 'R=115A',
	'decw' => 'R=105A',
	'divd' => 'I=118D,D=119D,i=11AD,E=11BD',
	'divq' => 'I=118E,D=119E,i=11AE,E=11BE',
	'eim' => 'LD=05,Li=65,LE=75',
	'eord' => 'I=1088,D=1098,i=10A8,E=10B8',
	'eorr' => 'r=1036',
	'incd' => 'R=104C',
	'ince' => 'R=114C',
	'incf' => 'R=115C',
	'incw' => 'R=105C',
	'lde' => 'I=1186,D=1196,i=11A6,E=11B6',
	'ldf' => 'I=11C6,D=11D6,i=11E6,E=11F6',
	'ldw' => 'I=1086,D=1096,i=10A6,E=10B6',
	'ldbt' => 'BB=1136',
	'ldmd' => 'I=113D',
	'ldq' => 'I=CD,D=10DC,i=10EC,E=10FC',
	'lsld' => 'R=1048',
	'lsrd' => 'R=1044',
	'lsrw' => 'R=1054',
	'muld' => 'I=118F,D=119F,i=11AF,E=11BF',
	'negd' => 'R=1040',
	'oim' => 'LD=01,Li=61,LE=71',
	'ord' => 'I=108A,D=109A,i=10AA,E=10BA',
	'orr' => 'r=1035',
	'pshsw' => 'R=1038',
	'pshuw' => 'R=103A',
	'pulsw' => 'R=1039',
	'puluw' => 'R=103B',
	'rold' => 'R=1049',
	'rolw' => 'R=1059',
	'rord' => 'R=1046',
	'rorw' => 'R=1056',
	'sbcd' => 'I=1082,D=1092,i=10A2,E=10B2',
	'sbcr' => 'r=1033',
	'sexw' => 'R=14',
	'ste' => 'D=1197,i=11A7,E=11B7',
	'stf' => 'D=11D7,i=11E7,E=11F7',
	'stw' => 'D=1097,i=10A7,E=10B7',
	'stbt' => 'BB=1137',
	'stq' => 'D=10DD,i=10ED,E=10FD',
	'sube' => 'I=1180,D=1190,i=11A0,E=11B0',
	'subf' => 'I=11C0,D=11D0,i=11E0,E=11F0',
	'subw' => 'I=1080,D=1090,i=10A0,E=10B0',
	'subr' => 'r=1032',
	'tfm' => 'T1=1138,T2=1139,T3=113A,T4=113B',
	'tim' => 'LD=0B,Li=6B,LE=7B',
	'tstd' => 'R=104D',
	'tste' => 'R=114D',
	'tstf' => 'R=115D',
	'tstw' => 'R=105D',
);

foreach $i (keys %insnlist)
{
	#print "$i ... $insnlist{$i}\n";
	@modes = split(/,/, $insnlist{$i});
	foreach $j (@modes)
	{
		($mc, $oc) = split(/=/, $j);
		$operand = '';
		if ($mc eq 'D')
		{
			$operand = '<0';
		}
		elsif ($mc eq 'E')
		{
			$operand = '>0';
		}
		elsif ($mc eq 'I')
		{
			$operand = '#0';
		}
		elsif ($mc eq 'i')
		{
			$operand = ',x';
		}
		elsif ($mc eq 'r')
		{
			$operand = 'a,a';
		}
		elsif ($mc eq 'p')
		{
			$operand = 'cc';
		}
		elsif ($mc eq 'b')
		{
			$operand = '*';
		}
		elsif ($mc eq 'T1')
		{
			$operand = 'x+,y+';
		}
		elsif ($mc eq 'T2')
		{
			$operand = 'x-,y-';
		}
		elsif ($mc eq 'T3')
		{
			$operand = 'x+,y';
		}
		elsif ($mc eq 'T4')
		{
			$operand = 'x,y+';
		}
		elsif ($mc eq 'BB')
		{
			$operand = 'a,0,0,0';
		}
		elsif ($mc eq 'LD')
		{
			$operand = '#0;<0';
		}
		elsif ($mc eq 'Li')
		{
			$operand = '#0;0,u';
		}
		elsif ($mc eq 'LE')
		{
			$operand = '#0;>0';
		}
		$asmcode = "\t$i $operand";

		# now feed the asm code to the assembler and fetch the result
		$tf = ".asmtmp.$$.$i.$mc";
		open H, ">$tf.asm";
		print H "$asmcode\n";
		close H;
		$r = `$lwasm --raw --list -o $tf $tf.asm`;
		open H, "<$tf";
		binmode H;
		$buffer = '';
		$r = read(H, $buffer, 10);
		close H;
		unlink $tf;
		unlink "$tf.asm";
		if ($r == 0)
		{
			$st = 'FAIL (no result)';
		}
		else
		{
			@bytes = split(//,$buffer);
			$rc = sprintf('%02X', ord($bytes[0]));
			if (length($oc) > 2)
			{
				$rc .= sprintf('%02X', ord($bytes[1]));
			}
			if ($rc ne $oc)
			{
				$st = "FAIL ($rc ≠ $oc, $asmcode)";
			}
			else
			{
				$st = 'PASS';
			}
		}
		print "$i" . "_$mc $st\n";
	}
}
