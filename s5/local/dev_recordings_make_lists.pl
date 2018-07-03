#!/usr/bin/env perl

# Copyright 2018 John Morgan
# Apache 2.0.

# dev_recordings_make_lists.pl - make acoustic model training lists

use strict;
use warnings;
use Carp;

use File::Spec;
use File::Copy;
use File::Basename;

BEGIN {
    @ARGV == 3 or croak "USAGE $0 <TRANSCRIPT_FILENAME> <SPEAKER_NAME> <COUNTRY>
example:
$0 /mnt/disk01/Libyan_MSA_ARL/adel/data/transcripts/recordings/adel_recordings.tsv adel libyan
";
}

my ($tr,$spk,$l) = @ARGV;

open my $I, '<', $tr or croak "problems with $tr";

my $tmp_dir = "data/local/tmp/$l/recordings/$spk";

# input wav file list
my $w = "$tmp_dir/wav.txt";
croak "$!" unless ( -f $w );
# output temporary wav.scp files
my $o = "$tmp_dir/wav.scp";

# output temporary utt2spk files
my $u = "$tmp_dir/utt2spk";

# output temporary text files
my $t = "$tmp_dir/text";

# initialize hash for prompts
my %p = ();

# store prompts in hash
LINEA: while ( my $line = <$I> ) {
    chomp $line;
    my ($s,$sent) = split /\t/, $line, 2;

    $p{$s} = $sent;
}

open my $W, '<', $w or croak "problem with $w $!";
open my $O, '+>', $o or croak "problem with $o $!";
open my $U, '+>', $u or croak "problem with $u $!";
open my $T, '+>', $t or croak "problem with $t $!";

 LINE: while ( my $line = <$W> ) {
     chomp $line;
     next LINE if ($line =~ /answers/ );
     next LINE unless ( $line =~ /recordings/ );
     my ($volume,$directories,$file) = File::Spec->splitpath( $line );
     my @dirs = split /\//, $directories;
     my $b = basename $line, ".wav";
     my $s = $dirs[-1];
     my ($spk,$m,$uttid) = split /\_/, $b, 3;

     if ( exists $p{$b} ) {
	 print $T "$spk\t$p{$b}\n";
     } elsif ( defined $s ) {
	 warn  "problem\t$s";
	 next LINE;
     } else {
	 croak "$line";
     }

     print $O "$spk sox $line -t wav - |\n";
	print $U "$b\t$spk\n";
}
close $T;
close $O;
close $U;
close $W;
