package Net::Appliance::Session::Transport;

use Moose::Role;
use IPC::Run qw(start pump finish timer timeout);

#requires qw(app opts hostname);

has 'irs' => (
    is => 'ro',
    default => sub { "\n" },
    required => 0,
);

has 'ors' => (
    is => 'ro',
    default => sub { "\n" },
    required => 0,
);

has '_in' => (
    is => 'rw',
    default => sub { \eval "''" },
    required => 0,
);

sub send { ${ (shift)->_in } .= shift }

has '_out' => (
    is => 'ro',
    default => sub { \eval "''" },
    required => 0,
);

sub out { ${ (shift)->_out } }

has '_err' => (
    is => 'ro',
    default => sub { \eval "''" },
    required => 0,
);

has 'harness' => (
    is => 'rw',
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
