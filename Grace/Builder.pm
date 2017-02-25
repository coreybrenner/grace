package Grace::Builder;

sub setenv ($$$) {
    my ($self, $var, $val) = @_;
    if (! defined($val)) {
        delete($ENV{$var});
    } else {
        $ENV{$var} = $val;
    }
}

sub getenv ($$) {
    my ($self, $var) = @_;
    if (defined($var)) {
        return $ENV{$var};
    } else {
        return %ENV;
    }
}

sub new {
    return bless({});
}

1;

