package Grace::Builder;

sub setenv ($$$) {
    my ($self, $var, $val) = @_;
    if (! defined($val)) {
        delete($ENV{$var});
    } else {
        $ENV{$var} = $val;
    }
    return $self;
}

sub getenv ($$) {
    my ($self, $var) = @_;
    return (defined($var) ? $ENV{$var} : %ENV);
}

sub new {
    return bless({});
}

1;

