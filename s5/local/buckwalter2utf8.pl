#!/usr/bin/env perl
use strict;
use warnings;
use Carp;

use Encode::Arabic::Buckwalter;         # imports just like 'use Encode' would, plus more

while ( my $line = <>) {
    print encode 'utf8', decode 'buckwalter', $line;
}
