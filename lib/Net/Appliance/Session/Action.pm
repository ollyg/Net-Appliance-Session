package Net::Appliance::Session::Action;

use Moose;
use Moose::Util::TypeConstraints qw(enum);
use Net::Appliance::Session::ActionSet;

has 'type' => (
    is => 'ro',
    isa => enum([qw/send match/]),
    required => 1,
);

has 'value' => (
    is => 'ro',
    isa => 'RegexpRef|Str',
    required => 1,
);

has 'literal' => (
    is => 'ro',
    isa => 'Bool',
    required => 0,
    default => 0,
);

has 'is_lazy' => (
    is => 'ro',
    isa => 'Bool',
    required => 0,
    default => 0,
    init_arg => 'lazy',
);

has 'continuation' => (
    is => 'rw',
    isa => 'Net::Appliance::Session::ActionSet',
    required => 0,
);

has 'params' => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [] },
    auto_deref => 1,
    required => 0,
);

has 'response' => (
    is => 'rw',
    isa => 'Str',
    default => sub { '' },
    required => 0,
);

sub BUILDARGS {
    my ($class, @rest) = @_;
    # accept single hash ref or naked hash
    my $params = (ref $rest[0] eq ref {} and scalar @rest == 1 ? $rest[0] : {@rest});

    if (exists $params->{continuation} and ref $params->{continuation} eq ref []) {
        $params->{continuation} = Net::Appliance::Session::ActionSet->new({
            actions => $params->{continuation},
        });
    }

    return $params;
}

# only a shallow copy so all the reference based slots still
# share data with the original Action's slots
sub clone {
    my $self = shift;
    $self->meta->clone_object($self, %{(shift) || {}});
}

# count the number of sprintf parameters used in the value
sub num_params {
    my $self = shift;
    return 0 if ref $self->value eq ref qr//;
    # this tricksy little number comes from the Perl FAQ
    my $count = () = $self->value =~ m/(?<!%)%/g;
    return $count;
}

1;
