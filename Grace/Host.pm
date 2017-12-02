# Host platform recognition.
package Grace::Host;

use strict;
use warnings;

use POSIX qw{uname};
use Carp;

use Grace::Platform;

my ($_sysname, $_sysarch, $_systype) = (uname())[0, 4];

$_systype = 'unix';
$_sysname = lc($_sysname);
$_sysarch = lc($_sysarch);

if ($_sysname =~ m{^(?:mswin32|cygwin)$}o) {
    $_sysname = 'windows';
    $_systype = 'windows';
} elsif ($_sysname =~ m{^(?:darwin|mac.*|osx)$}o) {
    $_sysname = 'darwin';
} else {
    carp(__PACKAGE__.": Unknown host sysname: '$_sysname'");
}

if ($_sysarch =~ m{^(?:x86(?:.32)?|ia32|x32|(?:cex|i\d?|80\d?)86)$}o) {
    $_sysarch = 'x86_32';
} elsif ($_sysarch =~ m{^(?:x86.64|x64|amd64)$}o) {
    $_sysarch = 'x86_64';
} else {
    carp(__PACKAGE__.": Unknown host sysarch: '$_sysarch'");
}

our $_hostsys = Grace::Platform->new(
    sysname => $_sysname,
    sysarch => $_sysarch,
    systype => $_systype,
);

sub platform () {
    return $_hostsys;
}

sub sysconf {
    return $_hostsys->sysconf(@_);
}

sub sysname {
    return $_hostsys->sysname(@_);
}

sub sysarch {
    return $_hostsys->sysarch(@_);
}

sub fatarch {
    return $_hostsys->sysarch(@_);
}

1;
