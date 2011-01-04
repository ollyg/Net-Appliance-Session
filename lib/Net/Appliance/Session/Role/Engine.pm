package Net::Appliance::Session::Role::Engine;

use Moose::Role;
use Net::Appliance::Session::Action;
use Net::Appliance::Session::ActionSet;
use Carp qw(croak);

has 'current_state' => (
    is => 'rw',
    isa => 'Str',
    required => 0,
);

has 'last_actionset' => (
    is => 'rw',
    isa => 'Net::Appliance::Session::ActionSet',
    required => 0,
);

sub response_tail { return (shift)->last_actionset->sequence->[-1]->response }

# returns either the content of the output buffer, or undef
sub do_action {
    my ($self, $action) = @_;

    if ($action->type eq 'match') {
        print STDERR "matching to ". $action->value ."\n";
        $self->harness->pump until $self->out =~ $action->value;
        $action->response($self->flush);
    }
    if ($action->type eq 'send') {
        my $command = sprintf $action->value, $action->params;
        print STDERR "sending '$command' \n";
        $self->send( $command, $self->ors );
    }
}

sub do_action_sequence {
    my $self = shift;
    my $set = Net::Appliance::Session::ActionSet->new({ sequence => [
        map { blessed $_ eq 'Net::Appliance::Session::ActionSet'
                ? ($_->sequence) : $_ } @_
    ] });

    $self->do_action($_) for $set->sequence;
    return $set;
}

sub execute_actions {
    my $self = shift;
    $self->last_actionset( $self->do_action_sequence( @_ ) )
}

# pump until any of the states matches the output buffer
sub find_state {
    my $self = shift;

    while ($self->harness->pump) {
        foreach my $state (keys %{ $self->states }) {
            # states consist of only one match action
            if ($self->out =~ $self->states->{$state}->sequence->[0]->value) {
                $self->last_actionset(
                    Net::Appliance::Session::ActionSet->new({ sequence => [
                        $self->states->{$state}->sequence->[0]->clone({
                            response => $self->flush,
                        })
                    ] })
                );
                $self->current_state($state);
                return;
            }
        }
    }
}

sub to_state {
    my ($self, $name, @params) = @_;
    my $transition = $self->current_state ."_to_". $name;

    # will block and timeout if we don't get the new state prompt
    $self->execute_actions(
        $self->transitions->{$transition}->clone->apply_params(@params),
        Net::Appliance::Session::Action->new({
            type => 'match',
            value => $self->states->{$name}->sequence->[0]->value,
        })
    );

    $self->current_state($name);
};

sub macro {
    my ($self, $name, @params) = @_;

    # will block until we see a prompt again
    $self->execute_actions(
        $self->macros->{$name}->clone->apply_params(@params),
        Net::Appliance::Session::Action->new({
            type => 'match',
            value => $self->states->{$self->current_state}->sequence->[0]->value,
        }),
    );
}

sub cmd {
    my ($self, $command) = @_;

    # will block until we see a prompt again
    $self->execute_actions(
        Net::Appliance::Session::Action->new({
            type => 'send',
            value => $command,
        }),
        Net::Appliance::Session::Action->new({
            type => 'match',
            value => $self->states->{$self->current_state}->sequence->[0]->value,
        }),
    );
}

1;
