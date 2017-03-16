package Grace::Options;

use strict;
use warnings;
#use diagnostics;

use File::Spec;
use Cwd;

BEGIN {
    our @ISA         = qw{Exporter};
    our @EXPORT_OK   = (
        'OPT_UNWANTED',
        'OPT_REQUIRED',
        'OPT_OPTIONAL',
        'OPT_ATTACHED',
    );
    our %EXPORT_TAGS = (
        OPT_ => [
            'OPT_UNWANTED',
            'OPT_REQUIRED',
            'OPT_OPTIONAL',
            'OPT_ATTACHED',
        ],
    );
    use Exporter;
}

use Grace::Utility qw{unique printdef};

BEGIN {
    sub OPT_UNWANTED () { 0 }
    sub OPT_REQUIRED () { 1 }
    sub OPT_OPTIONAL () { 2 }
    sub OPT_ATTACHED () { 3 }
}

sub _tolist (@) {
    grep { defined } map { (ref($_) ? @{$_} : $_) } @_;
}

my $_rex_split = qr{
    (?(DEFINE)
      (?<plain> (?:(?>[^\s\,\"\'\(\)\[\]\{\}\\]+)|\\.)+)
      (?<slack> (?:(?>[^\"\'\(\)\[\]\{\}\\]+)|\\.)+)
      (?<inquo> (?:(?>[^\"\(\)\{\}\[\]\\]+)|\\.)+)
      (?<group_middle>
        (?: (?&slack)*
            (?:(?&group)+ (?&slack)*)?
            (?:(?&quote)+ (?&slack)*)?
        )+
      )
      (?<group_parens> (?:(?>\( (?&group_middle)* \))|\())
      (?<group_square> (?:(?>\[ (?&group_middle)* \])|\[))
      (?<group_braces> (?:(?>\{ (?&group_middle)* \})|\{))
      (?<close> [\)\}\]])
      (?<group>
        (?: (?&group_parens)
          | (?&group_square)
          | (?&group_braces)
        )
      )
      (?<quote_escape> (?> \\. ))
      (?<quote_single> (?> \' (?:(?>[^\\']+)|(?>\\')|(?>\\))*  (?:\'|$) ))
      (?<quote_middle>
        (?: (?&inquo)*
            (?:(?&group)+ (?&inquo)*)?
            (?:(?&close)+ (?&inquo)*)?
        )+
      )
      (?<quote_double> (?> \" (?&quote_middle)* (?:\"|$) ))
      (?<quote_dollar> (?> \$\' (?:(?>[^\\']+)|(?>\\.)|(?>\\))* (?:\')|$))
      (?<quote>
        (?: (?&quote_escape)
          | (?&quote_single)
          | (?&quote_double)
          | (?&quote_dollar)
        )
      )
      (?<split>
        (?: (?&plain)*
            (?:(?&group)+ (?&plain)*)?
            (?:(?&quote)+ (?&plain)*)?
            (?:(?&close)+ (?&plain)*)?
        )+
      )
    )
    (?&split)
}xso;

sub _split (@) {
    my $istr;
    my @oarr;

    while (@_) {
        next if (! ($istr = shift));

        while ($istr ne '') {
            $istr =~ s{^(?>[\s,]*)($_rex_split)}{}o;
            push(@oarr, $1);
        }
    }

    return @oarr;
}

sub split (@) {
    return _split(@_);
}

my $_rex_chunk = qr{
    (?(DEFINE)
      (?<plain> (?:(?>[^\s\"\'\(\)\[\]\{\}\\]+)|\\.?)+)
      (?<slack> (?:(?>[^\"\'\(\)\[\]\{\}\\]+)|\\.?)+)
      (?<inquo> (?:(?>[^\"\(\)\{\}\[\]\\]+)|\\.?)+)
      (?<group_middle>
        (?: (?&slack)*
            (?:(?&group)+ (?&slack)*)?
            (?:(?&quote)+ (?&slack)*)?
        )+
      )
      (?<group_parens> (?:(?>\( (?&group_middle)* \))|\())
      (?<group_square> (?:(?>\[ (?&group_middle)* \])|\[))
      (?<group_braces> (?:(?>\{ (?&group_middle)* \})|\{))
      (?<close> [\)\}\]])
      (?<group>
        (?: (?&group_parens)
          | (?&group_square)
          | (?&group_braces)
        )
      )
      (?<quote_escape> (?> \\. ))
      (?<quote_single> (?> \' (?:(?>[^\\']+)|(?>\\')|(?>\\))*  (?:\'|$) ))
      (?<quote_middle>
        (?: (?&inquo)*
            (?:(?&group)+ (?&inquo)*)?
            (?:(?&close)+ (?&inquo)*)?
        )+
      )
      (?<quote_double> (?> \" (?&quote_middle)* (?:\"|$) ))
      (?<quote_dollar> (?> \$\' (?:(?>[^\\']+)|(?>\\.)|(?>\\))* (?:\')|$))
      (?<quote>
        (?: (?&quote_escape)
          | (?&quote_single)
          | (?&quote_double)
          | (?&quote_dollar)
        )
      )
      (?<chunk>
        (?: (?&plain)*
            (?:(?&group)+ (?&plain)*)?
            (?:(?&quote)+ (?&plain)*)?
            (?:(?&close)+ (?&plain)*)?
        )+
      )
    )
    (?&chunk)
}xso;

sub _chunk (@) {
    my $istr;
    my @oarr;

    while (@_) {
        next if (! ($istr = shift));

        while ($istr ne '') {
            $istr =~ s{^(?>[\s,]*)($_rex_chunk)}{}o;
            push(@oarr, $1);
        }
    }

    return @oarr;
}

sub parse ($@) {
    my $opts = shift;

    my (%long, $long);
    my (%flag, $flag);
    my $hand;

    my @unkn;
    my @untk;
    my @errs;
    my $type;

    my ($opt, $arg, $aop, $err, $cnt, $fil, $txt);

    foreach $hand (@{$opts}) {
        foreach $flag (_tolist($hand->{flag}, $hand->{flag_hidden})) {
            $flag{$flag} = $hand;
        }
        foreach $long (_tolist($hand->{long}, $hand->{long_hidden})) {
            $long{$long} = $hand;
        }
    }

    while (defined($_ = shift)) {
        if ($_ eq '--') {
            push(@untk, @_);
            last;
        }

        if (m{^\@(.+)$}o) {
            my $fil = $1;
            my $dsc;
print(STDERR __PACKAGE__."::parse(\@...): fil='$fil'\n");
            if (! File::Spec->file_name_is_absolute($fil)) {
print(STDERR __PACKAGE__."::parse(): not absolute\n");
                $fil = File::Spec->catfile(Cwd::cwd(), $fil);
print(STDERR __PACKAGE__."::parse(): absolutized: '$fil'\n");
                if (! open($dsc, '<', $fil)) {
                    push(@errs, "File '$1': $!");
                    next;
                } else {
                    local $/;
                    $txt = <$dsc>;
                    close($dsc);
                }
print(STDERR __PACKAGE__."::parse(): file text:\n$txt\n");
my @stuff = _chunk($txt);
print(STDERR __PACKAGE__."::parse(): new opts: [@stuff]\n");
                unshift(@_, @stuff);
print(STDERR __PACKAGE__."::parse(): amended option stream: @_\n");
            }
        } elsif (m{^--((?:[^:?+=]+|[:?+](?!=))+)(?:([:?+]?=)(.*)?)?}o) {
            $opt = $1;
            $aop = $2;
            $arg = $3;
            if (! ($hand = $long{$opt})) {
                push(@unkn, $_);
                next;
            }
            $type = (defined($hand->{type}) ? $hand->{type} : OPT_UNWANTED);
            if (($type == OPT_REQUIRED) && ! $arg && ! @_) {
                push(@errs, "Option '--$opt': Option requires argument");
                next;
            } elsif (($type == OPT_REQUIRED) || ($type == OPT_OPTIONAL)) {
                if (! $aop) {
                    $arg = $_[0];
                }
            } elsif (($type == OPT_UNWANTED) && $aop) {
                push(@errs, "Option '--$opt': Option takes no argument");
                next;
            } elsif (! $hand->{func}) {
                next;
            }
            if ($cnt = &{$hand->{func}}("--$opt", $aop, $arg, \@_)) {
                splice(@_, 0, $cnt);
            }
        } elsif (m{^-}o) {
            while ($_ ne '-') {
                s{^-(.)(.*)}{-$2}o;
                $opt = $1;
                $aop = undef;
                $arg = $2;
                if (! ($hand = $flag{$opt})) {
                    push(@unkn, "-$opt");
                    next;
                } else {
                    $type = $hand->{type};
                }
                if (($type == OPT_REQUIRED) && ! $arg && ! @_) {
                    push(@errs, "Option '-$1': Option requires argument");
                    next;
                } elsif (($type == OPT_REQUIRED)
                      || ($type == OPT_OPTIONAL)  # Flags taking values treat...
                      || ($type == OPT_ATTACHED)) # ATTACHED as if OPTIONAL.
                {
                    if ($arg) {
                        $aop = ':=';
                        $_   = '-';
                    } else {
                        $arg = $_[0];
                    }
                } elsif ($type == OPT_UNWANTED) {
                    $arg = undef;
                } elsif (! $hand->{func}) {
                    next;
                }
                if ($cnt = &{$hand->{func}}("-$opt", $aop, $arg, \@_)) {
                    shift $cnt;
                }
            }
        } else {
            # Not a special option char, '@' or '-', so pass as untaken.
            push(@untk, $_);
        }
    }

    return (\@unkn, \@untk, \@errs);
}

sub usage ($) {
    my @opts = @{$_[0]};
    my @args;
    my %opts;
    my %back;

    my (%hand, $hand);
    my (%long, $long); 
    my (%flag, $flag);
    my %done;
    my @mesg;
    my @help;
    my @line;
    my $opts;
    my $type;

    sub _listlen ($) {
        my $len = 0;
        map { $len += length($_) } @{$_[0]};
        return $len;
    }

    # Allow long and short options to be overridden.
    foreach $hand (@opts) {
        foreach (_tolist($hand->{flag})) {
            $flag{$_} = $hand;
        }
        foreach (_tolist($hand->{long})) {
            $long{$_} = $hand;
        }
    }

    my $max_opts = 0;
    my $max_help = 0;

    # Map option handles to long and short flags that point to them,
    # and calculate usage display layout parameters.
    foreach $hand (unique(values(%flag), values(%long))) {
        # Create a dummy so we don't have undefined array refs later.
        $hand{$hand} = {
            flag => [],
            long => [],
            opts => 0,
        };
        # Determine whether options listed for a handle do in fact
        # point back at that handle.  The option may have been overriden
        # in this aspect, so only report on what is current.
        foreach $flag (_tolist($hand->{flag})) {
            if ($flag{$flag} == $hand) {
                push(@{$hand{$hand}->{flag}}, $flag);
            }
        }
        foreach $long (_tolist($hand->{long})) {
            if ($long{$long} == $hand) {
                push(@{$hand{$hand}->{long}}, $long);
            }
        }

        # Determine whether this option handle is active.
        # An option handle may deactivate a flag or long option by
        # capturing it (last) and not providing a function, too.
        my @opt_list = (@{$hand{$hand}->{flag}}, @{$hand{$hand}->{long}});
        next if (! @opt_list || ! $hand->{func});

        my $num_opts = @opt_list;
        my $len_opts = _listlen(\@opt_list);
        # This handle has at least one option pointing to it, and
        # has a function bound to it.

        $type = (defined($hand->{type}) ? $hand->{type} : OPT_UNWANTED);

        # Calculate what is added to each option.
        my @args;
        if ($type != OPT_UNWANTED) {
            @args = _tolist($hand->{args});
            if (! @args) {
                @args = ( '<MISSING>' );
            }
        }

        my @list;
        foreach my $opt (sort(@{$hand{$hand}->{flag}})) {
            if ($type == OPT_UNWANTED) {
                push(@list, "-$opt");
            } elsif ($type == OPT_REQUIRED) {
                push(@list, map { "-$opt $_" } @args);
            } else {
                push(@list, map { "-$opt [$_]" } @args);
            }
        }
        foreach my $opt (sort(@{$hand{$hand}->{long}})) {
            if ($type == OPT_UNWANTED) {
                push(@list, "--$opt");
            } elsif ($type == OPT_REQUIRED) {
                push(@list, map { "--$opt=$_" } @args);
            } else {
                push(@list, map { "--$opt\[=$_\]" } @args);
            }
        }

        @line = ();
        $opts = '';
        foreach (@list) {
            if ((length($opts) + ($opts ? 2 : 0) + length($_)) <= 75) {
                $opts .= ($opts ? ', ' : '') . $_;
            } else {
                push(@line, $opts . ',');
                $opts  = $_;
            }
        }
        push(@line, $opts);
        $hand{$hand}{line} = [ @line ];

        if (length($opts) > $max_opts) {
            $max_opts = length($opts)
        }
        @help = _tolist($hand->{help});
        if (! @help) {
            @help = ('<UNDOCUMENTED>');
        }
        foreach (@help) {
            if (length($_) > $max_help) {
                $max_help = length($_);
            }
        }
    }

    my $marg = (76 - (2 + $max_help));
    my $wrap = 0;
    my $same = 0;
    foreach $hand (keys(%hand)) {
        if ((length($hand{$hand}{line}->[-1]) + 2 + $max_help) > 76) {
            ++$wrap;
        } else {
            ++$same;
        }
    }
    if ($wrap = ($wrap >= ($same * 2))) {
        $marg = ($marg / 2);
    }

    # Now, build the usage() output into an array to return.
    foreach (sort(keys(%flag), keys(%long))) {
        # If this handle is already reported on, skip it.
        $hand = ($flag{$_} || $long{$_});
        next if ($done{$hand});
        # Mark this handle done.
        $done{$hand} = 1;

        # Build flag+long option list.
        push(@mesg, @{$hand{$hand}{line}});
        @help = _tolist($hand->{help});
        if (! @help) {
            @help = ( '<UNDOCUMENTED>' );
        }

        if (! $wrap && ((length($mesg[-1]) + 2) <= $marg)) {
            $mesg[-1] = sprintf("%-*s%s", $marg, $mesg[-1], $help[0]);
            shift(@help);
        }
        foreach (@help) {
            push(@mesg, ((' ' x $marg) . $_));
        }
    }

    return @mesg;
}

1;

