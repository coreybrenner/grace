package Grace::LogEntry;

use strict;
use warnings;

sub new {
    my ($what, %attr) = @_;

    my $type = (ref($what) || $what);

    my %self = (
        object => $attr{object},
        stream => $attr{stream},
        offset => $attr{offset},
        length => $attr{length},
    );

    return bless(\%self, $type);
}

1;
