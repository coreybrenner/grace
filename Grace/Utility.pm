package Grace::Utility;

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

# Make a copy of the base type's %_dflt.
sub construct (@) {
    my (@hash) = @_;
    my  %copy;
    my  @errs;
    my  $weak;

    foreach my $hash (@hash) {
print(STDERR "HASH: " . (defined($hash) ? $hash : '<undef>') . "\n");
        while (my ($key, $val) = each(%{$hash})) {
print(STDERR "KEY: '$key', VAL: '" . Dumper($val) . "'\n");
            $weak = 0;

            if ($key =~ m{^:([^:]+):$}o) {
print(STDERR "KEY '$key' -> $1: Storable::dclone($val)\n");
                $copy{$1} = Storable::dclone($val);
print(STDERR Dumper($copy{$1}) . "\n");
            } elsif ($key =~ m{^\?([^?]+)\?$}o) {
print(STDERR "KEY '$key' -> $1: =\n");
                $copy{$1} = $val;
print(STDERR "WEAKEN: $copy{$1}\n");
                Scalar::Util::weaken($copy{$1});
                $weak = 1;
            } elsif ($key =~ m{^_(.*)_$}o) {
                $copy{$1} = (! ref($val)
                             ? $val
                             : ((ref($val) eq 'ARRAY') ? \@{$val} : \%{$val}));
print(STDERR "KEY '$key' -> ?=: $copy{$1}\n");
            } else {
                push(@errs, "Invalid key '$key'");
                next;
            }

            $key = $1;

            foreach (@over) {
                next if (! defined($_->{$key}));

                my ($cur, $new) = (ref($copy{$key}), ref($_->{$key}));

                if ((! $cur &&   $new)
                || (  $cur && ! $new)
                || ($cur && ($cur ne $new)))
                {
                    push(@errs, "Data type mismatch for '$key'");
                } elsif ($cur && ($cur ne 'ARRAY') && ($cur ne 'HASH')) {
                    $copy{$key} = $_->{$key};
                    if ($weak) {
                        Scalar::Util::weaken($copy{$key});
                    }
                } elsif ($cur && ($cur eq 'ARRAY')) {
                    $copy{$key} = [ @{$_->{$key}} ];
                } else {
                    $copy{$key} = { %{$_->{$key}} };
                }
            }
        }
    }

    return (\%copy, \@errs);
}

1;
