package Grace::Variant;

sub add_variant ($$$) {
}

sub get_variant ($$$) {
}

sub new {
    my ($what, $conf) = @_;

    my $self = {
        _vmgr_ = $conf->get_variant();
    }
}

1;
