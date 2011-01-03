package Net::Appliance::Session::Role::Engine;

use Moose::Role;
use Net::Appliance::Session::Action;
use Net::Appliance::Session::Response;
use Carp qw(croak);

has 'current_state' => (
    is => 'rw',
    isa => 'Str',
    required => 0,
);

has 'last_response' => (
    is => 'rw',
    isa => 'Net::Appliance::Session::Response',
    required => 0,
);

sub response_tail { return (shift)->last_response->sequence->[-1] }

# returns either the content of the output buffer, or undef
sub do_action {
    my ($self, $action) = @_;

    if ($action->type eq 'match') {
        print STDERR "matching to ". $action->value ."\n";
        $self->harness->pump until $self->out =~ $action->value;
        return $self->flush;
    }
    if ($action->type eq 'send') {
        print STDERR "sending ". $action->value ."\n";
        $self->send( $action->value, $self->ors );
        return undef;
    }
}

sub execute_actions {
    my $self = shift;
    my @actions = map { ((ref $_ eq ref []) ? @{$_} : $_) } @_;

    my $response = Net::Appliance::Session::Response->new({ sequence => [
        grep { defined $_ }
        map  { $self->do_action($_) } @actions
    ] });

    $response->success( scalar @{$response->sequence} == scalar @actions ? 1 : 0 );
    return $response;
}

# pump until any of the states matches the output buffer
sub find_state {
    my $self = shift;

    while ($self->harness->pump) {
        foreach my $state (keys %{ $self->states }) {
            # states consist of only one match action
            if ($self->out =~ $self->states->{$state}->[0]->value) {
                $self->last_response(
                    Net::Appliance::Session::Response->new({
                        sequence => [ $self->flush ]
                    })
                );
                $self->current_state($state);
                return;
            }
        }
    }
}

sub macro {
    my ($self, $name) = @_;

    # will block until we see a prompt again
    $self->last_response(
        $self->execute_actions(
            $self->macros->{$name},
            Net::Appliance::Session::Action->new({
                type => 'match',
                value => $self->states->{$self->current_state}->[0]->value,
            }),
        )
    );
}

sub cmd {
    my ($self, $command) = @_;

    # will block until we see a prompt again
    $self->last_response(
        $self->execute_actions(
            Net::Appliance::Session::Action->new({
                type => 'send',
                value => $command,
            }),
            Net::Appliance::Session::Action->new({
                type => 'match',
                value => $self->states->{$self->current_state}->[0]->value,
            }),
        )
    );
}

sub to_state {
    my ($self, $name) = @_;
    my $transition = $self->current_state ."_to_". $name;

    # will block and timeout if we don't get the new state prompt
    $self->last_response(
        $self->execute_actions(
            $self->transitions->{$transition},
            Net::Appliance::Session::Action->new({
                type => 'match',
                value => $self->states->{$name}->[0]->value,
            })
        )
    );

    $self->current_state($name);
};

1;
