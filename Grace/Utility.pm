package Grace::Utility;

use strict;
use warnings;

BEGIN {
    use Exporter     qw{import};
    our @EXPORT_OK = qw{unique printdef slice construct};
}

use Data::Dumper;
use Storable;
use Scalar::Util;

sub unique (@) {
    my %seen;
    grep { ! $seen{$_}++ } @_;
}

sub printdef ($) {
    return (defined($_[0]) ? "'$_[0]'" : '<undef>');
}

sub slice ($$@) {
    my ($beg, $cnt, @arr) = @_;

    my $rev = 0;

    # Negative count reverses stacking order in returned array.
    if ($cnt < 0) {
        $rev = 1;
        $cnt = -$cnt;
    }

    # Check the range of indices requested against the array.  If we go
    # completely off the ends of the given array, return an empty array.
    if ((($beg < 0) && (-$beg > (@arr + $cnt))) || ($beg >= @arr)) {
        return ();
    }

    # Adjust the element count based on where the slice begins.
    if ($beg < 0) {
        # A negative start index indexes from the back of the array.
        # Adding the array length to the index gives us the start index.
        # If this number still ends up negative, we've gone off the
        # beginning of the array.  The number of elements to pull in
        # from the beginning of the array is the number of elements
        # that wind up in the slice range.  The range check above makes
        # sure we actually need to do something here.
        $beg += @arr;
        if ($beg < 0) {
            $cnt += $beg;
            $beg  = 0;
        }
    }
    # Adjust the element count down if the slice goes off the back end.
    if (($beg + $cnt) > @arr) {
        $cnt = (@arr - $cnt);
    }

    splice(@arr, $beg, $cnt);
}

sub flatten (@) {
    my @ilist = @_;
    my @olist;

    while (@ilist) {
        my $data = pop(@ilist);
        if (ref($data) ne 'ARRAY') {
            push(@olist, $data);
        } else {
            unshift(@ilist, @{$data});
        }
    }

    return @olist;
}

1;
