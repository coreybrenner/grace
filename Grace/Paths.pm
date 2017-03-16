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
            next if ($res{$_});
            $fil = File::Spec->catfile($dir, $_);
            next if (! -e $fil);
            $res{$_} = $fil;
        }
    }

    return %res;
}

sub _abspath ($@) {
    my ($root, @list) = @_;

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
    return _abspath(Cwd::cwd(), @_);
}

sub _realpath ($@) {
    my ($root, @list) = @_;
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
    return _realpath(Cwd::cwd(), @_);
}

sub exists_below ($@) {
    my ($root, @list) = @_;

    my ($path, $look, %rslt);

    # Strip off directory separators so the raw dir name can be matched
    # against by adding a separator.
    if (! File::Spec->file_name_is_absolute($root)) {
        $root = File::Spec->catdir(Cwd::cwd(), $root);
    }
    $root = Cwd::realpath($root);

    foreach $path (@list) {
        $look = $path;
        if (! File::Spec->file_name_is_absolute($look)) {
            $look = File::Spec->catdir($root, $look);
        }
        next if (! defined($look = Cwd::realpath($look)));
        if (("$look/" =~ m{^$root/+(.*[^/])?/*$}) && -e $look) {
            $rslt{$path} = ($1 || File::Spec->curdir());
        }
    }

    return %rslt;
}

1;
