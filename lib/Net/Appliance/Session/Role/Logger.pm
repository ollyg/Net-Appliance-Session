package Net::Appliance::Session::Role::Logger;

use Moose::Role;
use Time::HiRes qw(gettimeofday tv_interval);

has 'log_flags' => (
    is => 'rw',
    isa => 'ArrayRef|HashRef[Int]',
    default => sub { {} },
);

has 'log_stamps' => (
    is => 'rw',
    isa => 'Bool',
    required => 0,
    default => 1,
);

has 'log_start' => (
    is => 'ro',
    isa => 'ArrayRef',
    required => 0,
    default => sub{ [gettimeofday] },
);

sub log_flag_on {
    my ($self, $flag) = @_;
    my $flags = (ref $self->log_flags eq ref []
        ? { map {$_ => 1} @{$self->log_flags} }
        : $self->log_flags
    );
    return (exists $flags->{$flag} ? $flags->{$flag} : 0);
}

sub log {
    my ($self, $flg, $lvl, @msgs) = @_;
    return unless $self->log_flag_on($flg) >= $lvl;
    my $stamp = sprintf "%13s", ($self->log_stamps
        ? ('['. (sprintf "%.6f", (tv_interval $self->log_start, [gettimeofday])) .'] ')
        : ());
    print STDERR $stamp, (substr $flg, 0, 1), (' ' x $lvl), (join ' ', @msgs);
    print STDERR "\n" if $msgs[-1] !~ m/\n$/;
}

1;
