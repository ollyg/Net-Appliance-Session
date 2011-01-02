package Net::Appliance::Session::Role::Transport;

use Moose::Role;
use IPC::Run ();
# requires qw(app opts host);

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
sub send { ${ (shift)->_in } .= shift }

has '_out' => (
    is => 'ro',
    isa => 'ScalarRef',
    default => sub { \eval "''" },
    required => 0,
);

# reader for the _out slot
sub out { ${ (shift)->_out } }

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

has 'harness' => (
    is => 'rw',
    isa => 'IPC::Run',
    required => 0,
);

sub connect {
    my ($self, $args) = @_;

    $self->harness(
        IPC::Run::harness(
            [$self->app, @{$self->opts}, $self->host],
               $self->_in,
               $self->_out,
               $self->_err,
               IPC::Run::timeout (10),
               debug => 1, )
    );
}

1;
