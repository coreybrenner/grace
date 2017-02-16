#!/usr/bin/perl -w

use Cwd;
use File::Spec;
use Data::Dumper;

use Grace::Options           qw{:OPT_};
use Grace::Utility           qw{unique};
use Grace::Paths;
use Grace::Config::Systems;
#use Grace::Config::Toolset;
#use Grace::Config::Environ;

my  $program        = (File::Spec->splitpath($0))[2];
my  $version        = '0.0';
my  $cfgfile        = 'Graceconf';
my  $prjfile        = 'Graceproj';
my  $optfile        = 'Graceopts';
my  $outroot        = 'out';
my  $genroot        = $outroot;
my  $pubroot        = 'pub';
my  $systems_config = 'systems.cfg';
my  $sysconf        = 'default';
my  $toolset_config = 'toolset.cfg';
my  $toolset        = 'common';
my  $environ_config = 'environ.cfg';

my  %options;
my  %globals;
my  @warning;
my  @errlist;
my  $nobuild = 0;
my  $showver = 0;
my  $showhlp = 0;
my  $numjobs = 1;
my  $runerrs = 0;
my  $loadavg = undef;
my  $nicelev = undef;
my  $nullenv = 0;
my  $dobuild = 1;
my  $dontdie = 0;
my  $list_toolsets = 0;
my  $show_toolsets = 0;
my  $list_projects = 0;
my  $show_projects = 0;
my  $show_environ  = 0;
my  $show_toolenv  = 0;

#
# grace.pl \
#   --srcroot foo=/src/abc     --srcroot bar=/src/def \
#   --sysconf foo=mac_x86-32   --sysconf bar=linux_x86-64,win_x86-64 \
#   --toolset foo=xcode-8.1    --toolset bar/linux_x86-64=gcc-6.2 \
#   --instrum foo=debug        --instrum bar=release \
#   --product foo=desktop      --product bar=auto,acr,gninternal \
#   --outroot foo=/tmp/foo-xyz --outroot bar=/tmp/bar-rel \
#   --pubroot=/tmp/merged # <-- publish to the same tree
#   --toolset=java-1.9 # <-- all builds use java-1.9
#   --toolset=gcc-3.2 # <-- all builds use gcc-3.2 (probably will not work...)
#

sub _opt_help ($$$$);
sub _opt_vers ($$$$);
sub _opt_jobs ($$$$);
sub _opt_load ($$$$);
sub _opt_nice ($$$$);
sub _opt_flag ($$$$);
sub _opt_list ($$$$);
sub _opt_dict ($$$$);
sub _opt_vars ($$$$);

my %aliases = (
    src      => 'srcroot',
    rel      => 'relpath',
    out      => 'outroot',
    gen      => 'genroot',
    pub      => 'pubroot',
    platform => 'sysconf',
);
    
