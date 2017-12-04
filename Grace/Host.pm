# Host platform recognition.
package Grace::Host;

use strict;
use warnings;

use POSIX qw{uname};
use Carp;

use Data::Dumper;

use Grace::Platform;

my  $_systype = 'unix';
my ($_sysname, $_sysarch) = (uname())[0, 4];

$_sysname = lc($_sysname);
$_sysarch = lc($_sysarch);
print(STDERR __PACKAGE__." -- SYSNAME: $_sysname\n");
print(STDERR __PACKAGE__." -- SYSARCH: $_sysarch\n");

if ($_sysname =~ m{^(?:mswin32|cygwin)$}o) {
    $_sysname = 'windows';
    $_systype = 'windows';
} elsif ($_sysname =~ m{^(?:darwin|mac.*|osx)$}o) {
    $_sysname = 'darwin';
} else {
    carp(__PACKAGE__.": Unknown host sysname: '$_sysname'");
}

if (Grace::Platform::is_x86($_sysarch)) {
    $_sysarch = 'x86_32';
} elsif (Grace::Platform::is_x64($_sysarch)) {
    $_sysarch = 'x86_64';
} else {
    carp(__PACKAGE__.": Unknown host sysarch: '$_sysarch'");
}

our $_hostsys = Grace::Platform->new(
    sysname => $_sysname,
    sysarch => $_sysarch,
    systype => $_systype,
);
print(STDERR __PACKAGE__.": _hostsys: ".Dumper($_hostsys));

sub platform () {
    return $_hostsys;
}

sub sysconf {
    return $_hostsys->sysconf();
}

sub sysname {
    return $_hostsys->sysname();
}

sub sysarch {
    return $_hostsys->sysarch();
}

sub systype {
    return $_hostsys->systype();
}

sub fatarch {
    return $_hostsys->sysarch();
}

1;
