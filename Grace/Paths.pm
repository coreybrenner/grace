package Grace::Paths;

use Cwd;
use File::Spec;
use Data::Dumper;

sub find_highest ($@) {
    my ($from, @list) = @_;

    my ($fil, %res);

    my ($vol, $dir, undef) = File::Spec->splitpath($from, 1);

    my @seg = File::Spec->splitdir($dir);
    my @cur;

    while (@seg) {
        push(@cur, shift(@seg));

        $dir = File::Spec->catdir(@cur);
        $dir = File::Spec->catpath($vol, $dir, '');

        foreach (@list) {
print(STDERR ">> Look for '$_' in path '$dir'\n");
            next if ($res{$_});
            $fil = File::Spec->catfile($dir, $_);
print(STDERR ">> Inspect file '$fil'\n");
            next if (! -e $fil);
print(STDERR ">> Got an extant '$_' file '$fil'\n");
            $res{$_} = $fil;
        }
    }

    return %res;
}

sub _abspath ($@) {
    my ($root, @list) = @_;
print(STDERR "_ABSPATH(root='$root', list=[@list])\n");

    my %rslt;
    my @segs;
    my $path;
    my $curr;
    my $file;

    foreach $curr (@list) {
        $path = $curr;
        if (! File::Spec->file_name_is_absolute($path)) {
            $path = File::Spec->catdir($root, $path);
        }

        if (($path =~ m{[\\/]+(?:\.\.?)?$}o) || (-d $path)) {
            $file = 0;
        } else {
            $file = 1;
        }
            
        my ($vol, $dir, $fil) = File::Spec->splitpath($path, ! $file);

        @segs = grep { $_ } File::Spec->splitdir($dir);

        for (my $i = 0; $i < @segs; ) {
            if ($segs[$i] eq File::Spec->curdir()) {
                splice(@segs, $i, 1);
                next;
            } elsif ($segs[$i] eq File::Spec->updir()) {
                splice(@segs, ($i - ($i ? 1 : 0)), (1 + ($i ? 1 : 0)));
                $i = ($i ? ($i - 1) : $i);
                next;
            }
            ++$i;

            my @head = @segs;
            splice(@head, 0, $i);

            $path = File::Spec->catdir($vol, @head);
            if (-l $path) {
                my $link = readlink($path);
                my $indx = $i;
                if (File::Spec->file_name_is_absolute($link)) {
                    $indx = 0;
                } else {
                    $path = File::Spec->catdir($path, $link);
                }
                ($vol, $dir, undef) = File::Spec->splitpath($path);
                @head = File::Spec->splitdir($dir);
                splice(@segs, 0, $i, @head);
                $i = $indx;
            }
        }

        $path = File::Spec->catdir($vol, @segs);
        if ($file) {
            $path = File::Spec->catfile($path, $file);
        }

        $rslt{$curr} = $path;
    }

    return %rslt;
}

sub abspath (@) {
print(STDERR "ABSPATH(list=[@_])\n");
    return _abspath(Cwd::cwd(), @_);
}

sub _realpath ($@) {
    my ($root, @list) = @_;
print(STDERR "_REALPATH(root='$root', list=[@list])\n");
    my $path;
    my %rslt;

    foreach (@list) {
        $path = $_;
        if (! File::Spec->file_name_is_absolute($path)) {
            $path = File::Spec->catdir($curr, $path);
        }
        if (defined($path = Cwd::realpath($_))) {
            $rslt{$_} = $path;
        }
    }

    return %rslt;
}

sub realpath (@) {
print(STDERR "REALPATH(list=[@_])\n");
    return _realpath(Cwd::cwd(), @_);
}

sub exists_below ($@) {
    my ($root, @list) = @_;
print(STDERR "EXISTS_BELOW(root='$root', list=[@list])\n");

    my ($path, $look, %rslt);

    # Strip off directory separators so the raw dir name can be matched
    # against by adding a separator.
    if (! File::Spec->file_name_is_absolute($root)) {
        $root = File::Spec->catdir(Cwd::cwd(), $root);
    }
    $root = Cwd::realpath($root);
print(STDERR ">> root: '$root'\n");

    foreach $path (@list) {
print(STDERR ">> path: '$path'\n");
        $look = $path;
        if (! File::Spec->file_name_is_absolute($look)) {
            $look = File::Spec->catdir($root, $look);
        }
print(STDERR ">> look: '$look'\n");
        next if (! defined($look = Cwd::realpath($look)));
print(STDERR ">> look '$look' exists\n");
        if (("$look/" =~ m{^$root/+(.*[^/])?/*$}) && -e $look) {
print(STDERR ">> look '$look' below '$root'; tail: ".(defined($1)?"'$1'":'<undef>')."\n");
            $rslt{$path} = $1;
        }
    }
print(STDERR ">> return\n");
print(STDERR Dumper([ 'result', \%rslt ]));
    return %rslt;
}

1;
