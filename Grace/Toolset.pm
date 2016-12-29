use strict;
use warnings;

package Grace::Toolset;

use File::Spec;
use Carp;

use Grace::Util;

my %_drivers;

sub register ($$$) {
    my ($drv, $chn, $new) = @_;

    my $old;

    if ($old = $_drivers{$drv}{toolchain}{$chn}) {
        carp(__PACKAGE__.": Driver '$drv' already registered '$chn'");
        carp(__PACKAGE__.": Old Rootdir: $old->{rootdir}");
        carp(__PACKAGE__.": New Rootdir: $new->{rootdir}");
        carp(__PACKAGE__.": Replacing toolchain '$chn'");
    }

    return ($_drivers{$drv}{toolchain}{$chn} = $new);
}

BEGIN {
    my ($inc, $pth, $dir, $fil, %drv, $drv);
    # Trace @INC to search for Grace::Toolchain drivers.
    foreach $inc (@INC) {
        $pth = $inc; # Copy to $pth, to avoid altering @INC.
        if (! File::Spec->file_name_is_absolute($pth)) {
            # Make an absolute path out of a relative one.
            $pth = File::Spec->catdir(File::Spec->curdir(), $pth);
        }
        # Inspect Grace/Toolchain/*.
        $pth = File::Spec->catdir($pth, 'Grace', 'Toolchain');
        next if (! -d $pth);
        if (! opendir($dir, $pth)) {
            carp("Path '$pth': $!\n");
            next;
        }
        # Pick up *.pm from Grace/Toolchain/...
        foreach $drv (grep { m{^.*\.pm$}io } readdir($dir)) {
            $fil =  File::Spec->catdir($pth, $drv);
            $drv =~ s{^(.*)\.pm$}{Grace::Toolchain::$1}io;
            $drv{$drv} = $fil;
        }
        closedir($dir);
    }
    # Doctor found driver filenames into something loadable.
    foreach $drv (keys(%drv)) {
        eval "require $drv" or do {
            carp("Could not load driver '$drv': $@\n");
            next;
        };
        $_drivers{$drv}{drivermod} = $drv{$drv};
    }
}

sub drivers () {
    return keys(%_drivers);
}

sub toolchains (@) {
    shift;
print(STDERR __PACKAGE__."->toolchains([@_])\n");
    my @drv = @_;
    my $drv;
    my @chn;
    if (! @drv) {
print(STDERR "->toolchains(): no drivers specified, probe all.\n");
        @drv = keys(%_drivers);
print(STDERR "->toolchains(): probe [@drv]\n");
    }
    foreach $drv (@drv) {
        map { push(@chn, "$drv/$_") } keys(%{$_drivers{$drv}{toolchain}});
    }
    return @chn;
}

sub toolchain ($) {
    shift;
    my $req = shift;
print(STDERR __PACKAGE__."->toolchain($req)\n");

    my ($drv, $chn, $cfg, $err);

    ($drv, $chn) = split(m{/+}o, $req, 2);
    if (defined($chn)) {
        $cfg = $_drivers{$drv}{toolchain}{$chn};
    } else {
        $chn = $drv;
        foreach $drv (keys(%_drivers)) {
            if ($cfg = $_drivers{$drv}{toolchain}{$chn}) {
                return $cfg;
            }
        }
    }

    return $cfg;
}

# Probe Grace/Toolchain/* for appropriate toolchain drivers.
# Attempt to load each toolchain driver, in turn.
# Each toolchain driver will attempt to auto-discover toolchains.
# Each toolchain driver may present multiple toolchains.
# Each individual toolchain is individually selectable.

1;