my @options = (
    {
        long        => [ 'srcroot', 'src', ],
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ=]PATH',
        help        => 'Add a source tree pointed to by its root',
    }, {
        long        => [ 'relpath', 'rel', ],
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ=]PATH',
        help        => 'Build targets under a relative path',
    }, {
        long        => [ 'outroot', 'out', ],
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ=]PATH',
        help        => 'Generate build artifacts to this directory tree',
    }, {
        long        => [ 'genroot', 'gen', ],
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ=]PATH',
        help        => 'Generate sources to this directory tree [default: outroot]',
    }, {
        long        => [ 'pubroot', 'pub', ],
        long_hidden => 'publish',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ=]PATH',
        help        => 'Publish packages to this directory tree',
    }, {
        long        => [ 'sysconf', 'sys', ],
        hidden_long => 'platform',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ=]ARCH...',
        help        => 'Configure for target platforms',
    }, {
        long        => 'product',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ=]PROD...',
        help        => 'Restrict build product variants',
    }, {
        long        => 'toolset',
        type        => OPT_UNWANTED,
        func        => \&_opt_dict,
        args        => [ '[[PROJ/]ARCH=]TOOL...', '[PROJ/]TOOL...' ],
        help        => 'Force use of toolset TOOL for platform ARCH',
    }, {
        long        => 'version',
        type        => OPT_UNWANTED,
        func        => \&_opt_vers,
        help        => 'Print version string',
    }, {
        long        => [ 'keep-going', 'no-keep-going' ],
        type        => OPT_ATTACHED,
        func        => \&_opt_flag,
        args        => 'PROJ...',
        help        => 'Keep going (or not) when errors encountered',
    }, {
        long        => 'jobs',
        flag        => 'j',
        type        => OPT_OPTIONAL,
        func        => \&_opt_jobs,
        args        => 'N',
        help        => 'Set max number of parallel jobs (no arg => unlimited)',
    }, {
        long        => 'load',
        flag        => 'l',
        type        => OPT_OPTIONAL,
        func        => \&_opt_load,
        args        => 'X.Y',
        help        => 'Start jobs when load average below X.Y (no arg => unset)',
    }, {
        long        => 'nice',
        flag        => 'n',
        type        => OPT_OPTIONAL,
        func        => \&_opt_nice,
        args        => '+/-N',
        help        => 'Set scheduling priority +/-N (no arg => unset)',
    }, {
        long        => 'help',
        flag        => 'h',
        flag_hidden => '?',
        type        => OPT_UNWANTED,
        func        => \&_opt_help,
        help        => 'Print this screen and exit',
    }, {
        long        => 'setvar',
        type        => OPT_REQUIRED,
        func        => \&_opt_dict,
        args        => '[PROJ/]NAME=DATA',
        help        => 'Set a build (not environment) variable',
    }, {
        long        => 'setenv',
        type        => OPT_REQUIRED,
        func        => \&_opt_vars,
        args        => '[PROJ/]NAME=DATA',
        help        => 'Set an environment (not build) variable',
    }, {
        long        => 'toolset-config',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ=]FILE',
        help        => 'Use toolset configuration file FILE',
    }, {
        long        => 'systems-config',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ=]FILE',
        help        => 'Use target platform configuration file FILE',
    }, {
        long        => 'empty-environ',
        type        => OPT_ATTACHED,
        func        => \&_opt_flag,
        args        => 'PROJ...',
        help        => 'Configure against an empty environment',
    }, {
        long        => 'environ-config',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ=]FILE',
        help        => 'Use environment configuration file FILE',
    }, {
        long        => 'list-toolsets',
        type        => OPT_ATTACHED,
        func        => \&_opt_flag,
        args        => 'PROJ...',
        help        => 'List available toolsets',
    }, {
        long        => 'show-toolsets',
        type        => OPT_ATTACHED,
        func        => \&_opt_flag,
        args        => 'PROJ...',
        help        => 'Show details about configured toolsets',
    }, {
        long        => 'show-toolset',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ=]TOOL...',
        help        => 'Show details about toolset TOOL',
    }, {
        long        => 'show-toolenv',
        type        => OPT_ATTACHED,
        func        => \&_opt_flag,
        args        => 'PROJ...',
        help        => 'Show complete toolset environment',
    }, {
        long        => 'show-environ',
        type        => OPT_ATTACHED,
        func        => \&_opt_flag,
        args        => 'PROJ...',
        help        => 'Show complete environment',
    }, {
        long        => [ 'build', 'no-build' ],
        type        => OPT_ATTACHED,
        func        => \&_opt_flag,
        args        => 'PROJ...',
        help        => 'Build or do not build',
    }, {
        long        => 'target',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ=]NAME',
        help        => 'Build target NAME',
    }, {
        long        => 'list-projects',
        type        => OPT_ATTACHED,
        func        => \&_opt_flag,
        args        => 'PROJ...', 
        help        => 'List configured projects',
    }, {
        long        => 'show-projects',
        type        => OPT_ATTACHED,
        func        => \&_opt_flag,
        args        => 'PROJ...', 
        help        => 'Show details about configured projects',
    }, {
        long        => 'show-project',
        type        => OPT_REQUIRED,
        func        => \&_opt_flag,
        args        => 'PROJ...', 
        help        => 'Show details about project PROJ',
    }, {
        long        => 'search-alias',
        type        => OPT_REQUIRED,
        func        => \&_opt_dict,
        args        => '[PROJ/]NAME=PROJ',
        help        => 'Set project alias for resolving target searches',
    }, {
        long        => 'search-order',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ=]NAME...',
        help        => 'Set target origin search order',
    }, {
        long        => 'search-group',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[NAME=]PROJ...',
        help        => 'Cluster projects together in search order',
    },
);

my $_rex_int = qr{};
my $_rex_pos = qr{};
my $_rex_flo = qr{};

sub _error (@) {
    push(@errlist, @_);
    return scalar(@_);
}

sub _warn (@) {
    push(@warning, @_);
    return scalar(@_);
}

sub _print ($) {
    my $val = shift;
    return (defined($val) ? '<undef>' : "'$val'");
}

