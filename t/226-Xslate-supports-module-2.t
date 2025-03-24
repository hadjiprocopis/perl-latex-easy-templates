#!/usr/bin/env perl

###################################################################
#### NOTE env-var PERL_TEST_TEMPDIR_TINY_NOCLEANUP=1 will stop erasing tmp files
###################################################################

use strict;
use warnings;

use lib 'blib/lib';

use utf8;

our $VERSION = '1.03';

use Test::More;
use Test::More::UTF8;
use Mojo::Log;
use File::Basename;
use FindBin;
use Test::TempDir::Tiny;
use File::Compare;

use Data::Roundtrip qw/perl2dump perl2json json2perl jsonfile2perl no-unicode-escape-permanently/;

use LaTeX::Easy::Templates;

my $VERBOSITY = 1;

my $log = Mojo::Log->new;

my $curdir = $FindBin::Bin;

# if for debug you change this make sure that it has path in it e.g. ./xyz
my $tmpdir = tempdir(); # will be erased unless a BAIL_OUT or env var set
ok(-d $tmpdir, "tmpdir exists $tmpdir") or BAIL_OUT;

my $template_dir = File::Spec->catdir($curdir, 'templates', 'simple05');
my $template_filename = File::Spec->catfile($template_dir, 'main.tex.tx');
my $expected_latex_output_filename = $template_filename; $expected_latex_output_filename =~ s/\.tx$/.expected_output/;
# let's see if myfunc() defined in perl will be supported in the template
# this returns {
#  a => ...
# }
# but when we run exact same thing in this file we get {a=>...} (no spaces)!
my $template_string = ': basename($data);';

my $template_data = 'αβγ/δεζ.τχτ';

my $latterparams = {
	'debug' => {
		'verbosity' => $VERBOSITY,
	},
	'log' => $log,
	'templater-parameters' => {
		'function' => {
			'myfunc' => \&myfunc,
		},
		'module' => [
			'File::Basename' => [],
			'Data::Roundtrip' => ['perl2dump', 'perl2json', 'json2perl', 'jsonfile2perl', 'no-unicode-escape-permanently'],
		],
	},
	'processors' => {
		# 1 in memory string
		'test-module' => {
		   'latex' => {
			# untemplate the in-memory template into this latex source file:
			'basedir' => File::Spec->catdir($tmpdir, 'adir'),
			# this must end in .tex
			'filename' => 'aaa.tex',
		   },
		   'template' => {
			'content' => $template_string,
			'auxfiles' => [ $template_dir ],
		   },
		   'output' => {
			#'filename' => File::Spec->catfile($tempdir, 'inmemory.pdf'),
			'basedir' => File::Spec->catdir($tmpdir, 'tmp', 'aaa'),
			'filename' => 'inmemory.pdf',
		   },
		},
	},
};
my $latter = LaTeX::Easy::Templates->new($latterparams);
ok(defined($latter), 'LaTeX::Easy::Templates->new()'." : called and got good result.") or BAIL_OUT;

