package Net::Appliance::Session::Transport::Telnet;

use Moose::Role;
with 'Net::Appliance::Session::Role::Transport';

has 'app' => (
    is => 'ro',
    isa => 'Str',
    default => sub { 'telnet' },
    required => 0,
);

sub runtime_options {
    # simple, for now
    return (shift)->transport_options->{host};
}

1;
