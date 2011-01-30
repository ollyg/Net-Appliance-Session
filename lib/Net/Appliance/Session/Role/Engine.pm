package Net::Appliance::Session::Role::Engine;

use Moose::Role;
use Net::Appliance::Session::Action;
use Net::Appliance::Session::ActionSet;

has '_prompt' => (
    is => 'rw',
    isa => 'Maybe[RegexpRef]',
    required => 0,
    reader => 'prompt',
    clearer => 'unset_prompt',
);

sub set_prompt {
    my ($self, $prompt) = @_;
    $self->_prompt( $self->_prompt_tbl->{$prompt}->first->value );
}

has 'last_actionset' => (
    is => 'rw',
    isa => 'Net::Appliance::Session::ActionSet',
    required => 0,
);

sub last_response {
    my $self = shift;
    return $self->last_actionset->item_at(-2)->response;
}

sub last_prompt {
    my $self = shift;
    return $self->last_actionset->item_at(-1)->response;
}

sub last_prompt_as_match {
    my $prompt = (shift)->last_prompt;
    return qr/^$prompt$/;
}

sub macro {
    my ($self, $name, @params) = @_;

    my $set = $self->_macro_tbl->{$name}->clone;
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

    # user can install a prompt, call find_prompt, or let us trigger that
    $self->find_prompt if not $self->last_actionset;

    $set->execute($self->prompt || $self->last_prompt_as_match);
    $self->last_actionset($set);

    # if user used a match ref then we assume new prompt value
    if ($self->last_actionset->last->is_lazy) {
        $self->_prompt($self->last_actionset->last->value);
    }
}

# pump until any of the prompts matches the output buffer
sub find_prompt {
    my $self = shift;

    while ($self->_harness->pump) {
        foreach my $prompt (keys %{ $self->_prompt_tbl }) {
            # prompts consist of only one match action
            if ($self->out =~ $self->_prompt_tbl->{$prompt}->first->value) {
                $self->last_actionset(
                    Net::Appliance::Session::ActionSet->new({ actions => [
                        $self->_prompt_tbl->{$prompt}->first->clone({
                            response => $self->flush,
                        })
                    ] })
                );
                return;
            }
        }
    }
}

1;
