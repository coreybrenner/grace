package Grace::Builder;

use strict;
use warnings;

use parent 'Grace::Overlay';

use Scalar::Util qw{weaken};

use Grace::Config;

sub new {
    my ($what, %attr) = @_;
    
    my $self = $what->SUPER::new(%attr);
    my $prnt = (ref($what) && $what);

    if ($self->{_prnt_} = $prnt) {
        weaken($self->{_prnt_});
        $prnt->{_kids_}->{$self->object_name()} = $self;
    }

    if (! $self->{_bldr_}) {
        $self->{_bldr_} = $self;
        weaken($self->{_bldr_});
    }

    $self->{_attr_} = {
        %{ ($prnt ? $prnt->{_attr_} : { }) },
        %attr,
    };

    $self->{_tgts_} = [];

    return $self;
}

our $generic = __PACKAGE__->new();

sub setenv {
    my $what = shift;

    if (@_) {
        my $hash = $_[0];
        if (ref($hash) ne 'HASH') {
            $hash = { $_[0] => $_[1] }
        }
        while (my ($var, $val) = each(%{$hash})) {
            if (defined($val)) {
                $ENV{$var} = $val;
            } else {
                delete($ENV{$var});
            }
        }
    }

    return $self;
}

sub getenv {
    my $what = shift;

    if (! @_) {
        return %ENV;
    } elsif (@_ == 1) {
        return $ENV{$_[0]};
    } else {
        my %hash;
        map { defined($ENV{$_}) && ($hash{$_} = $ENV{$_}) } @_;
        return %hash;
    }
}

sub target {
    my $self = shift;
    my @args = @_;
    my %name;
    my %data;
    my %targ;

    while (@args) {
        my $what = shift;
        if (! ref($what)) {
            $name{$what} = 1;
        } elsif (ref($what) eq 'ARRAY') {
            unshift(@args, @{$what});
        } elsif (ref($what) eq 'HASH') {
            %data = %{ Grace::Config::merge_data(\%data, $what) };
        } elsif ($what->isa('Grace::Target')) {
            $targ{$what} = $what;
        }
    }
}

sub get {
}

1;

