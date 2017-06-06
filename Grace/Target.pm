package Grace::Target;

use parent 'Grace::Object';

sub new {
    my $type = shift;
    my $self = $type->SUPER::new(@_);

    $self->{_needs_} = {};
    $self->{_after_} = {};
    $self->{_ifile_} = {};
    $self->{_ofile_} = {};

    return $self;
}

sub build {
    return 1;
}

sub clean {
    return 1;
}

sub build_after {
    my $self = shift;
    foreach my $tgt (@_) {
        $self->{_after_}->{$tgt} = 1;
    }
}

sub builds_after {
    my $self = shift;
    return unique(keys(%{$self->{_needs_}}), keys(%{$self->{_after_}}));
}

sub input {
    my $self = shift;
    foreach my $inp (@_) {
        $self->{_ifile_}->{$inp} = $inp;
    }
}

sub inputs {
    my $self = shift;
    return values(%{$self->{_ifile_}});
}

sub output {
    my $self = shift;
    foreach my $out (@_) {
        $self->{_ofile_}->{$out} = $out;
    }
}

sub outputs {
    my $self = shift;
    return values(%{$self->{_ofile_}});
}

sub require {
    my $self = shift;
    foreach my $tgt (@_) {
        $self->{_needs_}->{$tgt} = 1;
    }
}

sub requires {
    my $self = shift;
    return keys(%{$self->{_needs_}});
}

1;
