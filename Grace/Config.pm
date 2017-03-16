package Grace::Config;

use strict;
use warnings;

use Clone         qw{clone};
use Data::Dumper;

use parent 'Grace::Object';

my %_rawfile;
my %_stacked;
my %_compile;

sub merge_data (@) {
    my (@more) = @_;

    sub _merge_list ($$);
    sub _merge_hash ($$);

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

    my $data;
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
    my  @errs;
    my  @warn;
    my  $data;

    my $join = join('|', @_);
    if (defined($data = $_stacked{$join})) {
        return $data;
    }

    my $file;
    my @data;
    foreach $file (@_) {
        if (! defined($data = $_rawfile{$file})) {
            if (defined($data = eval { do $file })) {
                push(@data, ($_rawfile{$file} = $data));
            } else {
                push(@errs, $@);
            }
        }
        $data = merge_data(@data);
    }

    if (! @errs) {
        $_stacked{$join} = $data;
    }

    return ($data, \@errs, \@warn);
}

sub new {
    my ($what, @file) = @_;

    my $type = (ref($what) || $what);
    my $prnt = (ref($what) && $what);
    my $self = $type->SUPER::new();
    my $fail = 0;

    my ($data, $errs, $warn);

    if ($prnt) {
        unshift(@file, @{$prnt->{_file_}});
    }

    $self->{_file_} = \@file;

    ($data, $errs, $warn) = $type->merge_file(@file);

    $self->warning(@{$warn});
    $self->error(@{$errs});

    if (! @{$errs}) {
        $self->{_data_} = $data;
    }

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
