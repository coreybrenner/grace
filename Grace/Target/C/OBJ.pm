package Grace::Target::OBJ;

use parent 'Grace::Target';

sub new {
    my ($what, $name, $from) = @_;

    $what->SUPER::new($name, $conf);
}

1;
