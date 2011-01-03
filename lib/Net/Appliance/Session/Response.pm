package Net::Appliance::Session::Response;

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
