use strict;
use warnings;

package Grace::Config::Platform;

use parent 'Grace::Config';

use Grace::Utility       qw{unique};
use Grace::ActiveConfig;
use Grace::Platform;

#use Data::Dumper;
#$Data::Dumper::Indent = 1;
#$Data::Dumper::Purity = 1;
#$Data::Dumper::Trailingcomma = 1;
#$Data::Dumper::Sortkeys = 1;

sub _compile ($$) {
    our ($seed, $self) = @_;
    our $from = $self->{_data_};

    our @work = ();
    our %keep = ();
    our %done = ();
    our %fail = ();
    our %loop = ();
    our %fats = ();
    our %list = ();
    our @path = ();
    our %seed = ();

    # Inject an error into the configuration.
    sub _error (@) {
        my $head = (@path ? "Config '" . join('->', @path) . "': " : '');
        $self->error(map { print(STDERR "_ERROR: $head$_\n"); "$head$_" } @_);
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
                $fail{$name} = _error("Failed to trace config '$data'");
            }
        } elsif (ref($data) eq 'ARRAY') {
            if (! (@list = _group($data))) {
                $fail{$name} = _error("Failed to resolve system list");
            }
        } elsif (ref($data) eq 'HASH') {
            if (! (@list = _close($data, $name))) {
                $fail{$name} = _error("Failed to resolve config");
            }
        } else {
            $fail{$name} = _error(
                "Config '$name' must be string,"
              . " an array of strings, or a hash"
            );
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
            if (! $data->{subarch}
             && ! $data->{sysarch}
             && ! $data->{fatarch}
             && ! $data->{syslist})
            {
                $keep = 0;
                last;
            }
        }
        if ($keep) {
            if (@list == 1) {
                $keep{$name} = $list[0];
            } else {
                $keep{$name} = \@list;
            }
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
        if (! ref($arch) || (ref($arch) eq 'ARRAY')) {
            @arch = ( $arch );
        } elsif (ref($arch) eq 'HASH') {
            %arch = %{$arch};
        } else {
            $fail = _error("Fatarch: Unknown type: " . ref($arch));
        }

        #
        # If data was a string or list of strings, load up the named arch
        # hash, which is then unloaded.  Otherwise, we were given a hash
        # already keyed by subarch names.  If neither is true, then @arch
        # will be empty and so will %arch, so we fall through with a type
        # error.
        #
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
            } elsif (ref($arch) eq 'ARRAY') {
                # Flatten out embedded lists...
                splice(@arch, $indx, 1, @{$arch});
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
            my %data = %{$data};

            $fats{\%data} = {
                name => $name,
                conf => $conf,
                arch => \%data,
            };
            if (! $data{subarch}) {
                $data{subarch} = $name;
            }

            $data{inherit} = [
                grep { $_ } (($data->{inherit} || undef), $conf)
            ];

            push(@arch, \%data);
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
        my $list = $conf->{syslist};

        if (! ref($list)) {
            $list = [ $list ];
        } elsif (ref($list) eq 'ARRAY') {
            map { if (ref($_)) { $fail = 1; } } @{$list};
            if ($fail) {
                _error("Syslist entry must be a plain string");
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

        # Determine how this configuration must be finalized.
        if ($conf->{subarch}) {
            #
            # subarch is inserted by _fatarch() when the enclosing fat
            # platform container is encountered.  If we see it in a config,
            # then we get rid of the other finalizers.  A fat subarch
            # (building as a fat subarch) will not have a sysarch setting,
            # but will carry the platform discriminator on its subarch
            # setting.  A fat subarch is a single system configuration,
            # with no further platform nesting, so get rid of any
            # (probably inherited) fatarch and syslist finalizers.
            #
            delete($conf->{sysarch});
            delete($conf->{fatarch});
            delete($conf->{syslist});
        } elsif ($conf->{sysarch}) {
            #
            # sysarch presence marks this config as a thin, single-arch
            # configuration.  Drop fatarch and syslist finalizers, to
            # avoid confusion (and recursion).  fatarch and syslist
            # configs may end up using these configurations.
            #
            delete($conf->{fatarch});
            delete($conf->{syslist});
        } elsif ($conf->{fatarch}) {
            #
            # The presence of fatarch marks this config as a container
            # whose configurations are inherited by its subarchitectures
            # (except where the subarch holds a builtas setting), and
            # whose subarchitectures are built before fat target processing
            # makes use of the subarchitectures built.
            #
            delete($conf->{syslist});
        } elsif ($conf->{syslist}) {
            # 
            # The syslist finalizer makes it possible for this config to
            # both provide heritable settings and to show up in the final
            # configuration as a list of platforms aliased by this name.
            #
        }

        if (! $name) {
            #
            # An unnamed configuration passed in for finishing up is
            # almost certainly a fat subarchitecture.
            #
            if (my $fats = $fats{$data}) {
                #
                # If this configuration is tagged as a fat sub-architecture,
                # then stow the completed configuration for final linking.
                #
                $fats{$conf} = {
                    %{$fats},
                    arch => $conf,
                };
                #
                # Once the fat configuration is finalized, don't do that
                # again for this raw config reference.
                #
                delete($fats{$data});
            }
        } elsif ($conf->{fatarch}) {
            #
            # Inject partially-configured fat subarchitectures onto
            # the work queue for later completion.
            #
            if (_fatarch($conf)) {
                $fail = _error("Fatarch configuration");
            }
        } elsif ($conf->{syslist}) {
            #
            # A syslist or builtas field causes this configuration to
            # finalize the same way as a config defined with an [ array ].
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

        if ($fail) {
            return ();
        }

        # Tag the (mostly) finished configuration with a system name.
        $conf->{sysname} = (
            $conf->{sysname}
              || (Grace::Platform::split($name || $conf->{sysconf})->{sysname})
        );

        # Tag the (mostly) finished configuration with its name.
        $conf->{sysconf} = (
            $data->{sysconf}
              || $name  # The name given when closing this config.
              #
              # If neither of the above are set, make something up.
              # Most likely used to generate a fat sub-arch config name,
              # which will be used for placing compiled objects.  Makes
              # a particular sub-architecture selectable from the cmdline.
              #
              || ((! $conf->{subarch} && ! $conf->{sysarch})
                  ? $conf->{sysname}
                  : ($conf->{subarch}
                     ? join('/fat/', $conf->{sysname}, $conf->{subarch})
                     : join('_',     $conf->{sysname}, $conf->{sysarch})
                    )
                 )
        );

        return ( $conf );
    }

    sub _collate () {
        my %name;
        my %conf;

        my $bldr = $self->builder();

        # Do thin platforms first, delaying fatarch and syslist configs.
        while (my ($name, $conf) = each(%keep)) {
            # Skip array refs, fatarch containers, and already-done hashes.
            next if (ref($conf) ne 'HASH');
            next if ($conf->{fatarch});
            if ($conf{$conf}) {
                $name{$name} = $conf{$conf};
                next;
            }

            # Create a Platform.
            if (my $plat = Grace::Platform->new(%{$conf}, builder => $bldr)) {
                $conf{$conf} = $plat;
                $name{$name} = $plat;
            } else {
                _error("Failed to create configuration '$name'");
            }
        }

        #
        # Now, collate fatarch configs, creating Platforms for non-builtas
        # sub-architectures, keeping Platforms already created for builtas
        # sub-architectures, and finally creating a Platform for the fatarch
        # container itself, with sub-architectures already being completed
        # Platform objects.
        #
        while (my ($name, $conf) = each(%keep)) {
            next if ((ref($conf) ne 'HASH') || ! $conf->{fatarch});

            my %fat;
            while (my ($sub, $cfg) = each(%{$conf->{fatarch}})) {
                my $sys;
                if ($cfg->{builtas}) {
                    $sys = $name{$cfg->{builtas}};
                } else {
                    $sys = Grace::Platform->new(
                        %{$cfg}, builder => $self->builder(),
                    );
                }
                $fat{$sub} = $sys;
            }
            my $plat = Grace::Platform->new(
                %{$conf},
                fatarch => \%fat,
                builder => $bldr,
            );
            if ($plat && ! $plat->errors()) {
                $conf{$conf} = $plat;
                $name{$name} = $plat;
            }
        }

        #
        # Then, collate syslist configs.  These are stored in %keep as
        # array references, and may name fat architectures.
        #
        while (my ($name, $conf) = each(%keep)) {
            next if (ref($conf) ne 'ARRAY');

            my @list;
            foreach my $cfg (@{$conf}) {
                my $plat;
                if (! ($plat = $conf{$cfg})) {
                    $plat = Grace::Platform->new(
                        %{$cfg},
                        builder => $bldr,
                    );
                    if (! $plat->errors()) {
                        $conf{$cfg} = $plat;
                        $plat       = undef;
                    }
                }
                if ($plat) {
                    push(@list, $plat);
                }
            }
            $name{$name} = \@list;
        }

        return \%name;
    }

    sub _seed ($$);
    sub _seed ($$) {
        my ($path, $name) = @_;
        my $down = (($path ? "$path\->" : '') . $name);
        my @rslt;
        if ($loop{$name}) {
            _error(($path ? "Seed path '$path': " : '')
                 . "Config '$name' is config-looped");
            return ();
        }
        if (! $seed->{$name}) {
            _error(($path ? "Seed path '$path': " : '')
                 . "Config '$name' not seeded");
            return ();
        } elsif (! ref($seed->{$name})) {
            if (! $seed{$name}) {
                $loop{$name} = 1;
                @rslt = _seed($down, $seed->{$name});
                if (@rslt == 1) {
                    $seed{$name} = $rslt[0];
                } elsif (@rslt) {
                    $seed{$name} = \@rslt;
                }
                $loop{$name} = 0;
            }
        } elsif (ref($seed->{$name}) eq 'Grace::Platform') {
            return ( $seed{$name} = $seed->{$name} );
        } elsif (ref($seed->{$name}) eq 'ARRAY') {
            my @list = @{$seed->{$name}};
            $loop{$name} = 1;
            for (my $indx = 0; $indx < @list; ) {
                if (! ref($list[$indx])) {
                    push(@rslt, _seed("$down\[$indx]", $list[$indx]));
                } elsif (ref($list[$indx]) eq 'Grace::Platform') {
                    push(@rslt, $list[$indx]);
                } elsif (ref($list[$indx]) eq 'ARRAY') {
                    splice(@list, $indx, 1, @{$list[$indx]});
                    next;
                } else {
                    _error(($path ? "Seed path '$path': " : '')
                         . "Config '$down\[$indx]': Unknown type "
                         . ref($list[$indx]));
                }
                ++$indx;
            }
            $loop{$name} = 0;
        } else {
            _error(($path ? "Seed path '$path': " : '')
                 . "Config $down: Unknown type "
                 . ref($seed->{$name}));
        }
        return unique(@rslt);
    }

    #
    # Begin by building a hash of names referencing Grace::Platform(s).
    # Each name may reference a single instance or a list of instances.
    # This establishes a table used primarily to set up default and
    # native target platforms for a Grace::Builder.  Any config files
    # parsed in the constructor and "compiled" into Grace::Platform
    # instances here, will be merged into the table linked up here, and
    # will be returned as the platform configuration dictionary for a
    # builder.  This allows config files to override the settings given
    # in the builder's native seed platform description.  This loop
    # resolves names in $seed and begins populating %keep.
    #
    foreach (keys(%{$seed || {}})) {
        _seed('', $_);
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
                $fail = _error("Failed to trace configuration '$item'");
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
    while (my ($fats, $data) = each(%fats)) {
        my $name = $data->{name};
        my $conf = $data->{conf};
        my $arch = $data->{arch};

        if (ref($conf->{fatarch}) ne 'HASH') {
            $conf->{fatarch} = {};
        }
        $conf->{fatarch}{$name} = $arch;
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
    $self->{_data_} = { %seed, %{ _collate() } };

    # Clear these so the values don't persist.
    %done = ();
    %keep = ();
    %fail = ();
    %loop = ();
    %fats = ();
    %list = ();
    @path = ();

    return ($self->errors() == 0);
}

sub new {
    my ($what, %attr) = @_;

    my $self = $what->SUPER::new(%attr);
    if (! $self) {
        return undef;
    }

    if (! _compile($attr{systems}, $self)) {
        return undef;
    }

    return $self;
}

sub system {
    return $_[0]->{_data_}{$_[1]};
}

sub default {
    return $_[0]->system('default');
}

sub native {
    return $_[0]->system('native');
}

1;
