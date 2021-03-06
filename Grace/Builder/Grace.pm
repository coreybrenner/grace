package Grace::Builder::Grace;

use strict;
use warnings;

use parent 'Grace::Builder';

use Data::Dumper;
$Data::Dumper::Indent = 1;
$Data::Dumper::Purity = 1;
$Data::Dumper::Trailingcomma = 1;
$Data::Dumper::Sortkeys = 1;


use Grace::Host;
use Grace::Config::Environ;
use Grace::Config::Platform;

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

sub new {
    my ($what, %attr) = @_;

    my $type = (ref($what) || $what);
    my $prnt = (ref($what) && $what);
print(STDERR __PACKAGE__."->new(): WHAT: '$what', ATTR: ".Dumper(\%attr));

    our $self = $type->SUPER::new(%attr);
    if (! $self) {
print(STDERR __PACKAGE__."->new(): Parent constructor failed; return undef\n");
        return undef;
    }

    #
    # Apply environ files to current builder's environment.  Catch
    # changes made to %ENV, too, and make them local to the current
    # builder;  No configuration shall muck about with the global
    # environment affecting other configurations.
    #
    local %ENV = %{$self->{_attr_}{environ}};
    $self->{_attr_}{environ} = \%ENV;

    # Allow for BUILDER->setenv(...)
    sub BUILDER () {
        return $self;
    }

    my $list = $self->{_attr_}{environ_config_file};
    my @list = ((ref($list) eq 'ARRAY') ? @{$list} : ( $list ));
    # Apply file list.
    map { do $_ } @list;

    my $dict = Grace::Config::Platform->new(
        builder => $self,
        systems => {
            native  => Grace::Host->platform(),
            default => 'native',
        },
        fileset => $self->{_attr_}{systems_config_file},
    );

    if ($dict && ! $dict->errors()) {
        $self->{_attr}{systems_config_dict} = $dict;
    } else {
        if (@{$self->{_attr_}{systems_config_file}}) {
            $self->error(
                "System configuration files:",
                map { "    '$_'" } @{$self->{_attr_}{systems_config_file}}
            );
        } else {
            $self->error(
                "Default host platform configuration " . Grace::Host->sysconf()
            );
        }
    }

#    _variant_config($self, @{$self->{_attr_}->{variant_config_file}});
#    _toolset_config($self, @{$self->{_attr_}->{toolset_config_file}});

print(STDERR __PACKAGE__."->new: RETURN: ".Dumper($self));
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

