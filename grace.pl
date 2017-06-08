#!/usr/bin/perl -w

#
# This script sets up a simultaneous multi-platform, multi-configuration,
# multi-rooted build.  The script parses and resolves command line options
# to configurations on multiple Grace builders bound to a common scheduler.
#

use Cwd            qw{realpath};
use File::Spec;
use Data::Dumper;

use Grace::Options qw{:OPT_};
use Grace::Utility qw{unique printdef};
use Grace::Paths;
use Grace::Builder::Grace;

my ($program)       = ((File::Spec->splitpath($0))[2] =~ m{^([^.]+)\..*$}o);
my  $version        = '0.0';
my  $cfgfile        = 'Gracefile';
my  $prjfile        = 'Graceproj';
my  $outroot        = ".$program/out";
my  $pubroot        = ".$program/pub";
my  $verbose        = 0;
my  $systems_config = 'systems.cfg';
my  $systems        = 'default';
my  $variant_config = 'variant.cfg';
my  $variant        = 'debug';
my  $toolset_config = 'toolset.cfg';
my  $toolset        = 'common';
my  $environ_config = 'environ.cfg';
my  @include        = ();

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
#   --systems foo=mac_x86-32   --systems bar=linux_x86-64,win_x86-64 \
#   --toolset foo=xcode-8.1    --toolset bar/linux_x86-64=gcc-6.2 \
#   --instrum foo=debug        --instrum bar=release \
#   --product foo=desktop      --product bar=auto,acr,gninternal \
#   --outroot foo=/tmp/foo-xyz --outroot bar=/tmp/bar-rel \
#   --pubroot=/tmp/merged # <-- publish to the same tree
#   --toolset=java-1.9 # <-- all builds use java-1.9
#   --toolset=gcc-3.2 # <-- all builds use gcc-3.2 (probably will not work...)
#

sub _opt_help ($$$$$);
sub _opt_vers ($$$$$);
sub _opt_jobs ($$$$$);
sub _opt_load ($$$$$);
sub _opt_nice ($$$$$);
sub _opt_incl ($$$$$);
sub _opt_flag ($$$$$);
sub _opt_list ($$$$$);
sub _opt_dict ($$$$$);
sub _opt_vars ($$$$$);

#my %aliases = (
#    src      => 'srcroot',
#    rel      => 'relpath',
#    out      => 'outroot',
#    pub      => 'pubroot',
#    platform => 'systems',
#);
    
my @options = (
    {
        name        => 'srcroot',
        long        => [ 'srcroot', 'src' ],
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ...=]PATH...',
        help        => 'Add a source tree pointed to by its root',
    }, {
        name        => 'relpath',
        long        => [ 'relpath', 'rel' ],
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ...=]PATH...',
        help        => 'Build targets under a relative path',
    }, {
        name        => 'outroot',
        long        => [ 'outroot', 'out' ],
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ...=]PATH',
        help        => 'Store generated sources, artifacts in this tree',
    }, {
        name        => 'pubroot',
        long        => [ 'pubroot', 'pub' ],
        long_hidden => 'publish',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ...=]PATH',
        help        => 'Publish packages to this directory tree',
    }, {
        name        => 'include',
        flag        => 'I',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ...=]PATH...',
        help        => 'Search these dirs for build configuration',
    }, {
        name        => 'systems',
        long        => [ 'systems', 'sys' ],
        long_hidden => 'platform',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ...=]ARCH...',
        help        => 'Configure for target platforms',
    }, {
        name        => 'subarch',
        type        => OPT_REQUIRED,
        func        => \&_opt_dict,
        args        => '[PROJ...::][NAME=]ARCH...',
        help        => 'Restrict fat sub-architectures',
    }, {
        name        => 'variant',
        type        => OPT_REQUIRED,
        func        => \&_opt_dict,
        args        => '[PROJ...::][TYPE=]NAME...',
        help        => 'Restrict build product variants',
    }, {
        name        => 'verbose',
        type        => OPT_REQUIRED,
        func        => \&_opt_dict,
        args        => '[PROJ...::]PART...[=LEVEL]',
        help        => 'Restrict build product variants',
    }, {
        name        => 'toolset',
        type        => OPT_REQUIRED,
        func        => \&_opt_dict,
        args        => '[PROJ...::][ARCH...=]TOOL...',
        help        => 'Force use of toolset TOOL',
    }, {
        name        => 'version',
        type        => OPT_UNWANTED,
        func        => \&_opt_vers,
        help        => 'Print version string',
    }, {
        name        => 'dontdie',
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
        help      => 'Start jobs when load average below X.Y (no arg => unset)',
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
        name        => 'setvar',
        type        => OPT_REQUIRED,
        func        => \&_opt_dict,
        args        => '[PROJ...::]NAME...=DATA...',
        help        => 'Set a build (not environment) variable',
    }, {
        name        => 'setenv',
        type        => OPT_REQUIRED,
        func        => \&_opt_vars,
        args        => '[PROJ...::]NAME...=DATA',
        help        => 'Set an environment (not build) variable',
    }, {
        name        => 'toolset-config',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ...=]FILE...',
        help        => 'Use toolset configuration file FILE',
    }, {
        name        => 'systems-config',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ...=]FILE...',
        help        => 'Use target platform configuration file FILE',
    }, {
        name        => 'empty-environ',
        type        => OPT_ATTACHED,
        func        => \&_opt_flag,
        args        => 'PROJ...',
        help        => 'Configure against an empty environment',
    }, {
        name        => 'environ-config',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ...=]FILE...',
        help        => 'Use environment configuration file FILE',
    }, {
        name        => 'list-toolsets',
        type        => OPT_ATTACHED,
        func        => \&_opt_flag,
        args        => 'PROJ...',
        help        => 'List available toolsets',
    }, {
        name        => 'show-toolsets',
        type        => OPT_ATTACHED,
        func        => \&_opt_flag,
        args        => 'PROJ...',
        help        => 'Show details about configured toolsets',
    }, {
        name        => 'show-toolset',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ...=]TOOL...',
        help        => 'Show details about toolset TOOL',
    }, {
        name        => 'show-toolenv',
        type        => OPT_ATTACHED,
        func        => \&_opt_flag,
        args        => 'PROJ...',
        help        => 'Show complete toolset environment',
    }, {
        name        => 'show-environ',
        type        => OPT_ATTACHED,
        func        => \&_opt_flag,
        args        => 'PROJ...',
        help        => 'Show complete environment',
    }, {
        name        => 'dobuild',
        long        => [ 'build', 'no-build' ],
        type        => OPT_ATTACHED,
        func        => \&_opt_flag,
        args        => 'PROJ...',
        help        => 'Build or do not build',
    }, {
        name        => 'target',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ...=]NAME...',
        help        => 'Build target NAME',
    }, {
        name        => 'list-projects',
        type        => OPT_ATTACHED,
        func        => \&_opt_flag,
        args        => 'PROJ...', 
        help        => 'List configured projects',
    }, {
        name        => 'show-projects',
        type        => OPT_ATTACHED,
        func        => \&_opt_flag,
        args        => 'PROJ...', 
        help        => 'Show details about configured projects',
    }, {
        name        => 'show-project',
        type        => OPT_REQUIRED,
        func        => \&_opt_flag,
        args        => 'PROJ...', 
        help        => 'Show details about project PROJ',
    }, {
        name        => 'search-alias',
        type        => OPT_REQUIRED,
        func        => \&_opt_dict,
        args        => '[PROJ...::]NAME...=PROJ',
        help        => 'Set project alias for resolving target searches',
    }, {
        name        => 'search-order',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ...=]PROJ...',
        help        => 'Set target origin search order',
    }, {
        name        => 'overlay',
        type        => OPT_REQUIRED,
        func        => \&_opt_list,
        args        => '[PROJ...=]NAME...',
        help        => 'Apply configuration overlays',
    },
);

