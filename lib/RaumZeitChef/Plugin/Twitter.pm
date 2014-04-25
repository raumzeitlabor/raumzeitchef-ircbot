package RaumZeitChef::Plugin::Twitter;
use v5.14;
use utf8;
use RaumZeitChef::Plugin;

use AnyEvent::HTTP;
use HTTP::Status qw/status_message/;

use JSON::XS;
use HTML::TreeBuilder;

my $rx_tweet_id = qr#^https?://(?:[a-z]+\.)?twitter\.com/[a-z0-9_]+/status/(?<id>[0-9]+)#i;

before_action 'linkinfo' => sub {
    my ($self, $ircmsg, $match) = @_;
    return unless $match->{url} =~ /$rx_tweet_id/;
    my $id = $+{id};
    log_info("fetching tweet with id '$id'");

    $self->http_get_tweet_html($id, sub {
        my ($html) = @_;
        my $tweet = extract_tweet($html, $id);
        log_info("got tweet '$tweet'");
        $self->say($tweet);
    });

    return 1;
};

# find our tweet in a potential existing conversation
# <blockquote data-tweet-id=$id …>
sub lookup_tweet {
    my ($tree, $id) = @_;
    return $tree->look_down(_tag => 'blockquote', 'data-tweet-id' => $id);
}

# extract an fullsize image URL, if avaiable
# <img class='autosized-media' data-src-2x=$url …>
sub lookup_image_url {
    my ($tree) = @_;
    my $img = $tree->look_down(_tag => 'img', class => 'autosized-media')
        or return;
    return $img->attr('data-src-2x');
}

# ~140 chars of "information" are buried in
# <p class='e-entry-title' …>
sub lookup_tweet_text {
    my ($tree) = @_;
    my $content = $tree->look_down(_tag => 'p', class => 'e-entry-title')
        or return;
    return $content->as_trimmed_text;
}

sub lookup_nickname {
    my ($tree) = @_;
    my $nick = $tree->look_down(_tag => 'span', class => 'p-nickname');
    return $nick->as_trimmed_text;
}

# https://api.twitter.com/1/statuses/oembed.json
sub http_get_tweet_html {
    my ($self, $id, $callback) = @_;
    my $tweets_json = "https://syndication.twitter.com/tweets.json?ids=$id&lang=en";

    http_get $tweets_json, timeout => 10, sub {
        my ($data, $header) = @_;

        if ($header->{Status} !~ /^2/) {
            $self->say("twitter: $header->{Status} $header->{Reason}");
            return;
        }
        if ($header->{Status} =~ /^59/) {
            # internal error
            return;
        }

        # tweets.json returns HTML wrapped in JSON keyed by $id
        my $wrapped_html = decode_json($data);
        my $html = $wrapped_html->{$id};
        if ($html) {
            $callback->($html);
        }
        else {
            log_error("Couldn't find $id in JSON");
        }
    };

    return;

}

sub extract_tweet {
    my ($html, $id) = @_;
    my $root = HTML::TreeBuilder->new_from_content($html)
        or die "couldn't parse HTML: $!";

    # Our tweet might be buried in a conversation, find it by id first
    my $tweet = lookup_tweet($root, $id)
        or die "$id not found in HTML";

    my $text = lookup_tweet_text($tweet)
        or die 'could not find text in tweet';

    if (my $img_url = lookup_image_url($tweet)) {
        $text .= " $img_url";
    }

    my $nick = lookup_nickname($root);
    return "<$nick> $text";
}


1;
# vim: set ts=4 sw=4 sts=4 expandtab: 
