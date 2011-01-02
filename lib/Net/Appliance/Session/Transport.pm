package Net::Appliance::Session::Transport;

use Moose::Role;
use IPC::Run qw(start pump finish timer timeout);

#requires qw(app opts hostname);

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

# writer for the _in slot which is a scalar ref
sub send { ${ (shift)->_in } .= shift }

has '_out' => (
    is => 'ro',
    isa => 'ScalarRef',
    default => sub { \eval "''" },
    required => 0,
);

# reader for the _out slot which is a scalar ref
sub out { ${ (shift)->_out } }

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
        start( [$self->app, @{$self->opts}, $self->host],
               $self->_in,
               $self->_out,
               $self->_err,
               timeout (10),
               debug => 1, )
    );

    #$self->send("hello\n");
    #pump $self->harness until $self->out =~ m/hello/;
    #print $self->out, "\n";
}

1;
