package Grace::Config;

use strict;
use warnings;

use Clone         qw{clone};
use Data::Dumper;

use parent 'Grace::Object';

sub merge_data (@) {
    my (@more) = @_;

    sub _merge_list ($$);
    sub _merge_hash ($$);

    our @errs;
    our %funs = (
        UNDEF  => {
            ARRAY  => sub { _merge_list([], $_[1])        },
            HASH   => sub { _merge_hash({}, $_[1])        },
        },
        ''     => {
            ARRAY  => sub { _merge_list([ $_[0] ], $_[1]) },
            HASH   => sub { _merge_hash({}, $_[1])        },
        },
        ARRAY  => {
            ''     => sub { _merge_list($_[0], [ $_[1] ]) },
            ARRAY  => sub { _merge_list($_[0], $_[1])     },
            HASH   => sub { _merge_hash({}, $_[1])        },
        },
        HASH   => {
            ARRAY  => sub { _merge_list([], $_[1])        },
            HASH   => sub { _merge_hash($_[0], $_[1])     },
        },
    );

    sub _merge_list ($$) {
        my ($into, $list) = @_;

        foreach my $more (@{$list}) {
            my $type = (ref($more) || '');
            if (defined(my $func = $funs{UNDEF}{$type})) {
                $more = &{$func}(undef, $more);
            } else {
                $more = clone($more);
            }
            push(@{$into}, $more);
        }

        return $into;
    }

    sub _merge_hash ($$) {
        my ($into, $hash) = @_;

        my $orig;
        my $orig_type;
        my $more_type;
        my $func;

        while (my ($name, $more) = each(%{$hash})) {
            $orig      = $into->{$name};
            $orig_type = (defined($orig) ? (ref($orig) || '') : 'UNDEF');
            $more_type = (defined($more) ? (ref($more) || '') : 'UNDEF');
            if (defined($func = $funs{$orig_type}{$more_type})) {
                $into->{$name} = &{$func}($orig, $more);
            } else {
                $into->{$name} = clone($more);
            }
        }

        return $into;
    }

    my $data = {};
    my $data_type;
    my $more;
    my $more_type;
    my $from;
    my $func;

    foreach $more (@more) {
        $data_type = (defined($data) ? (ref($data) || '') : 'UNDEF');
        $more_type = (defined($more) ? (ref($more) || '') : 'UNDEF');

        if (defined($func = $funs{$data_type}{$more_type})) {
            $data = &{$func}($data, $more);
        } else {
            $data = clone($more);
        }
    }

    return $data;
}

sub merge_file (@) {
    my $conf = ((ref($_[-1]) eq 'HASH') ? pop(@_) : undef);
    my @file = @_;

    my  @errs;
    my  $data;

    our $bldr = ($conf && $conf->{builder});
    our %envp = ($bldr ? $bldr->getenv() : %ENV);
    my  $file;
    my  @data;

    sub BUILDER () {
        return $bldr;
    }

    { # scope for local %ENV
        local %ENV = %envp;

        foreach $file (@file) {
            if (! defined($data = do $file)) {
                push(@errs, "File '$file': " . ($@ || $!));
            } else {
                push(@data, $data);
            }
        }

        if ($bldr && $conf->{builder_write_env}) {
            $bldr->setenv(\%ENV);
        }
    }

    return (\@data, \@errs);
}

sub new {
    my ($what, $bldr, @file) = @_;

    my $type = (ref($what) || $what);
    my $prnt = (ref($what) && $what);
    my $self = $type->SUPER::new($bldr);
    my $fail = 0;

    if ($prnt) {
        unshift(@file, @{$prnt->{_file_}});
    }

    my ($data, $errs) = merge_file(@file);

    if (! @{$errs}) {
        $data = merge_data(@{$data});

        if (! @{$errs}) {
            $self->{_data_} = $data;
        }
    }

    $self->error(@{$errs});

    return $self;
}

# Dummy function.  Override in derived classes.
sub files ($) {
    my $self = shift;
    return ( @{$self->{_file_}} );
}

sub data ($) {
    my $self = shift;
    return $self->{_data_};
}

1;
