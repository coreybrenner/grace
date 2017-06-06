package Grace::Builder;

use parent 'Grace::Object';

use Scalar::Util qw{weaken};

use Grace::Config;

sub new {
    my $what = shift;

    my $type = (ref($what) || $what);
    my $prnt = (ref($what) && $what);
    
    my $self = $type->SUPER::new();

    $self->{_tgts_} = [];
    $self->{_bldr_} = ($prnt ? $prnt->builder() : $self);

    weaken($self->{_bldr_});
}

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

1;

