#!/usr/bin/perl -w

#
# This script sets up a simultaneous multi-platform, multi-configuration,
# multi-rooted build.  The script parses and resolves command line options
# to configurations on multiple Grace builders bound to a common scheduler.
#

use Cwd;
use File::Spec;
use Data::Dumper;

use Grace::Options           qw{:OPT_};
use Grace::Utility           qw{unique printdef};
use Grace::Paths;
use Grace::Config::Systems;
#use Grace::Config::Toolset;
#use Grace::Config::Environ;
#use Grace::Config::Variant;

my  $program        = (File::Spec->splitpath($0))[2];
my  $version        = '0.0';
my  $cfgfile        = 'Graceconf';
my  $prjfile        = 'Graceproj';
my  $optfile        = 'Graceopts';
my  $outroot        = 'out';
my  $pubroot        = 'pub';
my  $verbose        = '';
my  $systems_config = 'systems.cfg';
my  $systems        = 'default';
my  $variant_config = 'variant.cfg';
my  $variant        = 'debug';
my  $toolset_config = 'toolset.cfg';
my  $toolset        = 'common';
my  $environ_config = 'environ.cfg';

# Basic default variant set.  Customized in variant.cfg for complex builds.
my  %variant = (
    overlay => {
        strict  => { },
    },
    variant => {
        # Keys here describe variant dimensions.
        sysconf => {
        },
        instrum => {
            lint    => { },
            debug   => { },
            release => { },
            profile => { },
            dbginfo => { },
        },
    },
    outtree => sub {
        eval '$instrum/$sysconf'
            . (eval '$subarch' ? eval '/fat/$subarch' : '')
            . ((eval '$srcpath' !~ m{^(?:\.|/+)?$}o) ? eval '/$srcpath' : '');
    },
    objtree => sub {
        eval 'obj/$objcode'
            . ((eval '$relpath' !~ m{^(?:\.|/+)?$}o) ? eval '/$relpath' : '');
    },
    tgttree => sub {
        eval 'tgt/$tgttype/$tgtcode/$tgtstem'
    },
);

my  %options;
my  %configs;
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
        help        => 'Store generated sources, artifacts in this tree',
    }, {
        long        => [ 'pubroot', 'pub', ],
        long_hidden => 'publish',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ=]PATH',
        help        => 'Publish packages to this directory tree',
    }, {
        long        => 'include-dir',
        flag        => 'I',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ=]PATH...',
        help        => 'Search these dirs for build configuration',
    }, {
        long        => [ 'sysconf', 'sys', ],
        long_hidden => 'platform',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ=]ARCH...',
        help        => 'Configure for target platforms',
    }, {
        long        => 'variant',
        type        => OPT_REQUIRED,
        func        => \&_opt_dict,
        args        => [ '[[PROJ/]TYPE=]NAME...', '[PROJ/]NAME...' ],
        help        => 'Restrict build product variants',
    }, {
        long        => 'verbose',
        type        => OPT_REQUIRED,
        func        => \&_opt_dict,
        args        => [ '[PROJ/]PART=LEVEL', '[PROJ/]PART...' ],
        help        => 'Restrict build product variants',
    }, {
        long        => 'toolset',
        type        => OPT_REQUIRED,
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
        args        => '[PROJ+=]PROJ...',
        help        => 'Set target origin search order',
    }, {
        long        => 'search-group',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ/]NAME=PROJ...',
        help        => 'Cluster projects together in search order',
    }, {
        long        => 'overlay',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ+=]NAME...',
        help        => 'Apply configuration overlays',
    },
);

my $_rex_int = qr{[+-]?\d+};
my $_rex_pos = qr{[+]?\d+};
my $_rex_flo = qr{[+-]?(?:\d*\.\d+|\d+(?:\.\d+))(?:[Ee][+-]?\d+)?};

sub _error (@) {
    push(@errlist, @_);
    return scalar(@_);
}

sub _warn (@) {
    push(@warning, @_);
    return scalar(@_);
}