sub _match ($$) {
    my ($arg, $rex) = @_;

    if ($arg =~ qr{$rex}) {
        return $arg;
    } else {
        return undef;
    }
}

sub _opt_help ($$$$) {
    $showhlp = 1;
    return 0;
}

sub _opt_vers ($$$$) {
    $showver = 1;
    return 0;
}

sub _opt_jobs ($$$$) {
    my ($opt, $aop, $arg, $vec) = @_;
    if (! defined($arg)) {
        # --jobs= or --jobs <end-of-args>
        $loadavg = undef;
        # Consume no args.
        return 0;
    } elsif (! $aop) {
        # --jobs something-that-might-be-relevant
        $arg = $vec->[0]
    }
    if (defined(my $val = _match($arg, $_rex_int))) {
        if (($val = int($val)) <= 0) {
            _error("Option '$opt': Value must be > 0");
        } else {
            $numjobs = $val;
        }
        return ($aop ? 0 : 1);
    } elsif ($aop) {
        _error("Option '$opt': Argument must be integer");
    }
    return 0;
}

sub _opt_load ($$$$) {
    my ($opt, $aop, $arg, $vec) = @_;
    if (! defined($arg)) {
        # --load= or --load <end-of-args>
        $loadavg = undef;
        # Consume no args.
        return 0;
    } elsif (! $aop) {
        # --load something-that-might-be-relevant
        $arg = $vec->[0]
    }
    if (defined(my $val = _match($arg, $_rex_flo))) {
        if ($loadavg < 0.0) {
            _error("Option '$opt': Value must be >= 0.0");
        } else {
            $loadavg = $val;
        }
        return ($aop ? 0 : 1);
    } elsif ($aop) {
        _error("Option '$opt': Argument must be floating point");
    }
    return 0;
}

sub _opt_nice ($$$$) {
    my ($opt, $aop, $arg, $vec) = @_;
    if (! defined($arg)) {
        # --nice= or --nice <end-of-args>
        $nicelev = undef;
        # Consume no args.
        return 0;
    } elsif (! $aop) {
        # --nice something-that-might-be-relevant
        $arg = $vec->[0]
    }
    if (defined(my $val = _match($arg, $_rex_int))) {
        $nicelev = $val;
        return ($aop ? 0 : 1);
    } elsif ($aop) {
        _error("Option '$opt': Argument must be integer");
    }
    return 0;
}

sub _opt_flag ($$$$) {
    my ($opt, $aop, $arg, $vec) = @_;

    my ($not, $nam) = ($opt =~ m{^(?:--?)?(no-)?(.+)$}o);
    $not = ($not ? 1 : 0);

    if ($aliases{$nam}) {
        $nam = $aliases{$nam};
    }

    my @prj = Grace::Options::split($arg || '');
    if (! @prj) {
        @prj = ('');
    }

    foreach (@prj) {
        push(@{$options{$_}{$nam}}, [ '=', ! $not ]);
    }

    return ($aop ? 0 : (defined($arg) ? 1 : 0));
}

sub _opt_list ($$$$) {
    my ($opt, $aop, $arg, $vec) = @_;

    my ($nam) = ($opt =~ m{^(?:--?)?(.+)$}o);

    if ($aliases{$nam}) {
        $nam = $aliases{$nam};
    }

    my ($cfg, $Aop, $val)
        = ($arg =~ m{^(?:((?:(?>[^:?+=]+)|(?>[:?+](?!=)))+)?([:?+]?=))?(.*)$}o);

    if ((defined($cfg) ? 1 : 0) ^ (defined($Aop) ? 1 : 0)) {
        my $msg = sprintf("INTERNAL: C=%s, A=%s, V=%s",
                          _print($cfg), _print($Aop), _print($val)
                         );
        _error($msg);
        return 0;
    }
    if (! defined($cfg)) {
        $Aop = '+=';
        $cfg = '';
    }

    my @val = Grace::Options::split($val || '');
    my $tbl;

    $tbl = ($options{$cfg} || ($options{$cfg} = {}));

    if (($Aop ne '?=') || ! defined($tbl->{$nam})) {
        if ($Aop eq '+=') {
            push(@{$tbl->{$nam}}, [ '+', @val ]);
        } else {
            push(@{$tbl->{$nam}}, [ '=', @val ]);
        }
    }

    return ($aop ? 0 : 1);
}

