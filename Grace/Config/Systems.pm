package Grace::Config::Systems;

use strict;
use warnings;

use Clone                qw{clone};
use Data::Dumper;
use Scalar::Util         qw{weaken};

use parent 'Grace::Config';

use Grace::Utility       qw{unique};
use Grace::ActiveConfig;

$Data::Dumper::Indent=1;

sub _closure ($$) {
    our ($bldr, $from) = @_;

    our @work = ();
    our @errs = ();
    our @warn = ();
    our %keep = ();
    our %done = ();
    our %fail = ();
    our %loop = ();
    our %phat = ();
    our %list = ();
    our @path = ();

    # Inject an error into the configuration.
    sub _error (@) {
        my $head = "Config '" . join('->', @path) . "'";
        push(@errs, map { $_ } map { "$head: $_" } @_);
        return 1;
    }

    sub _group (@);
    sub _trace ($);
    sub _close;

    sub _trace ($) {
        my $name = shift;
        my $fail = 0;
        my $data;
        my @list;

        if ($fail{$name}) {
            return ();
        } elsif (defined($data = $done{$name})) {
            return @{$data};
        } elsif ($loop{$name}) {
            $fail{$name} = _error("Config '$name' is config-looped");
            return ();
        } elsif (! defined($data = $from->{$name})) {
            $fail{$name} = _error("Config '$name' is not present");
            return ();
        }

        $loop{$name} = 1;
        push(@path, $name);
        if (! ref($data)) {
            if (! (@list = _trace($data))) {
                $fail{$name} = _error("Aliased by config '$name'");
            }
        } elsif (ref($data) eq 'ARRAY') {
            if (! (@list = _group($data))) {
                $fail{$name} = _error("Grouped by config '$name'");
            }
        } elsif (ref($data) eq 'HASH') {
            if (! (@list = _close($data, $name))) {
                $fail{$name} = _error("Could not configure '$name'");
            } else {
                # Record the configuration's override sysconf.
                my $conf = $data->{sysconf};

                foreach $data (@list) {
                    #
                    # If this is a configurable system name, ensure that
                    # it is carrying an appropriate sysconf and syspath values.
                    #
                    if ($data->{sysarch}
                     || $data->{fatarch}
                     || $data->{syslist})
                    {
                        $data->{sysconf} = ($conf || $name);
                    }
                }
            }
        } else {
            $fail{$name} = _error("Config '$name' must be string,"
                                . " an array of strings, or a hash");
        }
        pop(@path);
        $loop{$name} = 0;

        if ($fail{$name}) {
            return ();
        }

        $done{$name} = \@list;

        # Determine whether to keep a configuration.
        my $keep = 1;
        foreach $data (@list) {
            if (! $data->{sysconf}) {
                $keep = 0;
                last;
            }
        }
        if ($keep) {
            $keep{$name} = \@list;
        }

        return @list;
    }

    sub _group (@) {
        my @data = @_;
        my $fail = 0;
        my @rslt;

        for (my $indx = 0; $indx < @data; ) {
            my $item = $data[$indx];
            my @part;
            if (! ref($item)) {
                push(@path, "[$indx]");
                @part = _trace($item);
                pop(@path);
            } elsif (ref($item) eq 'HASH') {
                push(@path, "[$indx]");
                @part = _close($item);
                pop(@path);
            } elsif (ref($item) eq 'ARRAY') {
                splice(@data, $indx, 1, @{$item});
                next;
            } else {
                $fail = _error("Unknown type: " . ref($item));
            }
            if (! @part) {
                $fail = _error("From LIST[$indx]");
            } else {
                push(@rslt, @part);
            }
            ++$indx;
        }
        return ($fail ? () : unique(@rslt));
    }

    sub _fatarch ($) {
        my $conf = shift;
        my $arch = $conf->{fatarch};
        my $fail = 0;

        #
        # Sub-architectures are marked with a subarch field by this function.
        # When we process fat sub-architectures from the work queue, the
        # fat architecture might have inherited a fatarch field from its
        # outer configuration.  We therefore only work through unmarked
        # configurations.
        #
        if ($conf->{subarch}) {
            return 0; # success = no failure.
        }

        my @arch;
        my %arch;
        if (! ref($arch)) {
            @arch = ( $arch );
        } elsif (ref($arch) eq 'ARRAY') {
            @arch = @{$arch};
        } elsif (ref($arch) eq 'HASH') {
            %arch = %{$arch};
        } else {
            $fail = _error("Fatarch: Unknown type: " . ref($arch));
        }

        for (my $indx = 0; $indx < @arch; ) {
            if (! ref($arch = $arch[$indx])) {
                $arch{$arch} = {};
            } elsif (ref($arch) eq 'HASH') {
                #
                # Name the subarchitecture, for path generation, etc.
                # Prefer subarch, then sysarch, or make something up.
                #
                my $name = (
                    $arch->{subarch} || $arch->{sysarch} || "subarch$indx"
                );
                $arch{$name} = $arch;
            } elsif (ref($arch[$indx]) eq 'ARRAY') {
                # Flatten out embedded lists...
                splice(@arch, $indx, 1, @{$arch[$indx]});
                next;
            } else {
                $fail = _error(
                    "Fatarch: LIST[$indx]: Unknown type: " . ref($arch[$indx])
                );
            }
            ++$indx;
        }

        @arch = ();
        while (my ($name, $data) = each(%arch)) {
            $phat{$data} = {
                name => $name,
                conf => $conf,
                arch => $data,
            };
            if (! $data->{subarch}) {
                $data->{subarch} = $name;
            }
            my $inht;
            if (! ($inht = $data->{inherit})) {
                $inht = [       ];
            } elsif (! ref($inht) || (ref($inht) ne 'ARRAY')) {
                $inht = [ $inht ];
            }
            $data->{inherit} = [ @{$inht}, $conf ];

            push(@arch, $data);
        }

        if (! $fail) {
            $conf->{fatarch} = \%arch;
            push(@work, @arch);
        }

        return $fail;
    }

    sub _syslist ($) {
        my $conf = shift;
        my $fail = 0;
        my $list;

        if (! ref($conf->{syslist})) {
            $list = [ $conf->{syslist} ];
        } elsif (ref($conf->{syslist}) eq 'ARRAY') {
            map { if (ref($_)) { $fail = 1; } } @{$conf->{syslist}};
            if ($fail) {
                _error("Syslist entry must be a plain string");
            } else {
                $list = $conf->{syslist};
            }
        } else {
            $fail = _error("Syslist must be plain string or array of strings");
        }

        if (! $fail) {
            $list{$conf} = {
                conf => $conf,
                list => $list,
            };
        }

        return $fail;
    }

    #
    # Resolve inheritance for a configuration, clip target architecture
    # configurations (i.e., (sysarch || subarch) > fatarch > syslist),
    # ...
    #
    sub _close {
        my $data = shift;
        my $name = shift;
        my $fail = 0;

        # Track down the inheritance chain and stack up a group of configs.
        my @inht;
        if (defined($data->{inherit})) {
            @inht = _group($data->{inherit});
        }
        # Merge the inherited configurations and the current configuration.
        my $conf = Grace::Config::merge_data(@inht, $data);
        #
        # Finalized configurations do not retain an inherit field,
        # as those configurations have just been merged.
        #
        delete($conf->{inherit});

        #
        # If sysarch is present, this configuration is a final,
        # single-architecture platform.  If subarch is present, this
        # configuration is a generated sub-architecture configuration
        # for an overarching fat platform.  In both cases, prune any
        # fatarch or syslist fields.  They are not relevant, and would
        # cause infinite recursion if not pruned.
        #
        if ($conf->{sysarch} || $conf->{subarch}) {
            delete($conf->{fatarch});
            delete($conf->{syslist});
        }

        if (! $name) {
            if (my $phat = $phat{$data}) {
                #
                # If this configuration is tagged as a fat sub-architecture,
                # then stow the completed configuration for final linking.
                #
                $phat{$conf} = {
                    %{$phat},
                    arch => $conf,
                };
                #
                # Once the fat configuration is finalized, don't do that
                # again for this raw config reference.
                #
                delete($phat{$data});
            }
        } elsif (defined($conf->{fatarch})) {
            #
            # If this is a fat architecture container, prune an
            # irrelevant (possibly inherited) syslist field.  This
            # will help us to avoid infinite recursion.  Then,
            # inject partially-configured fat subarchitectures onto
            # the work queue for later completion.
            #
            delete($conf->{syslist});
            if (_fatarch($conf)) {
                $fail = _error("Fatarch configuration");
            }
        } elsif (defined($conf->{syslist})) {
            #
            # A syslist field causes this configuration to finalize
            # the same way as a config defined with an [ array ].
            # This field allows a configuration to both act as a
            # source of inherited configuration and also as a logical
            # name for a group of independent platforms.  Consider a
            # platform like 'qnx', which can group the build of several
            # architectures of QNX with the same toolchain, sharing
            # a single environment and resources also defined in a
            # 'qnx' named configuration.
            #
            if (_syslist($conf)) {
                $fail = _error("Syslist configuration");
            }
        }

        return ($fail ? () : ( $conf ));
    }

    #
    # Start with the set of system names in the configuration, and
    # run until the work queue is empty.  The subroutines in this
    # closure will stick fat sub-architectures on the work queue, and
    # this loop schedules their resolution, too.
    #
    my $fail = 0;
    for (@work = keys(%{$from}); @work; ) {
        my $item = shift(@work);
        if (! ref($item)) {
            # A plain string.  Treat as an alias, and trace the reference.
            if (! _trace($item)) {
                # No configurations returned, and errors already logged.
                $fail = 1;
            }
        } elsif (ref($item) eq 'HASH') {
            # An actual configuration, used when resolving fatarches.
            if (! _close($item)) {
                $fail = _error("Failed to configure fatarch");
            }
        } else {
            # Nothing else should ever show up here.
            $fail = _error("Unknown type: " . ref($item));
        }
    }

    #
    # As the subroutines work, fat architectures might be encountered
    # (that is, those whose final configurations contain 'fatarch').
    # Linkage info is stashed until all the systems are resolved, then
    # references to fat architectures are linked into the config.
    # This deferred linkage makes avoiding recursion simpler (possible).
    #
    while (my ($phat, $data) = each(%phat)) {
        my $name = $data->{name};
        my $conf = $data->{conf};
        my $arch = $data->{arch};

        if (ref($conf->{fatarch}) ne 'HASH') {
            $conf->{fatarch} = {};
        }
        $conf->{fatarch}->{$name} = $arch;
    }

    #
    # System configurations may alternatively be tagged with a 'syslist'
    # field, which causes the configuration name to show up in the final
    # configuration as a list of finished configurations, rather than as
    # an incomplete configuration.
    #
    while (my ($list, $data) = each(%list)) {
        my $conf = $data->{conf};
        $keep{$conf->{sysconf}} = [ _group($data->{list}) ];
    }

    #
    # Turn this configuration into an active config (that is, one where
    # fetching a value stored as CODE will call that code and provide
    # it the builder's context).
    #
    my @pass_errs = @errs;
    my @pass_warn = @warn;
    my $pass_conf = Grace::ActiveConfig::activate(\%keep);

    # Clear these so the values don't persist.
    @errs = ();
    @warn = ();
    %done = ();
    %keep = ();
    %fail = ();
    %loop = ();
    %phat = ();
    %list = ();
    @path = ();

    return ($pass_conf, \@pass_errs, \@pass_warn);
}

sub new {
    my ($what, $bldr, @file) = @_;

    my $self = $what->SUPER::new($bldr, @file);

    my ($data, $errs, $warn) = _closure($bldr, $self->{_data_});

    $bldr->warning(@{$warn});
    $bldr->error(@{$errs});

    if (! @{$errs}) {
        $self->{_data_} = $data;
    }

    return $self;
}

sub system {
    return $_[0]->{_data_}->{$_[1]};
}

sub default {
    return $_[0]->system('default');
}

sub native {
    return $_[0]->system('native');
}

1;
