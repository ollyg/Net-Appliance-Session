package Net::Appliance::Session;

use Moose;
with 'Net::Appliance::Session::Role::Phrasebook';

has 'transport' => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has 'transport_options' => (
    is => 'ro',
    isa => 'HashRef[Str]',
    default => sub { {} },
    required => 0,
);

sub BUILD {
    my ($self, $params) = @_;

    $self->_load_graph;

    use Moose::Util;
    Moose::Util::apply_all_roles($self, 
        'Net::Appliance::Session::Transport::'. $self->transport);
}

1;