sub __opt_dist (@) {
    my ($opt, $aop, $arg, $vec, $fun) = @_;

    my ($nam) = ($opt =~ m{^(?:--?)?(.+)$}o);
    if ($aliases{$nam}) {
        $nam = $aliases{$nam};
    }

    my ($cfg, $key, $Aop, $val);

    ($cfg, $arg) = ($arg =~ m{^(?:((?:[^:?+=/]+|[:?+](?!=))+)?/)?(.+)$}o);

    ($key, $Aop, $val)
        = ($arg =~ m{^(?:((?:[^:?+=]+|[:?+](?!=))+)?([:?+]?=))?(.*)$}o);

    if ((defined($key) ? 1 : 0) ^ (defined($Aop) ? 1 : 0)) {
        my $msg = sprintf("INTERNAL: C=%s, K=%s, A=%s, V=%s",
                          _print($cfg), _print($key),
                          _print($Aop), _print($val)
                         );
        _error($msg);
        return 0;
    }
    if (! $cfg) {
        $cfg = '';
    }
    if (! $key) {
        $Aop = '+=';
        $key = '';
    }

    my @val = &{$fun}($val || '');
    my $tbl;

    $tbl = ($options{$cfg} || ($options{$cfg} = {}));

    if (($Aop ne '?=') || ! defined($tbl->{$nam}->{$key})) {
        if ($Aop eq '+=') {
            push(@{$tbl->{$nam}->{$key}}, [ '+', @val ]);
        } else {
            push(@{$tbl->{$nam}->{$key}}, [ '=', @val ]);
        }
    }

    return ($aop ? 0 : 1);
}

sub _opt_dict ($$$$) {
    sub _split_settings ($) {
        return Grace::Options::split($_[0]);
    }
    return __opt_dist(@_, \&_split_settings);
}

sub _opt_vars ($$$$) {
    sub _split_variable ($) {
        return ( $_[0] );
    }
    return __opt_dist(@_, \&_split_variable);
}

sub resolve_srcroot () {
    my (%dir, @dir, $dir);
    my (@top, $top, $cfg);
    my (%fil, $fil);
    my $vol;
    my $cwd = Cwd::cwd();

    # Determine whether any source roots were mentioned on the command line.
    if (defined($dir = $options{''}{srcroot})) {
        @dir = map { my @arr = @{$_}; splice(@arr, 1) } @{$dir};
        foreach $dir (@dir) {
            if (! File::Spec->file_name_is_absolute($dir)) {
                $dir = File::Spec->catdir($cwd, $dir);
            }
            push(@top, Cwd::realpath($dir));
        }
        @top = unique(@top);
    }

    if (! @top) {
        my %cfg = Grace::Paths::find_highest($cwd, $cfgfile, $prjfile);
        foreach $dir (values(%cfg)) {
            ($vol, $dir, undef) = File::Spec->splitpath($dir);
            $dir = File::Spec->catpath($vol, $dir, '');
            push(@top, $dir);
        }
        $top = (sort(@top))[0];

        if (! defined($top)) {
            $top = $cwd;
        }

        @top = ( Cwd::realpath($top) );
    }

    $configs{''}{srcroot} = \@top;

    foreach $cfg (grep { $_ } keys(%options)) {
        if (! defined($dir = $options{$cfg}{srcroot})) {
            $configs{$cfg}{srcroot} = $configs{''}{srcroot};
        } else {
            my @sub;
            @dir = map { my @arr = @{$_}; splice(@arr, 1) } @{$dir};
            foreach $dir (@dir) {
                if (! File::Spec->file_name_is_absolute($dir)) {
                    $dir = File::Spec->catdir($cwd, $dir);
                }
                push(@sub, Cwd::realpath($dir));
            }
            @sub = unique(@sub);
            $configs{$cfg}{srcroot} = \@sub;
        }
    }
}

#        long        => 'search-alias',
#        type        => OPT_REQUIRED,
#        func        => \&_opt_dict,
#        args        => '[PROJ/]NAME=PROJ',
#        help        => 'Set project alias for resolving target searches',
#    }, {
#        long        => 'search-order',
#        type        => OPT_REQUIRED,
#        func        => \&_opt_list,
#        args        => '[PROJ=]NAME...',
#        help        => 'Set target origin search order',
#    }, {
#        long        => 'search-group',
#        type        => OPT_REQUIRED,
#        func        => \&_opt_list,
#        args        => '[NAME=]PROJ...',
#        help        => 'Cluster projects together in search order',

