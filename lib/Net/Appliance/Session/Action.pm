package Net::Appliance::Session::Node::Action;

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

1;
