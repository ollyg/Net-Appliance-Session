package Net::Appliance::Session::Action;

use Moose;
use Moose::Util::TypeConstraints qw(enum);

has 'type' => (
    is => 'ro',
    isa => enum([qw/send match/]),
    required => 1,
);

has 'value' => (
    is => 'ro',
    isa => 'RegexpRef|Str',
    required => 1,
);

has 'continuation' => (
    is => 'ro',
    isa => 'RegexpRef',
    required => 0,
);

has 'params' => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [] },
    auto_deref => 1,
    required => 0,
);

has 'response' => (
    is => 'rw',
    isa => 'Str', # someday split it?
    required => 0,
);

# only a shallow copy
sub clone {
    my $self = shift;
    $self->meta->clone_object($self, %{(shift) || {}});
}

1;
