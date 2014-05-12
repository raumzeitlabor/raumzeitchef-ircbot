package RaumZeitChef::PluginSuperClass;
use Moose;
use MooseX::ClassAttribute;

has irc => (
    is => 'ro',
    weak_ref => 1,
    handles => [qw/say call_after_joined call_after_oped/]
);

class_has 'config' => (
    is => 'ro',
    handles => [qw/channel nick/],
);

no Moose;
no MooseX::ClassAttribute;

1;
