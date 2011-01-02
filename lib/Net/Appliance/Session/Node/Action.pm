package Net::Appliance::Session::Node::Action;

use Moose;

has 'type' => (
    is => 'ro',
    required => 1,
);

has 'value' => (
    is => 'ro',
    required => 1,
);

has 'continuation' => (
    is => 'ro',
    required => 0,
);

1;