sub resolve_relpath () {
    my (@rel, $rel);
    my (@dir, $dir);
    my (%top, @top, $top);
    my $cfg;

    my $cwd = Cwd::realpath(Cwd::cwd());

    if (defined($dir = $options{''}{relpath})) {
        @top = map { my @arr = @{$_}; splice(@arr, 1) } @{$dir};
    } else {
        @top = ( $cwd );
    }

    foreach $cfg (keys(%configs)) {
        if (defined($dir = $options{$cfg}{relpath})) {
            @dir = map { my @arr = @{$_}; splice(@arr, 1) } @{$dir};
        } else {
            @dir = @top;
        }

        foreach $top (@{$configs{$cfg}{srcroot}}) {
            my %sub = Grace::Paths::exists_below($top, @dir);
            my @arr = unique(grep { defined } values(%sub));
            if (! @arr) {
                @arr = ( File::Spec->curdir() );
            }
            $configs{$cfg}{relpath}{$top} = \@arr;
        }
    }
}

sub _resolve_outdir ($) {
    my $key = shift;

    my $cwd = Cwd::realpath(Cwd::cwd());

    my ($dir, $top, $cfg, $src, $out);

    if (defined($dir = $options{''}{$key})) {
        # $dir = [ [ '+', dir, dir, ... ], ... ].
        # Last one wins.
        $top = $dir->[-1]->[-1];
        if (! File::Spec->file_name_is_absolute($top)) {
            $top = File::Spec->catdir($cwd, $top);
        }
        # If we specify --outroot=/tmp/foo, we want all configs to build
        # there.  If we specify --outroot=foo, we still want all configs
        # to build to the directory specified ($PWD/foo).  We resolve this
        # to an absolute path, which will cause all configurations to use
        # the same dir.  Otherwise ...
    } else {
        # If --outroot=... is left unspecified, generate a subdir of each
        # srcroot.  Targets will resolve across different artifact caches.
        $top = eval "\$$key";
    }

    foreach $cfg (keys(%configs)) {
        if (defined($dir = $options{$cfg}{$key})) {
            # Specifying an outroot for a specific configuration causes
            # that configuration to resolve its own outroot.  Last one wins.
            $dir = $dir->[-1]->[-1];
            if (! File::Spec->file_name_is_absolute($dir)) {
                $dir = File::Spec->catdir($cwd, $dir);
            }
        } else {
            # Otherwise, accept the default.
            $dir = $top;
        }

        foreach $src (@{$configs{$cfg}{srcroot}}) {
            if (! File::Spec->file_name_is_absolute($out = $dir)) {
                $out = File::Spec->catdir($src, $out);
            }
            $configs{$cfg}{$key}{$src} = $out;
        }
    }
}

sub resolve_outroot () {
    _resolve_outdir('outroot');
}

sub resolve_genroot () {
    _resolve_outdir('genroot');
}

sub resolve_pubroot () {
    _resolve_outdir('pubroot');
}

sub _resolve_config (%) {
    my %setup = @_;

    my (@def, $def);
    my (@fil, $fil);
    my $cfg;

    my $cwd = Cwd::realpath(Cwd::cwd());

    if (! defined($fil = $options{''}{$setup{key}})) {
        @def = ( $setup{dfl} );
    } else {
        @fil = map { my @arr = @{$_}; splice(@arr, 1) } @{$fil};
        foreach $fil (@fil) {
            if (! File::Spec->file_name_is_absolute($fil)) {
                $fil = File::Spec->catdir($cwd, $fil);
            }
            if (! -f $fil) {
                _error("--$setup{key} '$fil': $!");
            } else {
                push(@def, Cwd::realpath($fil));
            }
        }
        @def = unique(@def);
    }

    foreach $cfg (keys(%configs)) {
        if (! defined($fil = $options{$cfg}{$setup{key}})) {
            @fil = @def;
        } else {
            foreach $fil (@{$fil}) {
                if (! File::Spec->file_name_is_absolute($fil)) {
                    $fil = File::Spec->catdir($cwd, $fil);
                }
                if (! -f $fil) {
                    _error("--$setup{key} $cfg='$fil': $!");
                } else {
                    push(@fil, Cwd::realpath($fil));
                }
            }
            @fil = unique(@fil);
        }

        foreach $top (@{$configs{$cfg}{srcroot}}) {
            foreach $fil (@fil) {
                if (! File::Spec->file_name_is_absolute($fil)) {
                    # This happens when no --systems-config=... is given,
                    # and the default has fallen through.  Look for a
                    # systems config file in the root of each source tree,
                    # which can apply to that build.
                    $fil = File::Spec->catdir($top, $fil);
                    if (! -f $fil || ! -r $fil) {
                        _error("$setup{msg} '$fil': $!");
                        next;
                    }
                    $fil = Cwd::realpath($fil);
                }
                push(@{$configs{$cfg}{$setup{fil}}{$top}}, $fil);
            }

            my $sys = "$setup{typ}"->new(@{$configs{$cfg}{$setup{fil}}{$top}});
            _warn($sys->warnings());
            if (! _error($sys->errors())) {
                $configs{$cfg}{$setup{tbl}}{$top} = $sys;
            }
        }
    }
}

