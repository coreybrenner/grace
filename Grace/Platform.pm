package Grace::Platform;

use strict;
use warnings;

use parent 'Grace::Object';

use Data::Dumper;

use POSIX qw{uname};
use Carp;

our $_match_x86_regex = qr{(?:x86(?:.32)?|ia32|x32|(?:cex|i\d?|80\d?)86)}io;
our $_match_x64_regex = qr{(?:x86.64|x64|amd64)}io;
our $_split_sys_regex = qr{(([^_/]+)(?:(?:_(.+))|/+(?:fat/+)?(.+))?)}io;

sub split {
    my $what = shift;
    my $conf = shift;
    my $self = (ref($what) && $what);
    my $name = ($self ? $self->sysconf() : ($conf || $what));

    $name =~ m{^$_split_sys_regex$}o;

    return {
        sysconf => $1,
        sysname => $2,
        sysarch => $3,
        subarch => $4,
    };
}

# __PACKAGE__::is_x86
# __PACKAGE__->is_x86
# $object->is_x86
sub is_x86 {
    my $what = shift;
    my $self = (ref($what) && $what);
    my $conf = ($self ? $self->sysarch() : $what);

    return ($conf =~ m{^$_match_x86_regex$}o);
}

# __PACKAGE__::is_x64
# __PACKAGE__->is_x64
# $object->is_x64
sub is_x64 {
    my $what = shift;
    my $self = (ref($what) && $what);
    my $conf = ($self ? $self->sysarch() : $what);

    return ($conf =~ m{^$_match_x64_regex$}o);
}

sub new {
    my ($what, %attr) = @_;

    my $type = (ref($what) || $what);
    my $prnt = (ref($what) && $what);

    my $self = $type->SUPER::new(%attr);
    my $fail = 0;

    my $systype = ($attr{systype} || ($prnt && $prnt->systype()));
    my $sysname = ($attr{sysname} || ($prnt && $prnt->sysname()));
    my $sysconf =  $attr{sysconf};
    my $sysarch =  $attr{sysarch};
    my $subarch =  $attr{subarch};
    my $fatarch =  $attr{fatarch};

    if (! $sysconf && $sysname) {
        $sysconf = (
            $sysarch
            ? join('_', $sysname, $sysarch)
            : ($subarch
               ? join('/fat/', $sysname, $subarch)
               : $sysname)
        );
    }

    if (! $sysname && $sysconf) {
        ($sysname) = (
            $sysarch
            ? m{^(.+)_$sysarch}i
            : ($sysconf =~ m{^([^_]+)(?:_.+)?$}o)
        );
    }

    if (! $sysconf) {
        $fail = 1;
        $self->error("$type\->new(): Could not determine 'sysconf' setting");
    }
    if (! $sysname) {
        $fail = 1;
        $self->error("$type\->new(): Could not determine 'sysname' setting");
    }
    if (! $systype) {
        $fail = 1;
        $self->error("$type\->new(): Could not determine 'systype' setting");
    }
    if (! $subarch && ! $sysarch && ! $fatarch) {
        $fail = 1;
        $self->error(
            "$type\->new(): Could not determine 'subarch',"
          . " 'sysarch' or 'fatarch' settings"
        );
    }

    #
    # Load up the object with whatever information we have, so that if
    # we are actually in a failure state, the object reference in the
    # error log can be examined further.
    #
    $self->{_plat_}{systype} = $systype;
    $self->{_plat_}{sysconf} = $sysconf;
    $self->{_plat_}{sysname} = $sysname;
    if ($subarch) {
        $self->{_plat_}{subarch} = $subarch;
    } elsif ($sysarch) {
        $self->{_plat_}{sysarch} = $sysarch;
    } elsif ($fatarch) {
        $self->{_plat_}{fatarch} = $fatarch;
    }

    return ($fail ? undef : $self);
}

#
# Usage:
#
#   $foo->systype()
#       return platform configuration type.
#   $foo->sysconf($match_this_systype)
#       returns platform config type, if matching, undef otherwise.
#
sub systype {
    my $self = shift;
    my $look = shift;

    if ($look) {
        return (($self->{_plat_}{systype} eq $look) ? $look : undef);
    } else {
        return $self->{_plat_}{systype};
    }
}

#
# Usage:
#
#   $foo->sysconf()
#       return platform configuration name.
#   $foo->sysconf($match_this_sysconf)
#       returns platform config name, if matching, undef otherwise.
#
sub sysconf {
    my $self = shift;
    my $look = shift;

    if ($look) {
        return (($self->{_plat_}{sysconf} eq $look) ? $look : undef);
    } else {
        return $self->{_plat_}{sysconf};
    }
}

#
# Usage:
#
#   $foo->sysname()
#       return platform operating system name.
#   $foo->sysname($match_this_sysname)
#       returns platform os name, if matching, undef otherwise.
#
sub sysname {
    my $self = shift;
    my $look = shift;

    if ($look) {
        return ((lc($self->{_plat_}{sysname}) eq lc($look)) ? $look : undef);
    } else {
        return $self->{_plat_}{sysname};
    }
}

#
# Usage:
#
#   $foo->sysarch()
#       return thin platform cpu information.
#   $foo->sysarch($match_this_sysarch)
#       returns thin platform cpu information, if matching, undef otherwise.
#
sub sysarch {
    my $self = shift;
    my $look = shift;

    if ($look) {
        return ((lc($self->{_plat_}{sysarch}) eq lc($look)) ? $look : undef);
    } else {
        return $self->{_plat_}{sysarch};
    }
}

#
# Usage:
#
#   $foo->subarch()
#       return fat sub-architecture name, if set.
#   $foo->subarch($match_this_subarch)
#       returns fat sub-architecture name, if matching, undef otehrwise.
#
sub subarch {
    my $self = shift;
    my $look = shift;

    if ($look) {
        return ((lc($self->{_plat_}{subarch}) eq lc($look)) ? $look : undef);
    } else {
        return $self->{_plat_}{subarch};
    }
}

#
# Usage:
#
#   $foo->fatarch()
#       return list of fat sub-architecture names, if any.
#   $foo->fatarch($find_this_subarch)
#       return matching fat sub-architecture, or undef.
#
sub fatarch {
    my $self = shift;
    my $arch = shift;

    if ($arch) {
        return $self->{_plat_}{fatarch}{$arch};
    } else {
        return keys(%{$self->{_plat_}{fatarch}});
    }
}

1;
