package RaumZeitLabor::IRC::Chef::Commands::Erinner;
use strict; use warnings;
use v5.10;

# core modules
use Sys::Syslog;
use POSIX qw(strftime);

# not in core
use AnyEvent::HTTP;

# pizza timer
my $pizza_timer_user;
my $pizza_timer_subject;
my $pizza_timer_minutes;
my $pizza_timer = undef;
my $pizza_disable_timer = undef; # timer used for disabling ping+

my @answers = ("Alles klar.", "Yup.", "Okidoki.", "Eyup.", "Roger.");

# timer ohne ping+ (irc-only)
RaumZeitLabor::IRC::Chef::Commands->add_command(erinner => sub {
    my ($conn, $channel, $ircmsg, $cmd, $rest) = @_;

    return unless $rest =~ /^(.+) an (.+) in (\d{1,2}) ?(h|m|s)/;
    my $reminder_target = $1;
    if ($reminder_target eq 'mich') {
        $reminder_target = AnyEvent::IRC::Util::prefix_nick($ircmsg->{prefix});
    }
    my $reminder_subject = $2;
    my $reminder_timeout = $3;
    $reminder_timeout *= 60 if ($4 eq 'm');
    $reminder_timeout *= 3600 if ($4 eq 'h');
    my $time = strftime("%H:%M", localtime(time()));
    my $reminder;
    $reminder = AnyEvent->timer(after => $reminder_timeout, cb => sub {
        $conn->send_chan($channel, 'PRIVMSG', ($channel, "Reminder für $reminder_target: $reminder_subject ($time Uhr)"));
        undef $reminder;
    });
    $conn->send_chan($channel, 'PRIVMSG', ($channel, $answers[rand @answers]));

});

RaumZeitLabor::IRC::Chef::Commands->add_command(timer => \&timer);
RaumZeitLabor::IRC::Chef::Commands->add_command(pizza => \&timer);
# timer mit ping+ (auf 1 user begrenzt)
sub timer {
    my ($conn, $channel, $ircmsg, $cmd, $rest) = @_;

    if ($cmd eq 'timer' and $rest eq 'cancel') {
        if (!$pizza_timer) {
            $conn->send_chan($channel, 'PRIVMSG', ($channel, "Es läuft momentan kein Timer."));
            return;
        }

        my $msguser = AnyEvent::IRC::Util::prefix_nick($ircmsg->{prefix});
        if ($pizza_timer_user eq $msguser) {
            undef $pizza_timer;
            $conn->send_chan($channel, 'PRIVMSG', ($channel,
                    "Dein Timer \"$pizza_timer_subject\", $pizza_timer_minutes Minuten "
                    ."wurde deaktiviert."));
            return;
        }

        $conn->send_chan($channel, 'PRIVMSG', ($channel,
                "Der Timer \"$pizza_timer_subject\", $pizza_timer_minutes Minuten "
                ."kann nur von $pizza_timer_user deaktiviert werden."));
        return;
    }

    if ($pizza_timer) {
        $conn->send_chan($channel, 'PRIVMSG', ($channel,
                "Es läuft bereits ein Timer von $pizza_timer_user "
                ."(\"$pizza_timer_subject\", $pizza_timer_minutes Minuten)."));
        return;
    }

    return unless $cmd eq 'pizza';

    $pizza_timer_minutes = 15;
    $pizza_timer_subject = 'Pizza';

    $pizza_timer_user = AnyEvent::IRC::Util::prefix_nick($ircmsg->{prefix});

    # !timer stuff
    # if ($pizza_timer_minutes * 60 < $ping_freq) {
    #     $conn->send_chan($channel, 'PRIVMSG', ($channel, "Das Timeout ist zu klein."));
    #     return;
    # }
    # if ($pizza_timer_minutes > 30) {
    #     $conn->send_chan($channel, 'PRIVMSG', ($channel, "Das Timeout ist zu groß."));
    #     return;
    # }

    $conn->send_chan($channel, 'PRIVMSG', ($channel, $answers[rand @answers]));

    my ($post, $epost);
    $pizza_timer = AnyEvent->timer(after => $pizza_timer_minutes * 60, cb => sub {
        $conn->send_chan($channel, 'PRIVMSG', ($channel,
            "( ・∀・)っ♨ $pizza_timer_user, deine Pizza ist fertig."));

        $pizza_disable_timer = AnyEvent->timer(after => 5, cb => sub {
            my $post;
            my $epost;
            $post = http_post 'http://172.22.36.1:5000/port/8', '0', sub {
                say "Port 8 am NPM deaktiviert!";
                undef $post;
                $epost = http_post 'http://172.22.36.1:5000/port/3', '0', sub {
                    say "Port 3 am NPM deaktiviert!";
                    undef $epost;
                };
            };
        });

        undef $pizza_timer;

        syslog('info', '!timer executed');
    });

}


1;
# vim: set ts=4 sw=4 sts=4 expandtab: 
