package Net::Appliance::Session::Output;

use Moose;

has 'sequence' => (
    is => 'ro',
    isa  => 'ArrayRef[Str]',
    required => 1,
);

has 'success' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
    required => 0,
);

1;
