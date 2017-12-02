package Grace::Object;

use strict;
use warnings;

use Scalar::Util qw{weaken};

use Grace::LogEntry;

my %_objects;

sub new {
    my ($what, %attr) = @_;

    my $type = (ref($what) || $what);
    my $prnt = (ref($what) && $what);

    my $inst = $type . '@' . ++$_objects{$type};

    my %self = (
        _inst_ => $inst,
        _errs_ => [],
        _warn_ => [],
        _info_ => [],
    );

    my $bldr = ($attr{builder} || ($prnt && $prnt->builder()));
    if ($self{_bldr_} = $bldr) {
        weaken($self{_bldr_});
    }

    return bless(\%self, $type);
}

sub object_type {
    my $self = shift;
    return (split('@', $self->{_inst_}))[0];
}

sub object_name {
    my $self = shift;
    return $self->{_inst_};
}

sub _message {
    my $self = shift;
    my $meth = shift;
    my $bldr = $self->builder();
    my $strm = (
        (($meth eq 'info')
         ? '_info_'
         : (($meth eq 'error')
            ? '_errs_'
            : (($meth eq 'warning')
               ? '_warn_'
               : '')))
    );

    my @hold;
    foreach (@_) {
        if (! ref($_)) {
            push(@hold, $_);
        } elsif (ref($_) eq 'Grace::LogEntry') {
            if ($bldr && ($bldr != $self)) {
                if (@hold) {
                    $bldr->$meth(
                        Grace::LogEntry->new(
                            object => $self,
                            stream => $strm,
                            offset => scalar(@{$self->{$strm}}),
                            length => scalar(@hold),
                        )
                    );
                }
                $bldr->$meth($_);
            }
            push(@{$self->{$strm}}, grep { $_ } (@hold, $_));
            @hold = ();
        }
    }
    if (@hold) {
        if ($bldr && ($bldr != $self)) {
            $bldr->$meth(
                Grace::LogEntry->new(
                    object => $self,
                    stream => $strm,
                    offset => scalar(@{$self->{$strm}}),
                    length => scalar(@hold),
                )
            );
        }
        push(@{$self->{$strm}}, @hold);
    }

    return $self;
}

sub error {
    my $self = shift;
    return _message($self, 'error', @_);
}

sub errors {
    my $self = shift;
    return @{$self->{_errs_}};
}

sub warning {
    my $self = shift;
    return _message($self, 'warning', @_);
}

sub warnings {
    my $self = shift;
    return @{$self->{_warn_}};
}

sub info {
    my $self = shift;
    return _message($self, 'info', @_);
}

sub infos {
    my $self = shift;
    return @{$self->{_info_}};
}

sub builder {
    my $self = shift;
    return $self->{_bldr_};
}

1;
