package Truc;

use MOP::MOP qw(new value add);
MOP::MOP::register_meta('MOP::Remote','Truc');

sub new {
    my $new = {VALUE => 0};
    return bless $new;
}

sub value {
    my $self = shift;
    return $self->{VALUE};
}

sub add {
    my ($self, $to_add) = @_;
    $self->{VALUE} += $to_add;
    return;
}

1;