sub _match ($$) {
    my ($arg, $rex) = @_;

    if ($arg =~ qr{^$rex$}) {
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

    my ($cfg, $Aop, $val) =
        ($arg =~ m{^(?:((?:(?>[^:?+=]+)|(?>[:?+](?!=)))+)?([:?+]?=))?(.*)$}o);
    if (! defined($cfg)) {
        $cfg = '';
    }
    if (! defined($Aop)) {
        $Aop = '+=';
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

    ($key, $Aop, $val) =
        ($arg =~ m{^(?:((?:[^:?+=]+|[:?+](?!=))+)?([:?+]?=))?(.*)$}o);

    if ((defined($key) ? 1 : 0) ^ (defined($Aop) ? 1 : 0)) {
        my $msg = sprintf("INTERNAL: C=%s, K=%s, A=%s, V=%s",
                          printdef($cfg), printdef($key),
                          printdef($Aop), printdef($val)
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

    my @key = Grace::Options::split($key);
       @key = (@key ? @key : (''));
    my @val = &{$fun}(defined($val) ? $val : '');
    my $tbl;

    $tbl = ($options{$cfg} || ($options{$cfg} = {}));

    foreach $key (@key) {
        if (($Aop ne '?=') || ! defined($tbl->{$nam}->{$key})) {
            if ($Aop eq '+=') {
                push(@{$tbl->{$nam}->{$key}}, [ '+', @val ]);
            } else {
                push(@{$tbl->{$nam}->{$key}}, [ '=', @val ]);
            }
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

sub resolve_pubroot () {
    _resolve_outdir('pubroot');
}

sub resolve_include () {
    # --include-dir dir...
    my ($inc, @inc, @def, $cfg);

    if (defined($inc = $options{''}{'include-dir'})) {
        @def = ();
        foreach $inc (map { my @arr = @{$_}; splice(@arr, 1) } @{$inc}) {
            if (! File::Spec->file_name_is_absolute($inc)) {
                $inc = File::Spec->catdir(Cwd::cwd(), $inc);
            }
            push(@def, Cwd::realpath($inc));
        }
        $configs{''}{include} = \@def;
    }

    foreach $cfg (grep { $_ } keys(%configs)) {
        @inc = ();
        if (defined($inc = $options{$cfg}{'include-dir'})) {
            foreach $inc (map { my @arr = @{$_}; splice(@arr, 1) } @{$inc}) {
                if (! File::Spec->file_name_is_absolute($inc)) {
                    $inc = File::Spec->catdir(Cwd::cwd(), $inc);
                }
                push(@inc, Cwd::realpath($inc));
            }
        }
        @inc = unique(@def, @inc);
        $configs{$cfg}{include} = \@inc;
    }
}

sub resolve_systems () {
    my (%cfg, $cfg);
    my (%sys, @sys, $sys);
    my ($top, @def, $tbl, $sub);
    my ($arr, $aop);

    # Build default systems list.
    if (! defined($sys = $options{''}{sysconf})) {
        @def = ( $systems );
    } else {
        # --sysconf=sys...
        foreach $arr (@{$sys}) {
            $aop = shift(@{$arr});
            if ($aop eq '+') {
                push(@def, @{$arr});
            } else {
                @def = ( @{$arr} );
            }
        }
        @def = unique(@def);
    }

    # Create system config list for named configurations.
    foreach $cfg (keys(%configs)) {
        if (! defined($sys = $options{$cfg}{sysconf})) {
            @sys = @def;
        } else {
            @sys = ();
            foreach $arr (@{$sys}) {
                $aop = shift(@{$arr});
                if ($aop eq '+') {
                    push(@sys, @{$arr});
                } else {
                    @sys = @{$arr};
                }
            }
        }
        $configs{$cfg}{sysconf} = [ unique(@sys) ];
    }
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
    %env = ( %env, %{ ($options{''}{setenv} || {}) } );

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
            %sub = ( %sub, %{ ($options{$cfg}{setenv} || {}) } );
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

sub resolve_setvars () {
    my %var = (defined($options{''}{setvar}) ? %{$options{''}{setvar}} : ());
    my $cfg;

    foreach $cfg (keys(%configs)) {
        my %sub;

        if (defined($options{$cfg}{setvar})) {
            %sub = %{$options{$cfg}{setvar}};
        }
        %sub = ( %var, %sub );

        $configs{$cfg}{setvar} = \%sub;
    }
}

sub resolve_targets () {
    my (@tgt, $tgt, $cfg);

    if (defined($tgt = $options{''}{target})) {
        @tgt = unique(map { my @arr = @{$_}; splice(@arr, 1) } @{$tgt});
    }

    foreach $cfg (keys(%configs)) {
        my @sub = unique(@tgt, @{($options{$cfg}{target} || [])});
        $configs{$cfg}{target} = \@sub;
    }
}

sub resolve_variant () {
    my (%cfg, $cfg);
    my (%dim, $dim);
    my (@var, $var);
    my %tbl;

    # --variant var...
    @var = ();
    if (defined($var = $options{''}{variant}{''})) {
        @var = unique(map { my @arr = @{$_}; splice(@arr, 1) } @{$var});
    }
    $cfg{''} = \@var;

    # --variant dim=var...
    %tbl = %{ ($options{''}{variant} || {}) };
    while (($dim, $var) = each(%tbl)) {
        next if (! $dim);
        my @var = unique(map { my @arr = @{$_}; splice(@arr, 1) } @{$var});
        $dim{''}{$dim} = \@var;
    }

    # --variant cfg/var...
    foreach $cfg (grep { $_ } keys(%configs)) {
        my @var = ();
        if (defined($var = $options{$cfg}{variant}{''})) {
            @var = map { my @arr = @{$_}; splice(@arr, 1) } @{$var};
        }
        # Merge in root config's dimension-less variant list.
        @var = unique(@{ ($cfg{''} || []) }, @var);
        $cfg{$cfg} = \@var;
    }

    # --variant cfg/dim=var...
    foreach $cfg (grep { $_ } keys(%configs)) {
        %tbl = (%{$dim{''}}, %{ ($options{$cfg}{variant} || {}) });
        while (($dim, $var) = each(%tbl)) {
            next if (! $dim);
            my @var = ();
            if (defined($var = $options{$cfg}{variant}{$dim})) {
                @var = map { my @arr = @{$_}; splice(@arr, 1) } @{$var};
            }
            # Merge in root config's dimensioned variants.
            @var = unique(@{ ($dim{''}{$dim} || []) }, @var);
            $dim{$cfg}{$dim} = \@var;
        }
    }

    # Assign to configuration.
    foreach $cfg (keys(%configs)) {
        $configs{$cfg}{variant} = {
            %{ ($dim{$cfg} || {}) },
            ($cfg{$cfg} ? ('' => $cfg{$cfg}) : ()),
        };
    }
}

sub resolve_lookups () {
    my %alias;
    my %group;
    my %order;

    my ($nam, $aop, $grp, $ali, $cfg, @grp, %tbl);

    # --search-group grp=nam...
    %tbl = %{ ($options{''}{'search-group'} || {}) };
    while (($grp, $nam) = each(%tbl)) {
        @grp = @{$grp};
        $aop = shift(@grp);
        if ($aop eq '+') {
            unshift(@grp, @{ ($group{''}{$nam} || []) });
        }
        $group{''}{$nam} = [ unique(@grp) ];
    }

    # --search-order=cfg...
    @grp = ();
    foreach $grp (@{ ($options{''}{'search-order'} || []) }) {
        @grp = @{$grp};
        $aop = shift(@$grp);
        if ($aop eq '+') {
            unshift(@grp, @{ ($order{''} || []) });
        }
    }
    $order{''} = [ unique(@grp) ];

    # --search-alias nam=cfg
    %tbl = %{ ($options{''}{'search-alias'} || {}) };
    while (($ali, $nam) = each(%tbl)) {
        # Last one wins.
        $alias{''}{$ali} = $nam->[-1]->[-1];
    }

    foreach $cfg (grep { $_ } keys(%configs)) {
        # --search-group cfg/grp=cfg...
        %tbl = %{ ($options{$cfg}{'search-group'} || {}) };
        while (($nam, $grp) = each(%tbl)) {
            @grp = @{ ($group{''}{$nam} || []) };
            foreach $grp (@{$grp}) {
                $aop = shift(@{$grp});
                if ($aop eq '+') {
                    push(@grp, @{$grp});
                } else {
                    @grp = @{$grp};
                }
            }
            $group{$cfg}{$nam} = [ unique(@grp) ];
        }

        # --search-order cfg/cfg...
        @grp = ( @{ ($order{''} || []) } );
        foreach $grp (@{ ($options{$cfg}{'search-order'} || []) }) {
            $aop = shift(@{$grp});
            if ($aop eq '+') {
                push(@grp, @{$grp});
            } else {
                @grp = @{$grp};
            }
        }
        $order{$cfg} = [ unique(@grp) ];

        # --search-alias cfg/nam=cfg
        $alias{$cfg} = { %{ ($alias{''} || {}) } };
        %tbl = %{ ($options{$cfg}{'search-alias'} || {}) };
        while (($ali, $nam) = each(%tbl)) {
            # Last one wins.
            $alias{$cfg}{$ali} = $nam->[-1]->[-1];
        }
    }

    foreach $cfg (keys(%configs)) {
        $configs{$cfg}{search_order} = $order{$cfg};
        $configs{$cfg}{search_alias} = $alias{$cfg};
        $configs{$cfg}{search_group} = $group{$cfg};
    }
}

sub resolve_verbose () {
    my (%cfg, $cfg, @sub, $sub, $lev);

    # --verbose=foo --> --verbose foo=1
    @sub = @{ ($options{''}{verbose}{''} || []) };
    @sub = map { my @arr = @{$_}; splice(@arr, 1) } @sub;
    foreach $sub (@sub) {
        $cfg{''}{$sub} = 1;
    }

    # --verbose foo=?
    while (($sub, $lev) = each(%{$options{''}{verbose}})) {
        # Last setting wins.
        $cfg{''}{$sub} = $lev->[-1]->[-1];
    }

    foreach $cfg (grep { $_ } keys(%configs)) {
        # --verbose cfg/foo...
        @sub = @{ ($options{$cfg}{verbose}{''} || []) };
        @sub = map { my @arr = @{$_}; splice(@arr, 1) } @sub;
        $cfg{$cfg} = { %{ $cfg{''} || {} } };
        foreach $sub (@sub) {
            if (! defined($cfg{$cfg}{$sub})) {
                $cfg{$cfg}{$sub} = 1;
            }
        }

        # --verbose cfg/foo=?
        while (($sub, $lev) = each(%{$options{$cfg}{verbose}})) {
            next if (! $sub);
            # Last setting wins.
            $cfg{$cfg}{$sub} = $lev->[-1]->[-1];
        }
    }

    foreach $cfg (keys(%configs)) {
        $configs{$cfg}{verbose} = $cfg{$cfg};
    }
}

sub resolve_overlay () {
    my ($cfg, $ovl, @ovl);

    @ovl = @{ ($options{''}{overlay} || []) };
    @ovl = unique(map { my @arr = @{$_}; splice(@arr, 1) } @ovl);
    $configs{''}{overlay} = \@ovl;

    foreach $cfg (grep { $_ } keys(%configs)) {
        my @sub = @{ ($options{$cfg}{overlay} || []) };
           @sub = map { my @arr = @{$_}; splice(@arr, 1) } @sub;
           @sub = unique(@ovl, @sub);
        $configs{$cfg}{overlay} = \@sub;
    }
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
        }
    }
}

sub resolve_systems_config () {
    _resolve_config (
        dfl => $systems_config,
        key => 'systems-config',
        fil => 'systems_config_file',
        msg => 'Target system config file',
    );
}

sub resolve_toolset_config () {
    _resolve_config (
        dfl => $toolset_config,
        key => 'toolset-config',
        fil => 'toolset_config_file',
        msg => 'Target toolset config file',
    );
}

sub resolve_environ_config () {
    _resolve_config (
        dfl => $environ_config,
        key => 'environ-config',
        fil => 'environ_config_file',
        msg => 'Environment config file',
    );
}

sub resolve_variant_config () {
    _resolve_config (
        dfl => $variant_config,
        key => 'variant-config',
        fil => 'variant_config_file',
        msg => 'Variant config file',
    );
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
                              printdef($key), printdef($aop), printdef($val)
                             );
            _error($msg);
        }

        if (defined($key)) {
            _opt_dict('setvar', '+=', $_, []);
        } else {
            _opt_list('target', '+=', $_, []);
        }
    }

    resolve_srcroot();
    resolve_relpath();
    resolve_outroot();
    resolve_pubroot();
    resolve_include();
    resolve_flagset();
    resolve_systems();
    resolve_toolset();
    resolve_environ();
    resolve_variant();
    resolve_overlay();
    resolve_setvars();
    resolve_targets();
    resolve_lookups();
    resolve_verbose();
    resolve_systems_config();
    resolve_toolset_config();
    resolve_environ_config();
    resolve_variant_config();

    my $ostream = STDOUT;

    if (@errlist) {
        $showhlp = 1;
        $ostream = STDERR;
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

sub create_builders () {
    my (%cfg, @cfg, $cfg, $dir, %bld, $bld);

    if (! (@cfg = grep { $_ } keys(%configs))) {
        @cfg = keys(%configs);
    }

    foreach $cfg (@cfg) {
        foreach $dir (@{$configs{$cfg}{srcroot}}) {
            %cfg = (
                %{$configs{$cfg}},
                cfgname => $cfg,
                srcroot => $dir,
                relpath => $configs{$cfg}{relpath}{$dir},
                outroot => $configs{$cfg}{outroot}{$dir},
                pubroot => $configs{$cfg}{pubroot}{$dir},
                systems_config_file =>
                    $configs{$cfg}{systems_config_file}{$dir},
                toolset_config_file =>
                    $configs{$cfg}{toolset_config_file}{$dir},
                environ_config_file =>
                    $configs{$cfg}{toolset_config_file}{$dir},
                variant_config_file =>
                    $configs{$cfg}{variant_config_file}{$dir},
            );

            $bld = Grace::Builder::Grace->new(%cfg);

            $bld{$cfg}{$dir} = $bld;
        }
    }
}

parse_options(@ARGV);

print(Dumper([ 'OPTIONS', \%options ],
             [ 'CONFIGS', \%configs ])); 

__DATA__
if (create_builders()) {
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
