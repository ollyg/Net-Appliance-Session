package Net::Appliance::Session::Role::Engine;

use Moose::Role;
use Net::Appliance::Session::Output;
use Carp qw(croak);

has 'current_state' => (
    is => 'rw',
    isa => 'Str',
    required => 0,
);

has 'last_output' => (
    is => 'rw',
    isa => 'Net::Appliance::Session::Output',
    required => 0,
);

sub response { return (shift)->last_output->sequence->[-1] }

sub do_action {
    my ($self, $action) = @_;

    if ($action->type eq 'match') {
        if ($self->out =~ $action->value) {
            return $self->flush;
        }
    }
    return undef;
}

sub execute_actions {
    my $self = shift;
    my @actions = (ref $_[0] ? @{(shift)} : @_);

    my $output = Net::Appliance::Session::Output->new({ sequence => [
        grep { defined $_ }
        map  { $self->do_action($_) } @actions
    ] });

    $output->success( scalar @{$output->sequence} == scalar @actions ? 1 : 0 );
    return $output;
}


sub find_state {
    my $self = shift;

    foreach my $state (keys %{ $self->states }) {
        my $output = $self->execute_actions( $self->states->{$state} );
        if ($output->success) {
            $self->current_state($state);
            $self->last_output($output);
            return 1;
        }
    }

    return 0;
}

1;
