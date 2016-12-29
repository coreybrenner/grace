use strict;
use warnings;

package Grace::Util;

BEGIN {
    our @EXPORT = qw{uniq};
    use Exporter qw{import};
}

sub uniq (@) {
    my %seen;
    grep { ! $seen{$_}++ } @_;
}

1;