my $_rex_int = qr{[+-]?\d+}o;
my $_rex_pos = qr{[+]?\d+}o;
my $_rex_flo = qr{[+]?(?:\d*\.\d+|\d+(?:\.\d+))(?:[Ee][+-]?\d+)?}o;
my $_rex_opt = qr{(?:(?>[^:?+=\\]+)|(?>[:?+](?!=))|\\.)+[:?+]?=}o;

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

sub _debug ($@) {
    my ($lvl, @msg) = @_;

    if ($lvl && ($verbose >= $lvl)) {
        print(map { "[DBG] $program: $_\n" } @msg);
    }
}

sub _opt_help ($$$$$) {
    $showhlp = 1;
    return 0;
}

sub _opt_vers ($$$$$) {
    $showver = 1;
    return 0;
}

sub _opt_jobs ($$$$$) {
    my ($handle, $opt, $aop, $arg, $vec) = @_;

    if (! defined($arg)) {
        # --jobs= or --jobs <end-of-args>
        $numjobs = undef;
        # Consume no args.
        return 0;
    } elsif (! $aop) {
        # --jobs something-that-might-be-relevant
        $arg = $vec->[0];
    }
    if (defined(my $val = _match($arg, $_rex_pos))) {
        $numjobs = $val;
        return ($aop ? 0 : 1);
    } elsif ($aop) {
        _error("Option '$opt': Argument must be integer");
    }
    return 0;
}

