package Net::Appliance::Session::Transport::Telnet;

use Moose::Role;

#require Net::Appliance::Session::Transport;
with 'Net::Appliance::Session::Transport';

has 'app' => (
    is => 'ro',
    default => sub { 'telnet' },
    required => 0,
);

has 'opts' => (
    is => 'ro',
    default => sub { [] },
    required => 0,
);

1;
