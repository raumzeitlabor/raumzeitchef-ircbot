package RaumZeitChef::PluginSuperClass;
use Moose;
use MooseX::ClassAttribute;

class_has irc => (is => 'ro', weak_ref => 1);
class_has [qw/channel nick/], is => 'ro';

no Moose;
no MooseX::ClassAttribute;

# XXX uhm, i guess that works, but it's just uber hacky
sub say { goto \&RaumZeitChef::IRC::say }
sub call_after_joined { goto \&RaumZeitChef::IRC::call_after_joined }
sub call_after_oped { goto \&RaumZeitChef::IRC::call_after_oped }

1;
