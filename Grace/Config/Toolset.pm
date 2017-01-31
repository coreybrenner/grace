package Grace::Config::Toolset;

use strict;
use warnings;

use parent 'Grace::Config';

my %_rawfile;
my %_configs;

sub new ($@) {
    my $what = shift;
    my $type = (ref($what) || $what);
    my $join = join('|', @_);

    my $self = {
        file => \@_,
        errs => [],
        warn => [],
    };

    bless($self, $type);

    if (defined($self->{data} = $_configs{$join})) {
        return $self;
    }

    my $file;
    my $data;
    my %hash;

    foreach $file (@_) {
        if (! defined($data = $_rawfile{$file})) {
            if (! defined($data = eval { do $file })) {
                $self->error($@);
                next;
            }
            $_rawfile{$file} = $data;
        }
        %hash = ( %hash, %{$data} );
    }

    $self->{data} = $_configs{$join} = \%hash;

    return $self;
}

1;
