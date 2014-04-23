package RaumZeitChef::PluginSuperClass;
use Moose;
use MooseX::ClassAttribute;

class_has irc => (is => 'ro', weak_ref => 1);
class_has [qw/channel nick/], is => 'ro';

no Moose;
no MooseX::ClassAttribute;

sub say {
    my ($self, $msg) = @_;
    $self->irc->send_long_message('utf8', 0, 'PRIVMSG', $self->channel, $msg);
}

1;
