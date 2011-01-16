package Net::Appliance::Session::Role::Iterator;

use Moose::Role;

# fiddly only in case of auto_deref
sub count { return scalar @{ scalar (shift)->_sequence } }

sub first { return (shift)->_sequence->[0]  }
sub last  { return (shift)->_sequence->[-1] }

sub insert_at {
    my ($self, $pos, @rest) = @_;
    my @seq = $self->_sequence;
    splice @seq, $pos, 0, @rest;
    $self->_sequence( \@seq );
}

sub append {
    my $self = shift;
    $self->insert_at( $self->count - 1, (shift)->clone->_sequence );
}

has '_position' => (
    is => 'rw',
    isa => 'Int',
    default => -1,
);

sub idx {
    my $self = shift;
    my $pos = $self->_position;
    confess "attempt to read iter index before pulling a value\n"
        if scalar @_ == 0 and $pos == -1;
    $self->_position(shift) if scalar @_;
    return $pos;
}

sub next {
    my $self = shift;
    confess "er, please check has_next before next\n"
        if not $self->has_next;

    my $position = $self->_position;
    confess "fell off end of iterator\n"
        if ++$position == $self->count;

    $self->_position($position);
    return $self->_sequence->[ $position ];
}

sub has_next {
    my $self = shift;
    return ($self->_position < ($self->count - 1));
}

sub peek {
    my $self = shift;
    return $self->_sequence->[ $self->_position + 1 ]
        if $self->has_next;
}

sub reset { (shift)->_position(-1) }

1;
