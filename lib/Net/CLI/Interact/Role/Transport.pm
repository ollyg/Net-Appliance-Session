package Net::CLI::Interact::Role::Transport;

use Moose::Role;
use IPC::Run ();

has 'irs' => (
    is => 'ro',
    isa => 'Str',
    default => sub { "\n" },
    required => 0,
);

has 'ors' => (
    is => 'ro',
    isa => 'Str',
    default => sub { "\n" },
    required => 0,
);

has '_in' => (
    is => 'rw',
    isa => 'ScalarRef',
    default => sub { \eval "''" },
    required => 0,
);

# writer for the _in slot
sub send { ${ (shift)->_in } .= join '', @_ }

has '_out' => (
    is => 'ro',
    isa => 'ScalarRef',
    default => sub { \eval "''" },
    required => 0,
);

# mutator for the _out slot
sub out {
    my $self = shift;
    return ${ $self->_out } if scalar(@_) == 0;
    return ${ $self->_out } = shift;
}

has '_stash' => (
    is => 'rw',
    isa => 'Str',
    default => sub { '' },
    required => 0,
);

# clearer for the _out slot
sub flush {
    my $self = shift;
    my $content = $self->_stash . $self->out;
    $self->_stash('');
    ${ $self->_out } = '';
    return $content;
}

has '_err' => (
    is => 'ro',
    isa => 'ScalarRef',
    default => sub { \eval "''" },
    required => 0,
);

has '_harness' => (
    is => 'rw',
    isa => 'IPC::Run',
    required => 0,
);

sub connect {
    my ($self, $args) = @_;
    $self->log('transport', 1, 'booting IPC::Run harness for', $self->app);

    $self->_harness(
        IPC::Run::harness(
            [$self->app, $self->runtime_options],
               $self->_in,
               $self->_out,
               $self->_err,
               IPC::Run::timeout (10),
        )
    );
}

# returns either the content of the output buffer, or undef
sub do_action {
    my ($self, $action) = @_;
    $self->log('transport', 2, 'callback received for', $action->type);

    if ($action->type eq 'match') {
        my $cont = $action->continuation;
        while ($self->_harness->pump) {
            my $irs = $self->irs;
            my @out_lines = split m/$irs/, $self->out;
            my $maybe_stash = join $self->irs, @out_lines[0 .. -2];
            my $last_out = $out_lines[-1];

            if ($cont and $last_out =~ $cont->first->value) {
                $self->log('transport', 3, 'continuation matched');
                $self->_stash($self->flush);
                $self->send($cont->last->value);
            }
            elsif ($last_out =~ $action->value) {
                $self->log('transport', 3, 'output matched, storing and returning');
                $action->response($self->flush);
                last;
            }
            else {
                $self->log('transport', 4, "nope, doesn't (yet) match", $action->value);
                # put back the partial output and try again
                $self->_stash( $self->_stash . $maybe_stash );
                $self->out($last_out);
            }
        }
    }
    if ($action->type eq 'send') {
        my $command = sprintf $action->value, $action->params;
        $self->log('transport', 3, 'queueing data for send:', $command);
        $self->send( $command, ($action->literal ? () : $self->ors) );
    }
}

1;
