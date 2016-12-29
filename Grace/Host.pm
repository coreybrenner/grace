use strict;
use warnings;

# Host platform recognition.
package Grace::Host;

use POSIX qw{uname};
use Carp;

my ($_sysname, $_sysarch) = (uname())[0, 4];

$_sysname = lc($_sysname);
$_sysarch = lc($_sysarch);

if ($_sysname =~ m{^(?:mswin32|cygwin)$}o) {
    $_sysname = 'windows';
} elsif ($_sysname =~ m{^(?:darwin|mac.*|osx)$}o) {
    $_sysname = 'darwin';
} else {
    carp(__PACKAGE__.": Unknown host sysname: '$_sysname'");
}

#===============================================================================
if ($_sysarch =~ m{^(?:x86(?:.32)?|ia32|x32|(?:cex|i\d?|80\d?)86)$}o) {
    $_sysarch = 'x86_32';
} elsif ($_sysarch =~ m{^(?:x86.64|x64|amd64)$}o) {
    $_sysarch = 'x86_64';
} else {
    carp(__PACKAGE__.": Unknown host sysarch: '$_sysarch'");
}

sub sysname () {
    return $_sysname;
}

sub sysarch () {
    return $_sysarch;
}

1;
