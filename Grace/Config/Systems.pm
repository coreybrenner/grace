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

sub _closure ($) {
    our ($from) = @_;

    our @work = (keys(%{$from}));

    our @errs = ();
    our @warn = ();
    our %keep = ();
    our %done = ();
    our %fail = ();
    our %loop = ();
    our %phat = ();
    our @path = ();

    # Inject an error into the configuration.
    sub _error (@) {
        my $head = "Config '" . join('->', @path) . "'";
        push(@errs, map { print("$_\n"); $_ } map { "$head: $_" } @_);
        return 1;
    }

    sub _group (@);
    sub _close ($);
    sub _trace ($);

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
                $fail = _error("Aliased by config '$name'");
            }
        } elsif (ref($data) eq 'ARRAY') {
            if (! (@list = _group($data))) {
                $fail = _error("Grouped by config '$name'");
            }
        } elsif (ref($data) eq 'HASH') {
            my $conf = $data->{sysconf};
            if (! (@list = _close($data))) {
                $fail = _error("Could not configure '$name'");
            } else {
                foreach $data (@list) {
                    if ($data->{sysarch} || $data->{fatarch}) {
                        $data->{sysconf} = ($conf || $name);
                    }
                }
            }
        } else {
            $fail = _error("Config '$name' must be string,"
                         . " an array of strings, or a hash");
        }
        pop(@path);
        $loop{$name} = 0;

        if ($fail{$name} = $fail) {
            return ();
        }

        $done{$name} = \@list;

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
            my $what = $data[$indx];
            my @part;
            if (! ref($what)) {
                push(@path, "[$indx]");
                @part = _trace($what);
                pop(@path);
            } elsif (ref($what) eq 'ARRAY') {
                splice(@data, $indx, 1, @{$what});
                next;
            } elsif (ref($what) eq 'HASH') {
                push(@path, "[$indx]");
                @part = _close($what);
                pop(@path);
            } else {
                $fail = _error("Unknown type: " . ref($what));
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

    sub _fatty ($) {
        my $conf = shift;
        my $arch = $conf->{fatarch};
        my $fail = 0;
        my @arch;

        if ($conf->{subarch}) {
            return 0;
        }

        if (! ref($arch) || (ref($arch) ne 'HASH')) {
            # Box a singlet so we can process it in a list.
            $arch = [ $arch ];
        }

        if (ref($arch) eq 'HASH') {
            $arch = clone($arch);
        } elsif (ref($arch) ne 'ARRAY') {
            return _error("Unknown type: " . ref($arch));
        } else {
            my %arch;
            @arch = @{$arch};
            for (my $indx = 0; $indx < @arch; ) {
                if (! ref($arch = $arch[$indx])) {
                    $arch{$arch} = {
                        subarch => $arch,
                        sysarch => $arch,
                    };
                } elsif (ref($arch) eq 'HASH') {
                    my $name = "subarch$indx";
                    $arch{$name} = $arch;
                    if (! $arch->{sysconf} && ! $arch->{subarch}) {
                        $arch->{subarch} = $name;
                    }
                    if (! $arch->{sysarch}) {
                        $arch->{sysarch} = $name;
                    }
                } elsif (ref($arch[$indx]) eq 'ARRAY') {
                    # Flatten out embedded lists...
                    splice(@arch, $indx, 1, @{$arch[$indx]});
                    next;
                } else {
                    $fail = _error(
                        "Fatarch: LIST[$indx]: Unknown"
                      . " type: " . ref($arch[$indx])
                    );
                }
                ++$indx;
            }
            $arch = \%arch;
        }

        if (ref($arch) ne 'HASH') {
            return _error("Fatarch: Unknown type: " . ref($arch));
        }

        @arch = ();
        while (my ($name, $data) = each(%{$arch})) {
            $phat{$data} = {
                name => $name,
                conf => $conf,
            };
            if (! $data->{sysconf} && ! $data->{subarch}) {
                $data->{subarch} = $name;
            }
            if (! $data->{sysarch}) {
                $data->{sysarch} = $name;
            }
            push(@arch, $data);
        }

        if (! $fail) {
            push(@work, @arch);
        }

        return $fail;
    }

    sub _close ($) {
        my $data = shift;
        my $fail = 0;
        my $conf;

        my @inht;
        if (defined($data->{inherit})) {
            push(@path, "inherit");
            @inht = _group($data->{inherit});
            pop(@path);
        }

        if (my $phat = $phat{$data}) {
            push(@inht, $phat->{conf});
        }
        $conf = Grace::Config::merge_data(@inht, $data);
        delete($conf->{inherit});

        if ($conf->{sysarch} || $conf->{subarch}) {
            delete($conf->{fatarch});
        }

        my ($phat, $name);
        if (defined($conf->{fatarch})) {
            if (_fatty($conf)) {
                $fail = _error("Fatarch configuration");
            }
        } elsif ($phat = $phat{$data}) {
            $phat{$conf} = {
                %{$phat},
                arch => $conf,
            };
            delete($phat{$data});
        }

        return ($fail ? () : ( $conf ));
    }

    my $fail = 0;
    while (@work) {
        my $what = shift(@work);
        if (! ref($what)) {
            if (! _trace($what)) {
                $fail = 1;
            }
        } elsif (ref($what) eq 'HASH') {
            if (! _close($what)) {
                $fail = _error("Failed to configure fatarch");
            }
        } else {
            $fail = _error("Unknown type: " . ref($what));
        }
    }

    my ($phat, $data);
    while (($phat, $data) = each(%phat)) {
        my $name = $data->{name};
        my $conf = $data->{conf};
        my $arch = $data->{arch};
        $conf->{fatarch}->{$name} = $arch;
    }

    my @pass_errs = @errs;
    my @pass_warn = @warn;
print(STDERR ">>>> raw config:".Dumper(\%keep));
    my $pass_conf = Grace::ActiveConfig::activate(\%keep);
print(STDERR ">>>> activated:".Dumper($pass_conf));

    # Clear these so the values don't persist.
    @errs = ();
    @warn = ();
    %done = ();
    %keep = ();
    %fail = ();
    %loop = ();
    %phat = ();
    @path = ();

    return ($pass_conf, \@pass_errs, \@pass_warn);
}

sub new {
    my ($what, @file) = @_;

    my $self = $what->SUPER::new(@file);

    my ($data, $errs, $warn) = _closure($self->{_data_});

    $self->warning(@{$warn});
    $self->error(@{$errs});

    if (! @{$errs}) {
        $self->{_data_} = $data;
    }

    return $self;
}

sub system {
    return $_[0]->{_data_}->{$_[1]};
}

sub default {
    return $_[0]->system('defaut');
}

sub native {
    return $_[0]->system('native');
}

1;