sub resolve_systems_config () {
    _resolve_config (
        dfl => $systems_config,
        key => 'systems-config',
        fil => 'systems_config_file',
        tbl => 'systems_config_dict',
        msg => 'Target system config file',
        typ => 'Grace::Config::Systems',
    );
}

sub resolve_sysconf () {
    my (%cfg, $cfg);
    my (%sys, @sys, $sys);
    my ($top, @def, $tbl, $sub);

    if (defined($sys = $options{''}{sysconf})) {
        # --sysconf=sys...
        @def = unique(map { my @arr = @{$_}; splice(@arr, 1) } @{$sys});
    } else {
        @def = ( $sysconf );
    }

    foreach $cfg (keys(%configs)) {
        my %sys = ();
        if (defined($sys = $options{$cfg}{sysconf})) {
            @sys = unique(map { my @arr = @{$_}; splice(@arr, 1) } @{$sys});
        } else {
            @sys = @def;
        }

        $sys = $configs{$cfg}{systems_config_dict};
        foreach (@sys) {
            while (($top, $tbl) = each(%{$sys})) {
                if ($sub = $tbl->system($_)) {
                    $sys{$_}{$top} = $sub;
                }
            }
        }

        foreach (@sys) {
            if (! $sys{$_}) {
                _warn("Target platform '$_' unknown in configuration '$cfg'");
            }
        }
        if (! keys(%sys)) {
            _error("No target platforms matched in configuration '$cfg'");
            next;
        }

        $configs{$cfg}{sysconf} = \%sys;
    }
}

sub resolve_toolset_config () {
    _resolve_config (
        dfl => $toolset_config,
        key => 'toolset-config',
        fil => 'toolset_config_file',
        tbl => 'toolset_config_dict',
        msg => 'Target toolset config file',
        typ => 'Grace::Config::Toolset',
    );
}

# --toolset=set --toolset cfg/set --toolset sys=set --toolset cfg/sys=set
sub resolve_toolset () {

    # --toolset vs2015
    # --toolset linux_x86-32=gcc6
    # --toolset thistree/java-1.7 --toolset thattree/java-1.9
    # --toolset thistree/mac_x86-64=gcc --toolset thattree/mac_x86-64=clang

    my %cfg;
    my @set;
    my $set;

    # --toolset val...
    if (defined($set = $options{''}{toolset}{''})) {
        @set = unique(map { my @arr = @{$_}; splice(@arr, 1) } @{$set});
    } else {
        @set = ( $toolset );
    }
    $cfg{''} = \@set;

    my %sys;
    my $sys;
    # --toolset sys=val...
    while (($sys, $set) = each(%{$options{''}{toolset}})) {
        next if (! $sys);
        @set = unique(map { my @arr = @{$_}; splice(@arr, 1) } @{$set});
        $sys{''}{$sys} = \@set;
    }

    # --toolset cfg/val...
    foreach $cfg (grep { $_ } keys(%configs)) {
        @set = ();
        if (defined($set = $options{$cfg}{toolset}{''})) {
            @set = map { my @arr = @{$_}; splice(@arr, 1) } @{$set};
        }
        # Merge in root config's sysconf-less toolset list.
        @set = unique(@{$cfg{''}}, @set);
        $cfg{$cfg} = \@set;

        # --sysconf sys...
        # --sysconf cfg=sys...
        # ...
        # --toolset cfg/sys=val...
        foreach $sys (keys(%{$configs{$cfg}{sysconf}})) {
            @set = ();
            if (defined($set = $options{$cfg}{toolset}{$sys})) {
                @set = map { my @arr = @{$_}; splice(@arr, 1) } @{$set};
            }
            @set = unique(@{$sys{''}{$sys}}, @set);
            $sys{$cfg}{$sys} = \@set;
        }
    }

    my $top;
    my $tbl;
    my $sub;
    my %set;
    foreach $cfg (keys(%configs)) {
        while (($top, $tbl) = each(%{$configs{$cfg}{toolset_config_dict}})) {
            while (($sys, $set) = each(%{$sys{$cfg}})) {
                next if (! $configs{$cfg}{sysconf}{$sys}{$top});
                %set = ();
                foreach (@{$set}) {
                    if ($sub = $tbl->get($_)) {
                        $set{$_}{$top} = $sub;
                    } else {
                        _error(
                            sprintf("Toolset '$_' unknown in %s for %s",
                                    ($cfg ? "configuration '$cfg' at '$top'"
                                          : "root configuration at '$top'"),
                                    ($sys ? "system '$sys'" : "all systems")
                                   )
                        );
                    }
                }
                $configs{$cfg}{toolset}{$sys} = \%set;
            }
        }
    }
}

