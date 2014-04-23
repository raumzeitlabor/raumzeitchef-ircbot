package RaumZeitChef::PluginFactory;
# since Moose is so javaish, I figured, we should have a factory *somewhere*

use v5.14;

use Moose;
use MooseX::ClassAttribute;
use RaumZeitChef::Log;

has plugins => (
    traits => ['Hash'],
    is => 'rw',
    # isa => 'ArrayRef[Object]',
    builder => '_build_plugins',
    handles => {
        get_plugin_instance => 'get',
    },
);

class_has Actions => (
    traits => ['Hash'],
    is => 'rw',
    default => sub { {} },
    handles => {
        add_action => 'set',
        get_action => 'get',
        action_pairs => 'kv',
    },
);

class_has BeforeActions => (
    traits => ['Hash'],
    is => 'rw',
    default => sub { {} },
    handles => {
        before_action_pairs => 'kv',
    }
);

no Moose;
no MooseX::ClassAttribute;

sub add_before_action {
    my ($class, $key, $action) = @_;
    push @{ $class->BeforeActions->{$key} ||= [] }, $action;
}

sub build_all_actions {
    my ($self) = @_;

    my %wrapped;
    for my $pair ($self->action_pairs) {
        my ($name, $action) = @$pair;
        my $match = $action->match;
        $wrapped{$name} = [ $match, $self->_build_action_closure($action) ];
    }

    for my $pair ($self->before_action_pairs) {
        my ($name, $actions) = @$pair;
        for my $act (@$actions) {
            # XXX capture where the before_action was defined
            die "couldn't wrap action '$name'" unless my $wrapped = $wrapped{$name};
            my ($match, $orig) = @$wrapped;
            my $before = $self->_build_action_closure($act);
            $wrapped{$name} = [ $match, sub { $before->(@_) or $orig->(@_) } ];
        }
    }

    return [ values %wrapped ];
}

sub _build_action_closure {
    my ($self, $action) = @_;
    my $o = $self->get_plugin_instance($action->plugin_name);
    my $code_ref = $action->body;
    return sub { $o->$code_ref(@_) };
}

sub _build_plugins {
    my ($self) = @_;
    my @plugins = $self->find_plugins;

    my $PLUGIN_SUPER = 'RaumZeitChef::PluginSuperClass';
    my %instances;
    for my $p (@plugins) {
        my $pkg = $p->{package_name};
        my $short_name = $p->{short_name};

        log_debug("loading plugin $short_name");

        Class::Load::load_class($pkg);
        my $o = $instances{$pkg} = $pkg->new;

        log_debug("instantiated $short_name");

        my $attr = lc $p->{short_name};
        $PLUGIN_SUPER->meta->add_class_attribute($attr, is => 'ro', weak_ref => 1);
        $PLUGIN_SUPER->meta->set_class_attribute_value($attr, $o);
    }

    return \%instances;
}

sub find_plugins {
    my ($self) = @_;

    my @prefix = qw/RaumZeitChef Plugin/;
    my $rel_path_dir = join '/', @prefix;

    # get first Plugin directory found via shell globbing
    my ($dir) = glob('{' . join(',', @INC) . "}/$rel_path_dir");
    say $dir;

    my @plugins;
    for my $abs_path (glob "$dir/*.pm") {
        my $name = File::Basename::fileparse($abs_path, '.pm');
        my $pkg = join '::', @prefix, $name;

        push @plugins, { package_name => $pkg, short_name => $name };

    }

    log_debug("found plugins '" . join(', ', map $_->{short_name}, @plugins) . "'");

    return @plugins;
}

1;
