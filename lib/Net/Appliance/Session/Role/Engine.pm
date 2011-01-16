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

sub response_tail { return (shift)->last_actionset->last->response }

# returns either the content of the output buffer, or undef
sub do_action {
    my ($self, $action) = @_;

    if ($action->type eq 'match') {
        my $cont = $action->continuation;
        while ($self->harness->pump) {
            if ($cont and $self->out =~ $cont) {
                (my $out = $self->out) =~ s/$cont\s*$//;
                $self->out($out);
                $self->send(' '); # XXX continuation char?
            }
            elsif ($self->out =~ $action->value) {
                $action->response($self->flush);
                last;
            }
        }
    }
    if ($action->type eq 'send') {
        my $command = sprintf $action->value, $action->params;
        $self->send( $command, $self->ors );
    }
}

sub pad_and_prepare_sequence {
    my ($self, @seq) = @_;
    my @padded_seq = ();

    foreach my $i (0 .. $#seq) {
        push @padded_seq, $seq[$i];

        if ($seq[$i]->type eq 'send' and $i < $#seq) {

            # pad out the Actions with match Actions if
            # needed between send pairs
            if ($seq[$i + 1]->type eq 'send') {
                push @padded_seq,
                    $self->states->{$self->current_state}->first->clone;
            }
            # carry-forward a continuation beacause it's the match
            # which really does the heavy lifting there
            elsif ($seq[$i + 1]->type eq 'match'
                    and defined $seq[$i]->continuation) {
                $seq[$i + 1]->continuation( $seq[$i]->continuation );
            }
        }
    }

    return @padded_seq;
}

sub do_action_sequence {
    my $self = shift;
    # unroll the params from set(s) into only Actions
    my @seq = map { ref $_ eq 'Net::Appliance::Session::ActionSet'
                    ? ($_->sequence) : $_ } @_;

    my $set = Net::Appliance::Session::ActionSet->new({ actions => [
        $self->pad_and_prepare_sequence(@seq)
    ] });

    $self->do_action($_) for $set->sequence;
    $set->marshall_responses;
    return $set;
}

sub execute_actions {
    my $self = shift;
    $self->last_actionset( $self->do_action_sequence( @_ ) );
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
        $self->states->{$self->current_state}->clone,
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
        $self->states->{$self->current_state}->clone,
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
