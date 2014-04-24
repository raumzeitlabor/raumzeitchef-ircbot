package RaumZeitChef::Log;
use v5.14;
use strict;
use warnings;

use Log::Dispatch;
use Log::Dispatch::Syslog ();
use Moose::Exporter;

my $log_output = [ 'Syslog', min_level => 'debug', facility => 'daemon' ];

# STDIN is a terminal, we are developing, don't send to syslog
if (-t STDIN) {
    $log_output = [ 'Screen', min_level => 'debug' ];
}

our $LOG = Log::Dispatch->new(outputs => [ $log_output ]);

my @levels = qw/debug info notice warning error critical alert emergency/;
my @exports;
for my $level (@levels) {
    my $sub_name = "log_$level";
    _mk_log_function($sub_name, $level);
    push @exports, $sub_name;
}

Moose::Exporter->setup_import_methods(
    with_meta => [@exports],
);

sub _mk_log_function {
    my ($sub_name, $level) = @_;
    my $sub = sprintf << 'EOC', $sub_name, $level;
        sub %s {
            my $meta = shift;
            # append a newline, if it isn't there
            # XXX there has to be a nicer way to do this
            chomp(my $msg = "@_");
            $msg .= "\n";

            $LOG->log(level => "%s", message => $msg);
        }
EOC
    eval $sub;
}


1;
