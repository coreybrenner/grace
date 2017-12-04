package Grace::Config;

use strict;
use warnings;

use parent 'Grace::Object';

use Clone  qw{clone};

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
    my @errs;
    my @data;

    foreach my $file (@_) {
        my $data;
        if (! defined($data = do $file)) {
            push(@errs, "File '$file': " . ($@ || $!));
        } else {
            push(@data, $data);
        }
    }

    return (\@data, \@errs);
}

sub new {
    my ($what, %attr) = @_;

    my  $type = (ref($what) || $what);
    my  $prnt = (ref($what) && $what);
    my  $fail = 0;
    our $self;

    if (! ($self = $type->SUPER::new(%attr))) {
        return undef;
    }

    my ($data, $errs) = (undef, []);

    my @file = (
        $attr{fileset}
          ? ((ref($attr{fileset}) eq 'ARRAY')
             ? @{$attr{fileset}}
             : ( $attr{fileset} ))
          : ()
    );
    if ($prnt) {
        unshift(@file, $prnt->fileset());
    }

    if (@file) {
        local %ENV = $self->builder()->getenv();

        sub BUILDER () {
            $self->builder()
        };

        ($data, $errs) = merge_file(@file);
    }

    if (! @{$errs}) {
        $self->{_data_} = merge_data(@{$data});
        return $self;
    } else {
        $self->error(@{$errs});
        return undef;
    }
}

sub files ($) {
    my $self = shift;
    return ( @{$self->{_file_}} );
}

sub data ($) {
    my $self = shift;
    return $self->{_data_};
}

1;
