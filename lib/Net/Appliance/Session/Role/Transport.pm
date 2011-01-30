package Net::Appliance::Session::Role::Transport;

use Moose::Role;
use IPC::Run ();
with 'Net::Appliance::Session::Role::Engine';

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
    return ${ $_[0]->_out } if scalar(@_) == 1;
    return ${ $_[0]->_out } = $_[1];
}

# clearer for the _out slot
sub flush {
    my $self = shift;
    my $content = $self->out;
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

    $self->_harness(
        IPC::Run::harness(
            [$self->app, $self->runtime_options],
               $self->_in,
               $self->_out,
               $self->_err,
               IPC::Run::timeout (10),
               debug => 1, )
    );
}

# returns either the content of the output buffer, or undef
sub do_action {
    my ($self, $action) = @_;

    if ($action->type eq 'match') {
        my $cont = $action->continuation;
        while ($self->_harness->pump) {
            if ($cont and $self->out =~ $cont->first->value) {
                my $match = $cont->first->value;
                (my $out = $self->out) =~ s/$match\s*$//;
                $self->out($out);
                $self->send($cont->last->value);
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

1;
