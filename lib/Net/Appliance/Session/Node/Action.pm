package NAS::Node::Action;

use Moo;

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
