#
# Allow config files to calculate values dynamically by way of auto-evaluation
# of CODE chunks encountered when obtaining data from the hash.
#
# Still naive.  Can't handle recursive data structures.
#
package Grace::ActiveConfig::Hash;

use strict;
use warnings;

require Tie::Hash;

our @ISA = qw{Tie::StdHash};

sub TIEHASH {
    sub _tie_hash ($$);
    sub _tie_list ($$);

    sub _tie_list ($$) {
        my $type = shift;
        my $list = shift;
        my $data;
        my @done;

        foreach $data (@{$list}) {
            if (! ref($data)
             || ((ref($data) ne 'ARRAY') &&  (ref($data) ne 'HASH')))
            {
                push(@done, $data);
            } elsif (ref($data) eq 'ARRAY') {
                push(@done, _tie_list($type, $data));
            } else {
                my %hash;
                tie(%hash, $type, $data);
                push(@done, bless(\%hash, $type));
            }
        }

        return \@done;
    }

    sub _tie_hash ($$) {
        my $type = shift;
        my $hash = shift;
        my $name;
        my $data;
        my %done;

        foreach $name (keys(%{$hash})) {
            $data = $hash->{$name};
            if (! ref($data) || (ref($data) eq 'SCALAR')) {
                $done{$name} = $data;
            } elsif (ref($data) eq 'ARRAY') {
                $done{$name} = _tie_list($type, $data);
            } elsif (ref($data) eq 'HASH') {
                my %hash;
                tie(%hash, $type, $data);
                $done{$name} = bless(\%hash, $type);
            }
        }

        return bless(\%done, $type);
    }

    return _tie_hash($_[0], $_[1]);
}

sub FETCH {
    my $val = $_[0]->SUPER::FETCH($_[1]);
    ((ref($val) eq 'CODE') ? &{$val}($_[0]->{_bldr_}) : $val);
}

sub STORE {
    # Read only.
}

package Grace::ActiveConfig;

sub activate ($) {
    my $data = shift;

    my %data;

    tie(%data, __PACKAGE__.'::Hash', $data);

    return \%data;
}

1;

