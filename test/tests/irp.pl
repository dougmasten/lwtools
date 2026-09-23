#!/usr/bin/env perl
#
# tests for the IRP directive

$lwasm = './lwasm/lwasm';
$tmp = "/tmp/lwasm_irp_$$";

# assemble source, return (exit status, output bytes as hex, stderr text)
sub asm
{
	my ($src) = @_;
	open F, ">$tmp.asm";
	print F $src;
	close F;
	unlink "$tmp.bin";
	my $err = `$lwasm -f raw -o $tmp.bin $tmp.asm 2>&1 >/dev/null`;
	my $rc = $? >> 8;
	my $hex = '';
	if (open B, "<$tmp.bin")
	{
		binmode B;
		local $/;
		$hex = unpack('H*', <B>);
		close B;
	}
	return ($rc, uc($hex), $err);
}

sub check
{
	my ($name, $ok) = @_;
	print "$name " . ($ok ? 'PASS' : 'FAIL') . "\n";
}

sub expect_bytes
{
	my ($name, $src, $want) = @_;
	my ($rc, $hex) = asm($src);
	check($name, $rc == 0 && $hex eq $want);
}

sub expect_error
{
	my ($name, $src, $pat) = @_;
	my ($rc, $hex, $err) = asm($src);
	check($name, $rc != 0 && $err =~ /$pat/);
}

expect_bytes('basic',              "\tirp v,1,2,3,4\n\tfcb \\v\n\tendr\n", '01020304');
expect_bytes('one_value',          "\tirp v,42\n\tfcb \\v\n\tendr\n", '2A');
expect_bytes('brace_form',         "\tirp v,5,6\n\tfcb \\{v}\n\tendr\n", '0506');
expect_bytes('brace_disambiguate', "\tirp v,1,2\nlbl\\{v}\tfcb \\v\n\tendr\n\tfdb lbl1,lbl2\n", '010200000001');
expect_bytes('multi_line_body',    "\tirp v,1,2\n\tinca\n\tincb\n\tendr\n", '4C5C4C5C');
expect_bytes('surrounding_code',   "\tnop\n\tirp v,1,2\n\tinca\n\tendr\n\trts\n", '124C4C39');
expect_bytes('textual_values',     "\tirp v,A,B,C\nlbl\\v\tfcb 0\n\tendr\n", '000000');
expect_bytes('quoted_values',      "\tirp v,\"a,b\",\"c\"\n\tfcc \"\\v\"\n\tendr\n", '612C6263');
expect_bytes('no_false_prefix',    "\tirp v,1,2\n\tirp vv,3,4\n\tfcb \\v,\\vv\n\tendr\n\tendr\n", '0103010402030204');
expect_bytes('nested_irp',         "\tirp a,1,2\n\tirp b,3,4\n\tfcb \\a,\\b\n\tendr\n\tendr\n", '0103010402030204');
expect_bytes('irp_in_rept',        "\trept 2\n\tirp v,1,2\n\tfcb \\v\n\tendr\n\tendr\n", '01020102');
expect_bytes('rept_in_irp',        "\tirp v,1,2\n\trept 2\n\tfcb \\v\n\tendr\n\tendr\n", '01010202');
expect_bytes('irp_in_macro',       "m\tmacro\n\tirp v,1,2\n\tfcb \\v\n\tendr\n\tendm\n\tm\n", '0102');
expect_bytes('irp_and_macro_args', "m\tmacro\n\tirp v,1,2\n\tfcb \\v,\\1\n\tendr\n\tendm\n\tm 99\n", '01630263');
expect_bytes('case_insensitive',   "\tIRP v,1,2\n\tfcb \\v\n\tENDR\n", '0102');
expect_bytes('local_labels',       "\tirp v,1,2\n\@l\tbra \@l\n\tendr\n", '20FE20FE');
expect_bytes('label_on_irp',       "lbl\tirp v,1,2\n\tnop\n\tendr\n\tfdb lbl\n", '12120000');
expect_bytes('label_on_endr',      "\tirp v,1,2\n\tnop\nfin\tendr\n\tfdb fin\n", '12120002');
expect_bytes('in_false_cond',      "\tif 0\n\tirp v,1,2\n\tnop\n\tendr\n\tendc\n\trts\n", '39');
expect_bytes('in_true_cond',       "\tif 1\n\tirp v,1,2\n\tnop\n\tendr\n\tendc\n", '1212');

expect_error('endr_without_irp',   "\tendr\n", 'ENDR without REPT/IRP');
expect_error('irp_without_endr',   "\tirp v,1,2\n\tnop\n", 'REPT/IRP without ENDR');
expect_error('irp_no_values',      "\tirp v\n\tnop\n\tendr\n", 'IRP requires at least one value');
expect_error('irp_no_param',       "\tirp\n\tnop\n\tendr\n", 'Invalid IRP parameter name');
expect_error('irp_digit_param',    "\tirp 1,2,3\n\tnop\n\tendr\n", 'Invalid IRP parameter name');

unlink "$tmp.asm", "$tmp.bin";
