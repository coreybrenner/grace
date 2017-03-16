package Grace::Config::Environ;

use strict;
use warnings;

use parent 'Grace::Config';

use Grace::ActiveConfig;

sub new {
    my ($what, $bldr, @file) = @_;
print(STDERR __PACKAGE__."->new(what=$what, bldr=$bldr, file=[@file])\n");

    my $type = (ref($what) || $what);
    my $prnt = (ref($what) && $what);
    my $self = $type->SUPER::new();

    my ($data, $errs, $warn);

    if ($prnt) {
        unshift(@file, @{$prnt->{_file_}});
    }

    $self->{_file_} = \@file;

    my %old = %ENV;
    my %env;
    {
        our $BUILDER = $bldr;
        sub BUILDER () { $BUILDER }

        %ENV = $bldr->getenv();
        foreach my $fil (@{$self->{_file_}}) {
            if (! defined(eval { do $fil })) {
                $self->error($@);
                last;
            }
        }
        %env = %ENV;
    }
    %ENV = %old;

    if (! defined($errs) || ! @{$errs}) {
        $self->{_data_} = Grace::ActiveConfig::activate(\%env);
    }

    return $self;
}

1;
