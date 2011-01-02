package Net::Appliance::Session::Transport::Telnet;

use Moose::Role;
with 'Net::Appliance::Session::Transport';

has 'app' => (
    is => 'ro',
    isa => 'Str',
    default => sub { 'telnet' },
    required => 0,
);

has 'opts' => (
    is => 'ro',
    isa => 'ArrayRef[Str]',
    default => sub { [] },
    required => 0,
);

1;
