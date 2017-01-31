package Grace::Object;

use strict;
use warnings;

my %_objname;

sub new {
    my $type = shift;
    my $name = $type . '::' . ++$_objname{$type};

    my %self = (
        _type_ => $type,
        _name_ => $name,
        _errs_ => [],
        _warn_ => [],
    );

    return bless(\%self, $type);
}

sub type {
    my $self = shift;
    return $self->{_type_};
}

sub setname {
    my $self = shift;
    my $name = shift;
    return ($self->{_name_} = $name);
}

sub name {
    my $self = shift;
    return $self->{_name_};
}

sub error {
    my $self = shift;
    push(@{$self->{_errs_}}, @_);
    return $self;
}

sub errors {
    my $self = shift;
    return @{$self->{_errs_}};
}

sub warning {
    my $self = shift;
    push(@{$self->{_warn_}}, @_);
    return $self;
}

sub warnings {
    my $self = shift;
    return @{$self->{_warn_}};
}

1;