sub _opt_load ($$$$$) {
    my ($handle, $opt, $aop, $arg, $vec) = @_;
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

sub _opt_nice ($$$$$) {
    my ($handle, $opt, $aop, $arg, $vec) = @_;
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

sub _opt_flag ($$$$$) {
    my ($handle, $opt, $aop, $arg, $vec) = @_;

    my ($not) = ($opt =~ m{^(?:--?)?(no-)?(?:.+)$}o);
    $not = !! $not;

    my $nam = $handle->{name};

    my @cfg = Grace::Options::split($arg || '');
    if (! @cfg) {
        @cfg = ( '' );
    }

    foreach (@cfg) {
        push(@{$options{$_}{$nam}}, [ '=', $not ]);
    }

    return ($aop ? 0 : (defined($arg) ? 1 : 0));
}

sub _opt_list ($$$$$) {
    my ($handle, $opt, $aop, $arg, $vec) = @_;

    my $nam = (($handle && $handle->{name}) || $opt);

    my  @cfg;
    my ($cfg, $Aop, $val) =
        ($arg =~ m{^(?:((?>[^:?+=]+)|(?>[:?+](?!=))+)([:?+]?=))?(.*)$}o);

    if ($cfg) {
        @cfg = Grace::Options::split($cfg);
    } else {
        @cfg = ( '' );
    }

    if (! defined($Aop)) {
        $Aop = '+=';
    }

    my @val = Grace::Options::split($val || '');
    my $tbl;

    foreach $cfg (@cfg) {
        $tbl = ($options{$cfg} || ($options{$cfg} = {}));
        if (($Aop ne '?=') || ! defined($tbl->{$nam})) {
            push(@{$tbl->{$nam}}, [ (($Aop eq '+=') ? '+' : '='), @val ]);
        }
    }

    return ($aop ? 0 : 1);
}

sub __opt_dist {
    my ($handle, $opt, $aop, $arg, $vec, $fun) = @_;

    my $nam = (($handle && $handle->{name}) || $opt);

    my ($cfg, $key, $Aop, $val);

    ($cfg, $arg) = ($arg =~ m{^(?:((?:[^:?+=]+|[:?+](?![:=]))+)?::)?(.+)$}o);

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

    my @cfg;
    if ($cfg) {
        @cfg = Grace::Options::split($cfg);
    } else {
        @cfg = ( '' );
    }

    if (! $key) {
        $Aop = '+=';
        $key = '';
    }

    my @key = Grace::Options::split($key);
       @key = (@key ? @key : (''));
    my @val = &{$fun}(defined($val) ? $val : '');
    my $tbl;

    foreach $cfg (@cfg) {
        $tbl = ($options{$cfg} || ($options{$cfg} = {}));
        foreach $key (@key) {
            if (($Aop ne '?=') || ! defined($tbl->{$nam}->{$key})) {
                push(@{$tbl->{$nam}->{$key}},
                     [ (($Aop eq '+=') ? '+' : '='), @val ]);
            }
        }
    }

    return ($aop ? 0 : 1);
}

sub _opt_dict ($$$$$) {
    sub _split_settings ($) {
        return Grace::Options::split($_[0]);
    }
    return __opt_dist(@_, \&_split_settings);
}

sub _opt_vars ($$$$$) {
    sub _split_variable ($) {
        return ( $_[0] );
    }
    return __opt_dist(@_, \&_split_variable);
}

#
# resolve_verbose():
#
# Distribute verbosity settings to build configurations.  This is called
# right after command options are read and distributed.  This begins the
# effort to comprehend what those settings mean.
#
# # 'foo', 'bar', and 'baz' parts from every configuration will debug.
# --verbose foo            --> (global) foo=1
# --verbose foo,bar,baz    --> (global) foo=1, bar=1, baz=1
# --verbose foo=2,3,4      --> (global) foo=4
# --verbose foo,bar=0      --> (global) foo=0, bar=0
#
# # 'foo', 'bar', and 'baz' parts only from config 'cfg' will debug.
# --verbose cfg::foo,bar   --> (scoped) cfg::bar=1, cfg::baz=1
# --verbose cfg::bar,baz=3 --> (scoped) cfg::bar=3, cfg::baz=3
#
# # named configs inherit global config.
# --verbose=foo --verbose cfg::bar=3  --> cfg::foo=1, cfg::bar=3
#
sub resolve_verbose () {
    my (%cfg, $cfg, @sub, $sub, $lev);

    # --verbose=? --> --verbose foo=1
    @sub = @{ ($options{''}{verbose}{''} || []) };
    @sub = map { my @arr = @{$_}; splice(@arr, 1) } @sub;
    foreach $sub (@sub) {
        if ($sub =~ m{^$_rex_pos$}o) {
            $cfg{''}{$program} = int($sub);
        } else {
            $cfg{''}{$sub} = 1;
        }
    }

    # --verbose foo=?
    while (($sub, $lev) = each(%{$options{''}{verbose}})) {
        next if (! $sub);
        # Last setting wins.
        $cfg{''}{$sub} = (int($lev->[-1]->[-1]) || 0);
    }

    foreach $cfg (grep { $_ } keys(%options)) {
        # --verbose cfg::foo...
        @sub = @{ ($options{$cfg}{verbose}{''} || []) };
        @sub = map { my @arr = @{$_}; splice(@arr, 1) } @sub;
        map { $cfg{$cfg}{$_} = ($cfg{''}{$_} || 1) } @sub;

        # --verbose cfg::foo=?
        while (($sub, $lev) = each(%{ ($options{$cfg}{verbose} || {}) })) {
            next if (! $sub);
            # Last setting wins.
            $cfg{$cfg}{$sub} = (int($lev->[-1]->[-1]) || 0);
        }

        $configs{$cfg}{verbose} = $cfg{$cfg};
    }

    foreach $cfg (keys(%options)) {
        $configs{$cfg}{verbose} = $cfg{''};
    }

    $verbose = ($configs{''}{verbose}{$program} || 0);
}

sub _resolve_cmdflg (%) {
    my %setup = @_;

    my $fun = uc($setup{var});

    my (@key, $key, $var, $dfl, $cfg, $val);

    $configs{''}{$setup{var}} = $setup{dfl};
    _debug(1, "$fun: Default value: " . printdef($configs{''}{$setup{var}}));

    @key = ((ref($setup{key}) && (ref($setup{key}) eq 'ARRAY'))
            ? @{$setup{key}}
            : ( $setup{key} ));
    _debug(1, "$fun: Keys [ @key ]");

    foreach $key (@key) {
        $val = ($key !~ m{^no-}o);
        _debug(1, "$fun: Key '$key' --> Val: '$val'");
        if (defined($options{''}{$key})) {
            $configs{''}{$setup{var}} = $val;
        }
    }

    foreach $cfg (grep { $_ } keys(%options)) {
        foreach $key (@key) {
            # Stow default value, ascertained above.
            $configs{$cfg}{$setup{var}} = $configs{''}{$setup{var}};

            next if (! defined($options{$cfg}{$key}));

            # Set true or set false?
            $val = ($key !~ m{^no-}o);
            $configs{$cfg}{$setup{var}} = $val;
            _debug(1, "$fun: --$key $cfg=$val") ;
        }
    }
}

sub resolve_boolean () {
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
        _debug(2, "ENVIRON: Configured blank environment globally");
        %env = %ENV;
    }

    # Set variables in the base environment as specified on the command line.
    # --setenv var=val
    %env = ( %env, %{ ($options{''}{setenv} || {}) } );

    $configs{''}{environ} = \%env;

    # Now, march through the established build configs applying settings.
    foreach my $cfg (grep { $_ } keys(%options)) {
        # Set variables in the configuration's environment as specified
        # on the command line.
        my %sub = %{ ($options{$cfg}{setenv} || {}) };

        # If not configured for an empty environment, base a named
        # config on the (modified via --setenv) base environment, then
        # overlay the config-specific --setenv changes.
        %sub = ( ($options{$cfg}{nullenv} ? () : %env), %sub );

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

#
# resolve_srcroot():
#
# Determine whether a build should look for sources in a different directory
# than the one which would otherwise be automatically determined, based upon
# the current directory at the time of the issuance of the command.  If no
# paths are given, tries to locate the root of the source tree at or above
# the current directory.  Failing that, defaults to the current directory.
#
# --srcroot='/tmp/foo /tmp/bar' --> (global) srcroot=[ /tmp/foo, /tmp/bar ]
# --srcroot cfg=/tmp/baz        --> (scoped) cfg::srcroot=[ /tmp/baz ]
#
# --srcroot=/tmp/foo --srcroot cfg=/tmp/bar
#       --> All named configs which do not have their own srcroot settings
#           inherit the global settings.
#
sub resolve_srcroot () {
    my (%dir, @dir, $dir);
    my (@top, $top, $cfg);
    my (%fil, $fil);
    my $raw;
    my $vol;
    my $cwd = Cwd::realpath(Cwd::cwd());

    _debug(2, "SRCROOT: Current directory: '$cwd'");

    # Determine whether any source roots were mentioned on the command line.
    if (defined($dir = $options{''}{srcroot})) {
        @dir = map { my @arr = @{$_}; splice(@arr, 1) } @{$dir};
        foreach $raw (@dir) {
            _debug(2, "SRCROOT: --srcroot='$raw'");
            if (! File::Spec->file_name_is_absolute($raw)) {
                $dir = File::Spec->catdir($cwd, $raw);
            } else {
                $dir = $raw;
            }
            _debug(2, "SRCROOT: Look for dir '$dir'");
            if (! defined($dir = Cwd::realpath($dir)) || ! -d $dir) {
                _debug(2, "SRCROOT: Failed real path: " . printdef($dir));
                _error("--srcroot: File '$raw': $!");
                next;
            }
            push(@top, $dir);
            _debug(2, "SRCROOT: Add srcroot '$dir'");
        }
        @top = unique(@top);
    }

    if (@top) {
        _debug(1, "SRCROOT: Configured globally: [ @top ]");
    } else {
        _debug(2, "SRCROOT: No configured global srcroots; scan up");
        _debug(2, "SRCROOT: Seek highest '$cfgfile' and '$prjfile'");

        my %cfg = Grace::Paths::find_highest($cwd, $cfgfile, $prjfile);
        foreach (keys(%cfg)) {
            _debug(2, "SRCROOT: Found '$_' at '$cfg{$_}'");
        }
        foreach $dir (values(%cfg)) {
            ($vol, $dir, undef) = File::Spec->splitpath($dir);
            $dir = File::Spec->catpath($vol, $dir, '');
            push(@top, $dir);
        }
        $top = (sort(@top))[0];

        if (! defined($top)) {
            $top = $cwd;
        }
        $top = File::Spec->canonpath($top);
        @top = ( $top );

        _debug(1, "SRCROOT: Found root dir '$top'");
    }

    $configs{''}{srcroot} = \@top;

    foreach $cfg (grep { $_ } keys(%options)) {
        _debug(2, "SRCROOT: Named configuration '$cfg'");

        if (! defined($dir = $options{$cfg}{srcroot})) {
            _debug(2, "SRCROOT: No configured srcroots for '$cfg'");
            _debug(2, "SRCROOT: Inherit global srcroots");
            $configs{$cfg}{srcroot} = \@top;
        } else {
            @dir = (@dir, map { my @arr = @{$_}; splice(@arr, 1) } @{$dir});
            my @sub;
            foreach my $raw (@dir) {
                _debug(2, "SRCROOT: --srcroot $cfg='$raw'");
                if (! File::Spec->file_name_is_absolute($raw)) {
                    $dir = File::Spec->catdir($cwd, $raw);
                } else {
                    $dir = $raw;
                }
                _debug(2, "SRCROOT: Look for dir '$dir'");
                if (! defined($dir = Cwd::realpath($dir)) || ! -d $dir) {
                    _debug(2, "SRCROOT: Failed real path: " . printdef($dir));
                    _error("--srcroot: File '$raw': $!");
                    next;
                }
                _debug(2, "SRCROOT: Add srcroot '$dir' for '$cfg'");
                push(@sub, $dir);
            }
            # If explicitly configured, force dirs into named config.
            @dir = ($options{''}{srcroot} ? @top : ());
            @sub = unique(@dir, @sub);
            $configs{$cfg}{srcroot} = \@sub;
        }
        _debug(2, "SRCROOT: $cfg source roots: [@{$configs{$cfg}{srcroot}}]");
    }
}

#
# resolve_relpath():
#
# Determine whether a relative path within a source tree was specified or,
# if a build is started from within a source tree, at what relative path
# the build was started from.  This will allow us to restrict the targets
# built to the subset that a developer would find most intuitive.  A
# production build of a full tree would likely be providing all the path
# particulars, anyway, and may be started from outside the source tree.
#
# --relpath foo/bar
# --relpath cfg=foo/baz,oof/zab
#
sub resolve_relpath () {
    my (@rel, $rel);
    my (@dir, $dir);
    my (%top, $top);
    my (%cfg, $cfg);

    my $cwd = Cwd::realpath(Cwd::cwd());

    _debug(1, "RELPATH: Current directory: '$cwd'");
    if (defined($dir = $options{''}{relpath})) {
        @rel = map { my @arr = @{$_}; splice(@arr, 1) } @{$dir};
        _debug(2, "RELPATH: Configured global relpaths: [ @rel ]");
    } else {
        @rel = ( $cwd );
        _debug(2, "RELPATH: No configured global relpaths: use '$cwd'");
    }

    $cfg{''} = \@rel;

    foreach $cfg (keys(%options)) {
        if ($cfg) {
            _debug(2, "RELPATH: Named configuration '$cfg'");
        } else {
            _debug(2, "RELPATH: Global configuration");
        }

        if (defined($dir = $options{$cfg}{relpath})) {
            @dir = map { my @arr = @{$_}; splice(@arr, 1) } @{$dir};
            _debug(2, "RELPATH: Relative paths for '$cfg': [ @dir ]");
        } else {
            @dir = @rel;
            _debug(2, "RELPATH: No configured relative paths; inherit global");
        }

        foreach $top (@{$configs{$cfg}{srcroot}}) {
            my %sub = Grace::Paths::exists_below($top, @dir);
            my @arr = unique(grep { defined } values(%sub));
            if (! @arr) {
                @arr = ( File::Spec->curdir() );
            }
            _debug(2, "RELPATH: Inside '$top':", map { "RELPATH: '$_'" } @arr);
            $configs{$cfg}{relpath}{$top} = \@arr;
        }
    }
}

sub _resolve_outdir ($$) {
    my ($key, $sub) = @_;

    my $fun = uc($key);
    my $cwd = Cwd::realpath(Cwd::cwd());

    _debug(1, "$fun: Current directory: '$cwd'");

    my ($dir, $raw, $top, $cfg, $src, $out);

    if (defined($dir = $options{''}{$key})) {
        # $dir = [ [ '+', dir, dir, ... ], ... ].
        # Last one wins.
        $raw = $dir->[-1]->[-1];
        if (! File::Spec->file_name_is_absolute($raw)) {
            $top = File::Spec->canonpath(File::Spec->catdir($cwd, $raw));
            _debug(2, "$fun: --$key='$raw': Not absolute");
        } else {
            $top = $raw;
            _debug(2, "$fun: --$key='$raw': Specified absolute");
        }
        _debug(2, "$fun: Canonical path: '$top'");
        # If we specify --outroot=/tmp/foo, we want all configs to build
        # there.  If we specify --outroot=foo, we still want all configs
        # to build to the directory specified ($PWD/foo).  We resolve this
        # to an absolute path, which will cause all configurations to use
        # the same dir.  Otherwise ...
    } else {
        # If --outroot=... is left unspecified, generate a subdir of each
        # srcroot.  Targets will resolve across different artifact caches.
        $top = eval "\$$key";
        _debug(2, "$fun: Default $key: '$top'");
    }

    foreach $cfg (keys(%options)) {
        _debug(2, sprintf("$fun: Configure for %s", ($cfg || 'DEFAULT')));

        if (defined($dir = $options{$cfg}{$key})) {
            # Specifying an outroot for a specific configuration causes
            # that configuration to resolve its own outroot.  Last one wins.
            $raw = $dir->[-1]->[-1];
            _debug(2, sprintf("$fun: --$key%s='$raw'", ($cfg ? " $cfg" : '')));
            if (! File::Spec->file_name_is_absolute($raw)) {
                $dir = File::Spec->catdir($cwd, $raw);
                _debug(2, "$fun: Not absolute; resolved: '$dir'");
            } else {
                $dir = $raw;
                _debug(2, "$fun: Absolute");
            }
        } else {
            # Otherwise, accept the default.
            $dir = $top;
            _debug(2, "$fun: Use default $key: '$dir'");
        }

        foreach $src (@{$configs{$cfg}{srcroot}}) {
            _debug(2, sprintf("$fun: %s srcroot: '$src'", ($cfg || 'DEFAULT')));
            if (! File::Spec->file_name_is_absolute($dir)) {
                $out = File::Spec->catdir($src, $dir, ($sub ? $cfg : ''));
                _debug(2, "$fun: Not absolute; resolved: '$out'");
            } else {
                $out = File::Spec->catdir($dir, ($sub ? $cfg : ''));
            }
            $out = File::Spec->canonpath($out);
            _debug(2, "$fun: Canonical: '$out'");
            $configs{$cfg}{$key}{$src} = $out;
        }
    }
}

sub resolve_outroot () {
    _resolve_outdir('outroot', 1);
}

sub resolve_pubroot () {
    _resolve_outdir('pubroot', 0);
}

sub resolve_include () {
    # --include dir...
    my (@inc, $inc, @raw, $raw, $cfg, @sub);

    my $cwd = Cwd::realpath(Cwd::cwd());
    _debug(2, "INCLUDE: Current directory: '$cwd'");

    @raw = @{ ($options{''}{include} || []) };
    @raw = map { my @arr = @{$_}; splice(@arr, 1) } @raw;
    foreach $raw (@raw) {
        _debug(2, "INCLUDE: Inspect '$raw'");
        if (! File::Spec->file_name_is_absolute($raw)) {
            $inc = File::Spec->catdir($cwd, $raw);
            _debug(2, "INCLUDE: Not absolute");
        }
        _debug(2, "INCLUDE: Look for '$inc' to exist");
        if (! defined($inc = Cwd::realpath($inc)) || ! -d $inc) {
            _debug(2, "INCLUDE: Path '$raw': $!");
        } else {
            push(@inc, $inc);
        }
    }

    $configs{''}{include} = \@inc;

    foreach $cfg (grep { $_ } keys(%options)) {
        @sub = ();
        @raw = @{ ($options{$cfg}{include} || []) };
        @raw = map { my @arr = @{$_}; splice(@arr, 1) } @raw;
        foreach $raw (@raw) {
            if (! File::Spec->file_name_is_absolute($raw)) {
                $inc = File::Spec->catdir($cwd, $raw);
                _debug(2, "INCLUDE: Not absolute");
            } else {
                $inc = $raw;
            }
            _debug(2, "INCLUDE: Look for '$inc' to exist");
            if (! defined($inc = Cwd::realpath($inc)) || ! -d $inc) {
                _debug(2, "INCLUDE: Path '$raw': $!");
            } else {
                push(@sub, $inc);
            }
        }
        $configs{$cfg}{include} = [ unique(@inc, @sub) ];
    }
}

sub resolve_overlay () {
    my ($cfg, $ovl, @ovl);

    @ovl = @{ ($options{''}{overlay} || []) };
    @ovl = unique(map { my @arr = @{$_}; splice(@arr, 1) } @ovl);
    $configs{''}{overlay} = \@ovl;
    _debug(1, "OVERLAY: Apply overlays globally: [ @ovl ]");

    foreach $cfg (grep { $_ } keys(%options)) {
        my @sub = @{ ($options{$cfg}{overlay} || []) };
           @sub = map { my @arr = @{$_}; splice(@arr, 1) } @sub;
           @sub = unique(@ovl, @sub);
        $configs{$cfg}{overlay} = \@sub;
        _debug(1, "OVERLAY: Apply overlays to config '$cfg': [ @sub ]");
    }
}

sub resolve_setvars () {
    my %var = %{ $options{''}{setvar} || {} };
    my $cfg;

    $configs{''}{setvar} = \%var;
    _debug(1, "SETVARS: Set globally: [ " . join(' ', keys(%var)) . " ]");

    foreach $cfg (grep { $_ } keys(%options)) {
        $configs{$cfg}{setvar} = { %var, %{ ($options{$cfg}{setvar} || {}) } };
        my $msg = join(' ', keys(%{$configs{$cfg}{setvar}}));
        _debug(1, "SETVARS: Set for config '$cfg': [ $msg ]");
    }
}

sub resolve_targets () {
    my (@tgt, $tgt, $cfg);

    if (defined($tgt = $options{''}{target})) {
        @tgt = unique(map { my @arr = @{$_}; splice(@arr, 1) } @{$tgt});
        $configs{''}{target} = \@tgt;
        _debug(1, "TARGETS: Specified globally: [ @tgt ]");
    }

    foreach $cfg (grep { $_ } keys(%options)) {
        my @sub = @{ ($options{$cfg}{target} || []) };
        _debug(1, "TARGETS: Specified for config '$cfg': [ @sub ]");
        @sub = unique(@tgt, @sub);
        $configs{$cfg}{target} = \@sub;
        _debug(1, "TARGETS: Config '$cfg' gets [ @sub ]");
    }
}

sub resolve_lookups () {
    my %alias;
    my %group;
    my %order;

    my (@ord, %tbl, $ali, $nam, $cfg, @sub);

    # --search-order=cfg...
    @ord = unique(
        map { my @arr = @{$_}; splice(@arr, 1) }
            @{ ($options{''}{'search-order'} || []) }
    );
    $order{''} = \@ord;
    _debug(2, "LOOKUPS: Global lookup order: [ @ord ]");
    
    # --search-alias nam=cfg
    %tbl = %{ ($options{''}{'search-alias'} || {}) };
    while (($ali, $nam) = each(%tbl)) {
        next if (! $ali);
        # Last one wins.
        $alias{''}{$ali} = $nam->[-1]->[-1];
    }
    _debug(2, "LOOKUPS: Global aliases:",
           map { "LOOKUPS: Alias '$_' = '" . $alias{''}{$_} . "'" }
               sort(keys(%{$alias{''}}))
          );

    $configs{''}{search_order} = $order{''};
    $configs{''}{search_alias} = $alias{''};

    foreach $cfg (grep { $_ } keys(%options)) {
        _debug(2, "LOOKUPS: Resolve named config '$cfg'");

        # --search-order cfg=cfg...
        @sub = @{ ($options{$cfg}{'search-order'} || []) };
        @sub = map { my @arr = @{$_}; splice(@arr, 1) } @sub;
        $order{$cfg} = [ unique(@ord, @sub) ];
        _debug(2, "LOOKUPS: Order for config '$cfg': [ @{$order{$cfg}} ]");

        # --search-alias cfg/nam=cfg
        %tbl = %{ ($options{$cfg}{'search-alias'} || {}) };
        while (($ali, $nam) = each(%tbl)) {
            # Last one wins.
            $alias{$cfg}{$ali} = $nam->[-1]->[-1];
        }
        $alias{$cfg} = { %{$alias{''}}, %{ ($alias{$cfg} || {}) } };
        _debug(2, "LOOKUPS: Aliases for config '$cfg':",
               map { "LOOKUPS: Alias '$_' = '$alias{$cfg}{$_}'" }
                   sort(keys(%{$alias{$cfg}}))
              );
    }

    foreach $cfg (keys(%options)) {
        $configs{$cfg}{search_order} = $order{$cfg};
        $configs{$cfg}{search_alias} = $alias{$cfg};
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
    _debug(2, "VARIANT: Undimensioned global variants: [ @var ]");

    # --variant dim=var...
    %tbl = %{ ($options{''}{variant} || {}) };
    while (($dim, $var) = each(%tbl)) {
        next if (! $dim);
        my @var = unique(map { my @arr = @{$_}; splice(@arr, 1) } @{$var});
        $dim{''}{$dim} = \@var;
        _debug(2, "VARIANT: Global '$dim' variants: [ @var ]");
    }

    # --variant cfg::var...
    foreach $cfg (grep { $_ } keys(%options)) {
        my @var = ();
        if (defined($var = $options{$cfg}{variant}{''})) {
            @var = map { my @arr = @{$_}; splice(@arr, 1) } @{$var};
        }
        # Merge in root config's dimension-less variant list.
        @var = unique(@{ ($cfg{''} || []) }, @var);
        $cfg{$cfg} = \@var;
        _debug(2, "VARIANT: Undimensioned variants for '$cfg': [ @var ]");
    }

    # --variant cfg::dim=var...
    foreach $cfg (grep { $_ } keys(%options)) {
        %tbl = (%{ $dim{''} || {} }, %{ ($options{$cfg}{variant} || {}) });
        while (($dim, $var) = each(%tbl)) {
            next if (! $dim);
            my @var = ();
            if (defined($var = $options{$cfg}{variant}{$dim})) {
                @var = map { my @arr = @{$_}; splice(@arr, 1) } @{$var};
            }
            # Merge in root config's dimensioned variants.
            @var = unique(@{ ($dim{''}{$dim} || []) }, @var);
            $dim{$cfg}{$dim} = \@var;
            _debug(2, "VARIANT: '$dim' variants for '$cfg': [ @var ]");
        }
    }

    # Assign to configuration.
    foreach $cfg (keys(%options)) {
        $configs{$cfg}{variant} = {
            %{ ($dim{$cfg} || {}) },
            ($cfg{$cfg} ? ('' => $cfg{$cfg}) : ()),
        };
    }
}

sub resolve_systems () {
    my (%cfg, $cfg);
    my (%sys, $sys);
    my ($top, @def, $tbl, $sub);
    my ($arr, $aop);

    # Build default systems list.
    if (! defined($sys = $options{''}{systems})) {
        @def = split(m{[\s,]+}o, $systems);
        _debug(2, "SYSTEMS: Use default: '$systems'");
    } else {
        # --systems=sys...
        @def = unique(map { my @arr = @{$_}; splice(@arr, 1) } @{$sys});
        _debug(2, "SYSTEMS: Specified globally: [ @def ]");
    }

    $configs{''}{systems} = \@def;

    # Create system config list for named configurations.
    foreach $cfg (grep { $_ } keys(%options)) {
        my @sys;
        if (! defined($sys = $options{$cfg}{systems})) {
            _debug(2, "SYSTEMS: No systems specified for $cfg config");
            @sys = @def;
        } else {
            _debug(2, "SYSTEMS: Systems specified for $cfg config");
            @sys = (@def, map { my @arr = @{$_}; splice(@arr, 1) } @{$sys});
            @sys = unique(@sys);
        }
        $configs{$cfg}{systems} = \@sys;
        _debug(2, "SYSTEMS: Configured for $cfg config: [ @sys ]");
    }
}

sub resolve_subarch () {
    my (%cfg, $cfg, @sub, $sub, $sys);

    # --subarch=foo --> --subarch foo=1
    @sub = @{ ($options{''}{subarch}{''} || []) };
    @sub = unique(map { my @arr = @{$_}; splice(@arr, 1) } @sub);
    _debug(2, "SUBARCH: Restrict subarches globally to [@sub]");
    foreach $sub (@sub) {
        $cfg{''}{''}{$sub} = 1;
    }

    # --subarch sys=sub
    while (($sys, $sub) = each(%{$options{''}{subarch}})) {
        next if (! $sys);
        @sub = map { my @arr = @{$_}; splice(@arr, 1) } @{$sub};
        @sub = unique(@sub, keys(%{$cfg{''}{''}}));
        _debug(2, "SUBARCH: Restrict subarches globally"
                . " for system $sys to [@sub]");
        foreach $sub (@sub) {
            $cfg{''}{$sys}{$sub} = 1;
        }
    }

    $configs{''}{subarch}{''} = $cfg{''};

    foreach $cfg (grep { $_ } keys(%options)) {
        # --subarch cfg::sub...
        @sub = @{ ($options{$cfg}{subarch}{''} || []) };
        @sub = map { my @arr = @{$_}; splice(@arr, 1) } @sub;
        @sub = unique(@sub, keys(%{$cfg{''}{''}}));
        _debug(2, "SUBARCH: Restrict subarches for config $cfg to [@sub]");
        foreach $sub (@sub) {
            $cfg{$cfg}{''}{$sub} = 1;
        }

        # --subarch cfg::sys=sub...
        while (($sys, $sub) = each(%{ ($options{$cfg}{subarch} || {}) })) {
            next if (! $sys);
            @sub = map { my @arr = @{$_}; splice(@arr, 1) } @{$sub};
            @sub = unique(@sub, keys(%{$cfg{$cfg}{''}}));
            _debug(2, "SUBARCH: Restrict subarches for"
                    . " config $cfg for system $sys to [@sub]");
            map { $cfg{$cfg}{$sys}{$_} = 1 } @sub;
        }

        $configs{$cfg}{subarch} = $cfg{$cfg};
    }
}

# --toolset=set --toolset cfg/set --toolset sys=set --toolset cfg/sys=set
sub resolve_toolset () {
    # --toolset vs2015
    # --toolset linux_x86-32=gcc6
    # --toolset thistree::java-1.7 --toolset thattree::java-1.9
    # --toolset thistree::mac_x86-64=gcc --toolset thattree::mac_x86-64=clang

    my (%cfg, $cfg);
    my $set;

    # --toolset val...
    my @glo;
    if (defined($set = $options{''}{toolset}{''})) {
        @glo = unique(map { my @arr = @{$_}; splice(@arr, 1) } @{$set});
        _debug(2, "TOOLSET: --toolset " . join(',', @glo));
    } else {
        @glo = ( $toolset );
    }
    $cfg{''}{''} = \@glo;
    _debug(2, "TOOLSET: Baseline toolsets: [ @glo ]");

    my $sys;
    # --toolset sys=val...
    while (($sys, $set) = each(%{$options{''}{toolset}})) {
        next if (! $sys);
        my @set = map { my @arr = @{$_}; splice(@arr, 1) } @{$set};
           @set = unique(@glo, @set);
        $cfg{''}{$sys} = \@set;
        _debug(2, "TOOLSET: --toolset $sys=[ @set ]");
    }

    # --toolset cfg::val...
    foreach $cfg (grep { $_ } keys(%options)) {
        my @set;
        if (defined($set = $options{$cfg}{toolset}{''})) {
            @set = map { my @arr = @{$_}; splice(@arr, 1) } @{$set};
        }
        # Merge in root config's systems-less toolset list.
        @set = unique(@{ ($cfg{''}{''} || []) }, @set);
        $cfg{$cfg}{''} = \@set;
        _debug(1, "TOOLSET: All systems in config '$cfg' use: [ @set ]");
        _debug(1, "TOOLSET: --toolset ${cfg}::" . join(',', @set));

        # --systems sys...
        # --systems cfg=sys...
        # ...
        # --toolset cfg::sys=val...
        foreach $sys (keys(%{ $options{$cfg}{systems} || {} })) {
            @set = ();
            if (defined($set = $options{$cfg}{toolset}{$sys})) {
                @set = map { my @arr = @{$_}; splice(@arr, 1) } @{$set};
                _debug(1, "TOOLSET: --toolset '$cfg::$sys='");
                my $msg = "'$sys' in config '$cfg': [ @set ]";
                _debug(1, "TOOLSET: Specified for $msg");
            }
            @set = unique(@{ ($cfg{''}{$sys} || []) }, @set);
            $cfg{$cfg}{$sys} = \@set;
            _debug(1, "TOOLSET: System '$sys' in config '$cfg' uses: [ @set ]");
        }
    }

    foreach $cfg (keys(%options)) {
        $configs{$cfg}{toolset} = $cfg{$cfg};

        _debug(2, sprintf("TOOLSET: %s config:", ($cfg ? "'$cfg'" : 'Default')),
               map {
                    sprintf("TOOLSET: %s: [ @{$configs{$cfg}{toolset}{$_}} ]",
                            ($cfg ? "Config '$cfg'": 'Default config'))
               } sort(keys(%{$configs{$cfg}{toolset}}))
              );
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
            FILE: foreach $fil (@fil) {
                if (! File::Spec->file_name_is_absolute($fil)) {
                    # This happens when no --systems-config=... is given,
                    # and the default has fallen through.  Look for a
                    # systems config file in the root of each source tree,
                    # which can apply to that build.
                    foreach $dir (@{$configs{$cfg}{include}}, $top) {
                        my $tst = File::Spec->catdir($dir, $fil);
                        next if (! -f $tst || ! -r $tst);
                        $tst = Cwd::realpath($tst);
                        push(@{$configs{$cfg}{$setup{fil}}{$top}}, $tst);
                        next FILE;
                    }
                }
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
            _opt_dict(undef, 'setvar', '+=', $_, []);
        } else {
            _opt_list(undef, 'target', '+=', $_, []);
        }
    }

    resolve_verbose(); # This goes first, so other resolvers can _debug().
    resolve_boolean();
    resolve_environ(); # Must be after resolve_boolean().
    resolve_srcroot();
    resolve_relpath();
    resolve_outroot();
    resolve_pubroot();
    resolve_include();
    resolve_overlay();
    resolve_setvars();
    resolve_targets();
    resolve_lookups();
    resolve_variant();
    resolve_systems();
    resolve_subarch();
    resolve_toolset();
    resolve_systems_config();
#    resolve_toolset_config();
#    resolve_environ_config();
#    resolve_variant_config();

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
    my (%cfg, @cfg, $cfg, $dir, %bld);

    # If there are named configs, configure those.
    if (! (@cfg = grep { $_ } keys(%configs))) {
        # Otherwise, configure the unnamed (global) config.
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
                    $configs{$cfg}{environ_config_file}{$dir},
                variant_config_file =>
                    $configs{$cfg}{variant_config_file}{$dir},
            );

            $bld{$cfg}{$dir} = Grace::Builder::Grace->new(%cfg);
        }
    }

    return %bld;
}

parse_options(@ARGV);
create_builders();

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
