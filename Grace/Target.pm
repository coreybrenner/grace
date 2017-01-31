package Grace::Target;

use strict;
use warnings;

use Clone qw{clone};

use Grace::Builder;

sub new {
    my $func = __PACKAGE__ . '->new()';

    my ($what, $name, $conf) = @_;

    my $type = (ref($what) || $what)
    my $prnt = (ref($what) && $what)
    my $self;
    my $bldr;

    $conf = ($conf || {});

    if ($prnt) {
        $self = {
            %{clone($prnt)},
            knownas => $name,
            %{$conf}
        };
    } else {
        $self = {
            objtype => $type,
            attribs => {},
            knownas => $name,
            depends => {},
            clients => {},
            sources => {},
            outputs => {},
            variant => {},
            %{$conf},
        };
    }

    return bless($self, $type);
}

sub variant {
}

sub outputs {
    my $self = shift;
    return keys(%{$self->{outputs}})
}

sub sources {
    my $self = shift;
    return keys(%{$self->{sources}});
}

sub depends {
    my $self = shift;
    return keys(%{$self->{depends}});
}

sub clients {
    my $self = shift;
    return keys(%{$self->{clients}});
}

sub getattr {
    my ($self, $name) = @_;

    my $aref = $self->{attribs}->{$name};

    return ($aref ? @{$aref} : ())
}

sub hasattr {
    my ($self, $name) = @_;

    return defined($self->{attribs}->{$name});
}

sub setattr {
    my ($self, $name, @vals) = @_;

    $self->{attribs}->{$name} = \@vals;

    if (wantarray) {
        return @{$self->{attribs}->{$name}};
    } else {
        return $self;
    }
}

sub addattr {
    my ($self, $name, @vals) = @_;

    push(@{$self->{attribs}->{$name}}, @vals);

    if (wantarray) {
        return @{$self->{attribs}->{$name}};
    } else {
        return $self;
    }
}

1;
