use strict;
use warnings;

# Configure GCC toolchains.
package Grace::Toolchain::GCC;

use File::Spec;

BEGIN {
    my ($dir, $pth, @gcc);
    foreach $pth (File::Spec->path()) {
        next if (! opendir($dir, $pth));
        @gcc =
            grep { -x $_ }
            map  { File::Spec->catfile($pth, $_) }
            grep { m{^.*g(?:cc|\+\+)$}o }
            readdir($dir);
print("GCC: [@gcc]\n");
    }
}

print(__PACKAGE__."\n");

1;
