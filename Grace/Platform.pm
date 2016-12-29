use strict;
use warnings;

package Grace::Platform;

use Clone qw{clone};

sub new {
    my  $what = shift;
    our $conf = shift;
    our $self;

    my $type = (ref($what) || $what);
    my $prnt = (ref($what) && $what);

    if (defined($prnt)) {
        $self = clone($prnt);
    } else {
        $self = { };
    }

    sub replace ($) {
        if ($conf->{$_[0]}) {
            $self->{$_[0]} = clone($conf->{$_[0]});
        }
        return $self->{$_[0]};
    }
    if (defined($conf)) {
        replace('sysname');
        replace('sysarch');
        replace('sysconf');
    }
}

1;