sub resolve_environ_config () {
    _resolve_config (
        dfl => $environ_config,
        key => 'environ-config',
        fil => 'environ_config_file',
        tbl => 'environ_config_dict',
        msg => 'Environment config file',
        typ => 'Grace::Config::Environ',
    );
}

sub _resolve_cmdflg (%) {
    my %setup = @_;

    my (@key, $key, $var, $dfl, $cfg, $val);

    $configs{''}{$setup{var}} = $setup{dfl};

    @key = ((ref($setup{key}) && (ref($setup{key}) eq 'ARRAY'))
            ? @{$setup{key}}
            : ( $setup{key} ));

    foreach $key (@key) {
        $val = ($key !~ m{^no-}o);
        if (defined($options{''}{$key})) {
            $configs{''}{$setup{var}} = $val;
        }
    }

    foreach $cfg (grep { $_ } keys(%configs)) {
        foreach $key (@key) {
            # Stow default value, ascertained above.
            $configs{$cfg}{$setup{var}} = $configs{''}{$setup{var}};

            # Set true or set false?
            $val = ($key !~ m{^no-}o);

            # If set in a named configuration, record that value.
            if (defined($options{$cfg}{$key})) {
                $configs{$cfg}{$setup{var}} = $val;
            }
        }
    }
}

sub resolve_flagset () {
    _resolve_cmdflg(
        key => 'empty-environ',
        var => 'nullenv',
        dfl => $nullenv,
    );
    _resolve_cmdflg(
        key => [ 'build', 'no-build' ],
        var => 'dobuild',
        dfl => $dobuild,
    );
    _resolve_cmdflg(
        key => [ 'keep-going', 'no-keep-going' ],
        var => 'dontdie',
        dfl => $dontdie,
    );
    _resolve_cmdflg(
        key => 'list-projects',
        var => 'list_projects',
        dfl => $list_projects,
    );
    _resolve_cmdflg(
        key => 'show-projects',
        var => 'show_projects',
        dfl => $show_projects,
    );
    _resolve_cmdflg(
        key => 'show-environ',
        var => 'show_environ',
        dfl => $show_environ,
    );
    _resolve_cmdflg(
        key => 'show-toolenv',
        var => 'show_toolenv',
        dfl => $show_toolenv,
    );
    _resolve_cmdflg(
        key => 'list-toolsets',
        var => 'list_toolsets',
        dfl => $list_toolsets,
    );
    _resolve_cmdflg(
        key => 'show-toolsets',
        var => 'show_toolsets',
        dfl => $show_toolsets,
    );
}

sub resolve_environ () {
    # Start out with an empty environment.  If someone hasn't said
    # "start all builds with an empty environment" (--empty-environ),
    # take a snapshot of the environment we were given.
    my %env;
    if (! $configs{''}{nullenv}) {
        %env = %ENV;
    }

    # Set variables in the base environment as specified on the command line.
    # --setenv var=val
    %env = ( %env, %{ ($options{''}{setenv} || ()) } );

    # Now, march through the established build configs applying settings.
    foreach my $cfg (keys(%configs)) {
        # Start out with an empty environment.  If a named configuration
        # has not set --empty-environ, inherit the global environment.
        my %sub;
        if (($cfg eq '') || ! $configs{$cfg}{nullenv}) {
            %sub = %env;
        }

        # Set variables in the configuration's environment as specified
        # on the command line.  We don't do this for the global config
        # in this loop, because it's already been done.
        if ($cfg ne '') {
            # --setenv config/var=val
            %sub = ( %sub, %{ ($options{$cfg}{setenv} || ()) } );
        }

        # Stow the resolved environment for each configuration.  These
        # are not the final environment settings used for running programs
        # for this configuration, but provide the base environment for
        # the --environ-config=... settings to scribble upon.  Those
        # settings are ActiveConfig, and so may not be completely evaluated
        # until after fork() (or the Win32 platform equivalent).  This makes
        # it necessary to ask the child spawner to feed back the final
        # environment used to run the tool, for auditing.
        $configs{$cfg}{environ} = \%sub;
    }
}

