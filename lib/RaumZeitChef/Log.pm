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
    my $sub = sprintf << 'EOC', __LINE__ + 1, __FILE__, $sub_name, $level;
#line %d %s
        sub %s {
            my $meta = shift;

            my @lines;
            push @lines, split /\n/, $_ for @_;

            my $prefix = $meta->name;
            $prefix =~ s/^RaumZeitChef:://;
            $prefix .= ': ';
            my $indent = ' ' x length $prefix;

            $lines[0] = $prefix . $lines[0];
            for my $line (@lines[1 .. $#lines]) {
                $line = $indent . $line;
            }

            my $msg = join "\n", @lines;
            $msg .= "\n";
            $LOG->log(level => "%s", message => $msg);
        }
EOC
    local $@;
    eval $sub;
    die $@ if $@;
}


1;
