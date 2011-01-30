package Net::Appliance::Session::Role::Engine;

use Moose::Role;
use Net::Appliance::Session::Action;
use Net::Appliance::Session::ActionSet;

has 'last_actionset' => (
    is => 'rw',
    isa => 'Net::Appliance::Session::ActionSet',
);

sub last_prompt { return (shift)->last_actionset->last->response }

sub prompt_as_match {
    my $prompt = (shift)->last_prompt;
    return qr/^$prompt$/m;
}

sub macro {
    my ($self, $name, @params) = @_;

    my $set = $self->macros->{$name}->clone;
    $set->apply_params(@params);
    $self->_execute_actions($set);
}

sub cmd {
    my ($self, $command) = @_;

    $self->_execute_actions(
        Net::Appliance::Session::Action->new({
            type => 'send',
            value => $command,
        }),
    );
}

sub _execute_actions {
    my $self = shift;

    my $set = Net::Appliance::Session::ActionSet->new({ actions => [@_] });
    $set->register_callback(sub { $self->do_action(@_) });
    $set->execute($self->prompt_as_match);

    $self->last_actionset($set);
}

# pump until any of the states matches the output buffer
sub find_state {
    my $self = shift;

    while ($self->_harness->pump) {
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
                # $self->current_state($state);
                return;
            }
        }
    }
}

1;
