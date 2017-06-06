package Grace::Object;

use strict;
use warnings;

my %_objname;

sub new {
    my ($type, $bldr) = @_;

    my $name = $type . '@' . ++$_objname{$type};

    my %self = (
        _type_ => $type,
        _name_ => $name,
        _bldr_ => $bldr,
        _errs_ => [],
        _warn_ => [],
    );

    return bless(\%self, $type);
}

sub type {
    my $self = shift;
    return $self->{_type_};
}

#sub setname {
#    my $self = shift;
#    my $name = shift;
#    return ($self->{_name_} = $name);
#}

sub object_name {
    my $self = shift;
    return $self->{_name_};
}

sub error {
    my $self = shift;
    push(@{$self->{_errs_}}, @_);
    # Propagate errors up the chain to the highest builder.
    if ($self->{_bldr_} && ($self->{_bldr_} != $self)) {
        $self->{_bldr_}->error(@_);
    }
    return $self;
}

sub errors {
    my $self = shift;
    return @{$self->{_errs_}};
}

sub warning {
    my $self = shift;
    push(@{$self->{_warn_}}, @_);
    # Propagate warnings up the chain to the highest builder.
    if ($self->{_bldr_} && ($self->{_bldr_} != $self)) {
        $self->{_bldr_}->warning(@_);
    }
    return $self;
}

sub warnings {
    my $self = shift;
    return @{$self->{_warn_}};
}

sub builder {
    my $self = shift;
    return $self->{_bldr_};
}

1;
