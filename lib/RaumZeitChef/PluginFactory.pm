package RaumZeitChef::PluginFactory;
# since Moose is so javaish, I figured, we should have a factory *somewhere*

use v5.14;

use MooseX::Singleton;
use RaumZeitChef::Log;

has config => (
    is => 'ro',
    required => 1,
);

has irc => (
    is => 'ro',
    required => 1,
    weak_ref => 1,
);

has plugins => (
    traits => ['Hash'],
    is => 'rw',
    isa => 'HashRef[Object]',
    handles => {
        get_plugin_instance => 'get',
        add_plugin_instance => 'set',
    },
);

around 'get_plugin_instance' => sub {
    my ($orig, $self, $key) = @_;

    my $value = $self->$orig($key);
    return $value if $value;

    log_error("requested plugin instance for '$key' which isn't instantiated");
    exit -1;
};

has events => (
    is => 'rw',
    traits => ['Array'],
    default => sub { [] },
    handles => {
        'add_irc_event' => 'push',
    },
);

has Actions => (
    traits => ['Hash'],
    is => 'rw',
    default => sub { {} },
    handles => {
        add_action => 'set',
        get_action => 'get',
        action_pairs => 'kv',
    },
);

has BeforeActions => (
    traits => ['Hash'],
    is => 'rw',
    default => sub { {} },
    handles => {
        before_action_pairs => 'kv',
    }
);

no MooseX::Singleton;

my $PLUGIN_SUPER = 'RaumZeitChef::PluginSuperClass';

sub BUILD {
    my ($self) = @_;

    $PLUGIN_SUPER->meta->set_class_attribute_value(config => $self->config);
}

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

    return values %wrapped;
}

sub _build_action_closure {
    my ($self, $action) = @_;
    my $o = $self->get_plugin_instance($action->plugin_name);
    my $code_ref = $action->body;
    return sub { $o->$code_ref(@_) };
}

sub build_all_events {
    my ($self) = @_;

    my $events = $self->events;
    my @wrapped;
    for my $event (@$events) {
        my $name = $event->name;
        my $sub = $event->body;
        my $plugin = $event->plugin_name;

        my $obj = $self->get_plugin_instance($plugin);

        push @wrapped, [
            $name,
            sub {
                shift; # don't leak AnyEvent::IRC::Client object
                $obj->$sub(@_);
            }
        ];
    }

    return @wrapped;
}

sub build_plugins {
    my ($self) = @_;
    my @plugins = $self->find_plugins;

    my @instances;
    for my $p (@plugins) {
        my $pkg = $p->{package_name};
        my $short_name = $p->{short_name};

        log_debug("loading plugin $short_name");

        Class::Load::load_class($pkg);
        my $o = $pkg->new(irc => $self->irc);

        $self->add_plugin_instance($pkg => $o);
        push @instances, $o;

        log_debug("instantiated $short_name");

        my $attr = lc $p->{short_name};
        $PLUGIN_SUPER->meta->add_class_attribute(
            $attr,
            is => 'ro',
            weak_ref => 1,
        );
        $PLUGIN_SUPER->meta->set_class_attribute_value($attr, $o);
    }

    $_->can('init_plugin') and $_->init_plugin for @instances;
    return;
}

sub find_plugins {
    my ($self) = @_;

    my @prefix = qw/RaumZeitChef Plugin/;
    my $rel_path_dir = join '/', @prefix;

    # get first Plugin directory found via shell globbing
    my ($dir) = grep { -d $_ } glob('{' . join(',', @INC) . "}/$rel_path_dir");
    log_debug("using Plugin directory $dir");

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
