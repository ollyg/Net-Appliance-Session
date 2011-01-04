package Net::Appliance::Session::ActionSet;

use Moose;
use Net::Appliance::Session::Action;

has 'sequence' => (
    is => 'ro',
    isa  => 'ArrayRef[Net::Appliance::Session::Action]',
    auto_deref => 1,
    required => 1,
);

sub BUILDARGS {
    my ($class, @rest) = @_;
    my $params = (ref $rest[0] eq ref {} and scalar @rest == 1 ? $rest[0] : {@rest});

    if (exists $params->{actions}) {
        push @{$params->{sequence}}, Net::Appliance::Session::Action->new($_)
            for @{$params->{actions}};
        delete $params->{actions};
    }

    return $params;
}

sub clone {
    return Net::Appliance::Session::ActionSet->new({
        sequence => [ map { $_->clone } (shift)->sequence ],
    });
}

sub apply_params {
    my ($self, @params) = @_;

    for (0 .. (scalar @{$self->sequence} - 1)) {
        $self->sequence->[$_]->params($params[$_] || []);
    }
    return $self;
}

1;
