package Net::Appliance::Session::Role::Engine;

use Moose::Role;
use Net::Appliance::Session::Action;
use Net::Appliance::Session::ActionSet;

has 'current_state' => (
    is => 'rw',
    isa => 'Str',
    required => 0,
);

sub current_match {
    my $self = shift;
    return $self->states->{$self->current_state}->first->clone;
}

has 'last_actionset' => (
    is => 'rw',
    isa => 'Net::Appliance::Session::ActionSet',
    required => 0,
);

sub last_prompt { return (shift)->last_actionset->last->response }

sub execute_actions {
    my $self = shift;

    my $set = Net::Appliance::Session::ActionSet->new({ actions => [@_] });
    $set->register_callback(sub { $self->do_action(@_) });
    $set->execute($self->current_match);

    $self->last_actionset($set);
}

sub to_state {
    my ($self, $name, @params) = @_;
    my $transition = $self->current_state ."_to_". $name;

    # will block and timeout if we don't get the new state prompt
    $self->execute_actions(
        $self->transitions->{$transition}->clone->apply_params(@params),
        $self->states->{$name}->clone,
    );

    $self->current_state($name);
};

sub macro {
    my ($self, $name, @params) = @_;

    # will block until we see a prompt again
    $self->execute_actions(
        $self->macros->{$name}->clone->apply_params(@params),
        $self->current_match,
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
        $self->current_match,
    );
}

# pump until any of the states matches the output buffer
sub find_state {
    my $self = shift;

    while ($self->harness->pump) {
        foreach my $state (keys %{ $self->states }) {
            # states consist of only one match action
            if ($self->out =~ $self->states->{$state}->first->value) {
                $self->last_actionset(
                    Net::Appliance::Session::ActionSet->new({ actions => [
                        $self->states->{$state}->first->clone({
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

1;