for my $aprocessorname ('test-module'){
	my $processor_data = $latterparams->{'processors'}->{$aprocessorname};
	my $untemplate_ret = $latter->untemplate({
		'processor' => $aprocessorname,
		'template-data' => $template_data
	});
	ok(defined($untemplate_ret), 'untemplate()'." : called for processor '$aprocessorname', and got good result.") or BAIL_OUT;
	is(ref($untemplate_ret), 'HASH', 'untemplate()'." : called for processor '$aprocessorname', and got a scalar back.") or BAIL_OUT;

	for my $ak ('template', 'latex'){
		ok(exists($untemplate_ret->{$ak}), 'untemplate()'." : called for processor '$aprocessorname', and returned result contains key '$ak'.") or BAIL_OUT(perl2dump($untemplate_ret)."no, above is what was returned.");
		is(ref($untemplate_ret->{$ak}), 'HASH', 'untemplate()'." : called for processor '$aprocessorname', and returned result contains key '$ak' and it is a SCALAR.") or BAIL_OUT(perl2dump($untemplate_ret)."no, above is what was returned.");
	}

	for my $ak ('filename', 'filepath', 'basedir'){
		ok(exists($untemplate_ret->{'latex'}->{$ak}), 'untemplate()'." : called for processor '$aprocessorname', and returned result contains key 'latex'->'$ak'.") or BAIL_OUT(perl2dump($untemplate_ret)."no, above is what was returned.");
		is(ref($untemplate_ret->{'latex'}->{$ak}), '', 'untemplate()'." : called for processor '$aprocessorname', and returned result contains key 'latex'->'$ak' and it is a SCALAR.") or BAIL_OUT(perl2dump($untemplate_ret)."no, above is what was returned.");
		ok($untemplate_ret->{'latex'}->{$ak} !~ /^\s*$/, 'untemplate()'." : called for processor '$aprocessorname', and returned result contains key 'latex'->'$ak' and it is a SCALAR and it is not empty.") or BAIL_OUT(perl2dump($untemplate_ret)."no, above is what was returned.");
	}

	ok(-d $untemplate_ret->{'latex'}->{'basedir'}, 'untemplate()'." : called for processor '$aprocessorname', and returned output dir (".$untemplate_ret->{'latex'}->{'basedir'}.") is a dir.") or BAIL_OUT;
	ok(-f $untemplate_ret->{'latex'}->{'filepath'}, 'untemplate()'." : called for processor '$aprocessorname', and returned latex output file (".$untemplate_ret->{'latex'}->{'filepath'}.") is a filepath and it exists.") or BAIL_OUT;
	# open the latex source and check if there any templated vars
	my ($FH, $content);
	ok(open($FH, '<:encoding(utf-8)', $untemplate_ret->{'latex'}->{'filepath'}), "Output latex source '".$untemplate_ret->{'latex'}->{'filepath'}."' opened for reading.") or BAIL_OUT("failed: $!");
	{ local $/ = undef; $content = <$FH> } close $FH;
	ok($content !~ /<\:.+?\:>/, 'untemplate()'." : called for processor '$aprocessorname', and latex source (content of file '".$untemplate_ret->{'latex'}->{'filepath'}."') does not look to contain templated var remains.") or BAIL_OUT($content."\n\nno see above latex source content.");

	my $expected = File::Basename::basename($template_data);
	is($content, $expected, 'untemplate()'." : called for processor '$aprocessorname', and latex source (content of file '".$untemplate_ret->{'latex'}->{'filepath'}."') contains what is expected '${expected}'.") or BAIL_OUT("no it contains '$content'.");

	if( $aprocessorname =~ /on-disk/ ){
		# only for on-disk tests
		# we have an main.tex.expected_output file in the templates dir
		# compare its content with returned
		my $latexsrcf = $untemplate_ret->{'latex'}->{'filepath'};
		ok(-f $latexsrcf, 'untemplate()'." : called for processor '$aprocessorname', compare1 file ($latexsrcf) exists.") or BAIL_OUT;
		ok(-f $expected_latex_output_filename, 'untemplate()'." : called for processor '$aprocessorname', compare2 file ($expected_latex_output_filename) exists.") or BAIL_OUT;
		is(File::Compare::compare($latexsrcf, $expected_latex_output_filename), 0, 'untemplate()'." : called for processor '$aprocessorname', and latex output file ($latexsrcf) is exactly the same as the expected output ($expected_latex_output_filename).") or BAIL_OUT;
	}
}
diag "temp dir: $tmpdir ..." if exists($ENV{'PERL_TEST_TEMPDIR_TINY_NOCLEANUP'}) && $ENV{'PERL_TEST_TEMPDIR_TINY_NOCLEANUP'}>0;

# END
done_testing();

sub myfunc { return "BINGO".$_[0]->{'a'} }