sub resolve_targets () {
}

sub resolve_product () {
}

sub resolve_lookups () {
}

sub resolve_setvars () {
}

sub resolve_nobuild () {
}

sub parse_options (@) {
    my ($unknown, $untaken, $errlist) = Grace::Options::parse(\@options, @_);

    push(@errlist, @{$errlist});

    print(STDERR
          map { "$program: Warning: Unknown option '$_'; Ignoring\n" }
            @{$unknown}
         );

    foreach (@{$untaken}) {
        my ($prj, $key, $aop, $val)
            = m{
                ^
                (((?:[^:?+=/]+|[:?+](?!=))+)/)?
                (((?:[^:?+=]+|[:?+](?!=))+)([:?+]?=))?
                (.*)
                $
               }xo;

        if ((defined($key) ? 1 : 0) ^ (defined($aop) ? 1 : 0)) {
            my $msg = sprintf("INTERNAL: K=%s, O=%s, V=%s",
                              _print($key), _print($aop), _print($val)
                             );
            _error($msg);
        }

        if (defined($key)) {
            _opt_dict('setvar', '+=', $_, []);
        } else {
            _opt_list('target', '+=', $_, []);
        }
    }

print(STDERR "resolve_srcroot()\n");
    resolve_srcroot();
print(STDERR "resolve_relpath()\n");
    resolve_relpath();
print(STDERR "resolve_outroot()\n");
    resolve_outroot();
print(STDERR "resolve_genroot()\n");
    resolve_genroot();
print(STDERR "resolve_pubroot()\n");
    resolve_pubroot();
print(STDERR "resolve_systems_config()\n");
    resolve_systems_config();
print(STDERR "resolve_sysconf()\n");
    resolve_sysconf();
#print(STDERR "resolve_toolset_config()\n");
#    resolve_toolset_config();
#print(STDERR "resolve_toolset()\n");
#    resolve_toolset();
#    resolve_environ_config();
    resolve_flagset();
    resolve_environ();
    resolve_product();
print(STDERR "resolve_lookups()\n");
    resolve_lookups();
    resolve_targets();
    resolve_setvars();
    resolve_nobuild();

    my $ostream = *STDOUT;

    if (@errlist) {
        $showhlp = 1;
        $ostream = *STDERR;
    }

    if ($showver) {
        print($ostream "$program: Version $version\n");
    }
    if ($showhlp) {
        print($ostream join("\n", Grace::Options::usage(\@options), ''));
    }

    if (@warning) {
        print(STDERR map { "$program: Warning: $_\n" } @warning);
    }
    if (@errlist) {
        print(STDERR map { "$program: Error: $_\n" } @errlist);
        exit 1;
    }

    if ($showhlp || ($showver && $nobuild)) {
        exit 0;
    }
}

sub spawn_configs ($) {
    my $conf = shift;
    return 1;
}

parse_options(@ARGV);

print(Dumper([ 'OPTIONS', \%options ],
             [ 'CONFIGS', \%configs ])); 

__DATA__
my %configs;
if (spawn_configs(\%configs)) {
    my %schedul = (
        nice => $nicelev,
        jobs => $numjobs,
        load => $loadavg,
    );
    if (my @schderr = Grace::Builder::schedule(\%schedul, values(%configs))) {
        print(STDERR map { "$program: INTERNAL: $_\n" } @schderr);
        exit 1;
    }
}

my $results = 0;
foreach my $prj (sort(keys(%builder))) {
    my $bld = $builder{$prj};

    my $res = $bld->result();
    my @err = $bld->errors();
    my @wrn = $bld->warnings();

    print(STDERR map { "PROJECT '$key': $_\n" } @wrn);
    print(STDERR map { "PROJECT '$key': $_\n" } @err);

    if (@err) {
        if ($res >= 0) {
            print(STDERR "PROJECT '$prj': Exited with status $res\n");
            $results += $res;
        } else {
            my $sig = $bld->signal();
            print(STDERR "PROJECT '$prj': Exited with signal $sig\n");
            $results += 1;
        }
    }
}

exit $results;
