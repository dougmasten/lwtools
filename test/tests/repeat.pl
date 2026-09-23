#!/usr/bin/env perl
#
# tests for the REPT directive

$lwasm = './lwasm/lwasm';
$tmp = "/tmp/lwasm_rept_$$";

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

expect_bytes('basic',            "\trept 3\n\tnop\n\tendr\n", '121212');
expect_bytes('count_one',        "\trept 1\n\tinca\n\tendr\n", '4C');
expect_bytes('count_zero',       "\tnop\n\trept 0\n\tfcb 99\n\tendr\n\trts\n", '1239');
expect_bytes('count_expr',       "N equ 2\n\trept N+1\n\tnop\n\tendr\n", '121212');
expect_bytes('set_increment',    "i\tset\t0\n\trept 5\n\tfcb i\ni set i+1\n\tendr\n", '0001020304');
expect_bytes('multi_line_body',	 "\trept 2\n\tinca\n\tincb\n\tendr\n", '4C5C4C5C');
expect_bytes('surrounding_code', "\tnop\n\trept 2\n\tinca\n\tendr\n\trts\n", '124C4C39');
expect_bytes('nested',           "\trept 2\n\trept 3\n\tinca\n\tendr\n\tincb\n\tendr\n", '4C4C4C5C4C4C4C5C');
expect_bytes('local_labels',     "\trept 2\n\@l\tbra \@l\n\tendr\n", '20FE20FE');
expect_bytes('label_on_rept',    "lbl\trept 2\n\tnop\n\tendr\n\tfdb lbl\n", '12120000');
expect_bytes('label_on_rept2',   "\tnop\nlbl\trept 2\n\tnop\n\tendr\n\tfdb lbl\n", '1212120001');
expect_bytes('label_rept_zero',  "lbl\trept 0\n\tnop\n\tendr\n\tfdb lbl\n", '0000');
expect_bytes('label_on_endr',    "\trept 2\n\tnop\nfin\tendr\n\tfdb fin\n", '12120002');
expect_bytes('label_endrep_zero',"\trept 0\n\tnop\nfin\tendr\n\tfdb fin\n", '0000');
expect_bytes('label_both_ends',  "beg\trept 2\n\tnop\nfin\tendr\n\tfdb beg\n\tfdb fin\n", '121200000002');
expect_bytes('label_endrep_nest',"\trept 2\n\trept 2\n\tnop\n\tendr\nout\tendr\n\tfdb out\n", '121212120004');
expect_bytes('case_insensitive', "\tREPT 2\n\tnop\n\tENDR\n", '1212');
expect_bytes('rept_synonym',     "\trept 3\n\tnop\n\tendr\n", '121212');
expect_bytes('rept_endr',        "\trept 2\n\tnop\n\tendr\n", '1212');
expect_bytes('nested_mixed',     "\trept 2\n\trept 2\n\tinca\n\tendr\n\tincb\n\tendr\n", '4C4C5C4C4C5C');
expect_bytes('in_false_cond',    "\tif 0\n\trept 2\n\tnop\n\tendr\n\tendc\n\trts\n", '39');
expect_bytes('in_true_cond',     "\tif 1\n\trept 2\n\tnop\n\tendr\n\tendc\n", '1212');
expect_bytes('macro_in_body',    "m\tmacro\n\tinca\n\tendm\n\trept 2\n\tm\n\tendr\n", '4C4C');
expect_bytes('inside_macro_def', "m\tmacro\n\trept 2\n\tnop\n\tendr\n\tendm\n\tm\n", '1212');

expect_error('endr_without_rept', "\tendr\n", 'ENDR without REPT/IRP');
expect_error('rept_without_endr', "\trept 2\n\tnop\n", 'REPT/IRP without ENDR');
expect_error('negative_count',    "\trept -1\n\tnop\n\tendr\n", 'Invalid REPT count');
expect_error('nonconst_count',    "\trept undefined_sym\n\tnop\n\tendr\n", '.');

unlink "$tmp.asm", "$tmp.bin";
