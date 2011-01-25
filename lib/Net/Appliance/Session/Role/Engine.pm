package Net::Appliance::Session::Role::Engine;

use Moose::Role;
use Net::Appliance::Session::Action;
use Net::Appliance::Session::ActionSet;

has 'current_prompt' => (
    is => 'rw',
    isa => 'RegexpRef',
    lazy_build => 1,
);

sub _build_current_prompt {
    my $self = shift;
    return $self->last_prompt if eval { $self->last_prompt };
    confess "no prompt set and no last prompt to retrieve";
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
    $set->execute($self->current_prompt);

    $self->last_actionset($set);
}

sub macro {
    my ($self, $name, @params) = @_;

    $self->execute_actions(
        $self->macros->{$name}->clone->apply_params(@params),
    );
}

sub cmd {
    my ($self, $command) = @_;

    $self->execute_actions(
        Net::Appliance::Session::Action->new({
            type => 'send',
            value => $command,
        }),
    );
}

1;
