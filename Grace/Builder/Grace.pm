package Grace::Builder::Grace;

use strict;
use warnings;

use Data::Dumper;

use Grace::Config::Environ;
use Grace::Config::Systems;

use parent 'Grace::Builder';

use Clone qw{clone};

sub getenv {
    my ($self, $var) = @_;

    return (
        defined($var)
            ? $self->{_attr_}->{environ}->{$var}
            : %{$self->{_attr_}->{environ}}
    );
}

sub setenv {
    my $self = shift;

    if (ref($_[0]) eq 'HASH') {
        $self->{_attr_}->{environ} = shift;
    } else {
        my ($var, $val) = @_;

        if (! defined($val)) {
            delete($self->{_attr_}->{environ}->{$var});
        } else {
            if (ref($val) eq 'ARRAY') {
                $val = join(' ', @{$val});
            }
            $self->{_attr_}->{environ}->{$var} = $val;
        }
    }

    return $self;
}

sub _systems_config {
    my $self = shift;

    $self->{_attr_}->{systems_config_dict} =
        Grace::Config::Systems->new($self, @_);

    #
    # Validate systems+subarch configurations, possibly restricting subarches.
    #
    my %sys;
    my @bad;
    foreach my $sys (@{$self->{_attr_}->{systems}}) {
        my $cfg;
        if (! ($cfg = $self->{_attr_}->{systems_config_dict}->system($sys))) {
            push(@bad, $sys);
            next;
        }
        #
        # Make independent copy of each active system configuration.
        # These configurations may then be modified as needed, while
        # not changing the information in the compiled system config
        # dictionary, which we also want to keep in a pristine state
        # for reporting.
        #
        $cfg = $sys{$sys} = clone($cfg);

        #
        # Restrict fat architectures' fatarch fields to the named
        # subarchitectures, if any names match.  If there are no
        # matches in any active configuration's fatarch field, then
        # assume that the subarch restriction does not apply to the
        # system under scrutiny, and allow through the full set.
        #
        my @cfg;
        if (ref($cfg) eq 'ARRAY') {
            @cfg = @{$cfg};
        } else {
            @cfg = ( $cfg );
        }

        foreach $cfg (@cfg) {
            if ($cfg->{fatarch} && $self->{_attr_}->{subarch}) {
                my %sub;
                # Compile a list of subarches matching this system config.
                foreach my $sub (keys(%{$cfg->{fatarch}})) {
                    if ($self->{_attr_}->{subarch}->{$sub}) {
                        $sub{$sub} = 1;
                    }
                }
                # If any matches, chop out the non-matching subarchitectures
                # from the retained system configuration.
                if (keys(%sub)) {
                    foreach my $sub (keys(%{$cfg->{fatarch}})) {
                        if (! $sub{$sub}) {
                            delete($cfg->{fatarch}->{$sub});
                        }
                    }
                }
            }
        }
    }
    if (@bad) {
        $self->error(map { "System '$_' not configured" } @bad);
        $self->error("System configuration files:");
        $self->error(map { "    '$_'" } @{$self->{systems_config_file}});
    } else {
        $self->{_attr_}->{systems_config} = \%sys;
    }
}

sub new {
    my ($what, %conf) = @_;

    my  $type = (ref($what) || $what);
    my  $self = bless({ _attr_ => { %conf } }, $type);

#    _environ_config($self, @{$conf{environ_config_file}});
#print(STDERR __PACKAGE__."->new($what, ...): ENV: ".Dumper($self->{_attr_}->{environ}));

    _systems_config($self, @{$conf{systems_config_file}});
print(STDERR __PACKAGE__."->new(): Final builder config:".Dumper($self));

#    _variant_config($self, @{$conf{variant_config_file}});
#    _toolset_config($self, @{$conf{toolset_config_file}});

    return $self;
}

1;

#        include
#    if (! defined($sys = $options{''}{sysconf})) {
#                $configs{$cfg}{toolset}{$sys} = \%set;
#        var => 'nullenv',
#        var => 'dobuild',
#        var => 'dontdie',
#        var => 'list_projects',
#        var => 'show_projects',
#        var => 'show_environ',
#        var => 'show_toolenv',
#        var => 'list_toolsets',
#        var => 'show_toolsets',
#        $configs{$cfg}{environ} = \%sub;
#        $configs{$cfg}{setvar} = \%sub;
#        $configs{$cfg}{target} = \@sub;
#        $configs{$cfg}{variant} = {
#        $configs{$cfg}{search_order} = $order{$cfg};
#        $configs{$cfg}{search_alias} = $alias{$cfg};
#        $configs{$cfg}{search_group} = $group{$cfg};
#        $configs{$cfg}{verbose} = $cfg{$cfg};
#        $configs{$cfg}{overlay} = \@sub;
#        fil => 'systems_config_file',
#        fil => 'toolset_config_file',
#        fil => 'environ_config_file',
#        fil => 'variant_config_file',
#                cfgname => $cfg,
#                srcroot => $dir,
#                relpath => $configs{$cfg}{relpath}{$dir},
#                outroot => $configs{$cfg}{outroot}{$dir},
#                pubroot => $configs{$cfg}{pubroot}{$dir},
#                systems_config_file =>
#                    $configs{$cfg}{systems_config_file}{$dir},
#                toolset_config_file =>
#                    $configs{$cfg}{toolset_config_file}{$dir},
#                environ_config_file =>
#                    $configs{$cfg}{toolset_config_file}{$dir},
#                variant_config_file =>
#                    $configs{$cfg}{variant_config_file}{$dir},
#            );
