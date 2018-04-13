#!/usr/bin/env perl
#utf82buckwalter.pl - Convert Arabic in UTF8 to Buckwalter
use strict;
use warnings;
use Carp;

use Encode::Arabic::Buckwalter;

while ( my $line = <>) {
    print encode 'buckwalter', decode 'utf8', $line;
}
