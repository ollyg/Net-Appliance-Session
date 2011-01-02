package Net::Appliance::Session::Transport;

use Moo::Role;

has 'irs' => (
    is => 'ro',
    default => sub { "\n" },
    required => 0,
);

has 'ors' => (
    is => 'ro',
    default => sub { "\n" },
    required => 0,
);

1;
