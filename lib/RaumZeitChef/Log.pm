package RaumZeitChef::Log;
use v5.14;
use strict;
use warnings;

use Sys::Syslog ':macros';

our @EXPORT;

BEGIN {
    my @LEVELS = qw/EMERG ALERT CRIT ERR WARNING NOTICE INFO DEBUG/;
    for my $level (@LEVELS) {
        my $sub_name = 'log_' . lc $level;
        my $numeric = do { no strict 'refs'; &{"LOG_$level"} };
        eval qq/sub $sub_name { say "<$numeric> \@_" }/;
        push @EXPORT, $sub_name;
    }
}

use Exporter 'import';

1;
