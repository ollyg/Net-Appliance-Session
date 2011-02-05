package Net::CLI::Interact;

use Moose;
with 'Net::CLI::Interact::Role::Phrasebook';
with 'Net::CLI::Interact::Role::Engine';
with 'Net::CLI::Interact::Role::Logger';

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

    $self->log('phrasebook', 1, 'about to load phrasebooks');
    $self->_load_phrasebooks;

    $self->log('transport', 1, 'about to load transport', $self->transport);
    use Moose::Util;
    Moose::Util::apply_all_roles($self, 
        'Net::CLI::Interact::Transport::'. $self->transport);

    $self->log('build', 1, 'finished phrasebook and transport load');
}

1;
