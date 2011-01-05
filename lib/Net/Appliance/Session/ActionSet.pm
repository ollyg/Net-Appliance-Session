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

# err...?
sub count { return scalar @{ scalar (shift)->sequence } }

# marshall the responses so as to move data from match to send
sub marshall_responses {
    my $self = shift;
    my @seq = $self->sequence;

    foreach my $i (1 .. ($self->count - 1)) {
        next unless $self->sequence->[$i]->type eq 'match';
        my $response = $self->sequence->[$i]->response; # need an lvalue
        my $cmd = $self->sequence->[$i - 1]->value;
        $response =~ s/^$cmd\s+//;
        if ($response =~ s/(\s+)(\S+)\s*$/$1/) {
            $self->sequence->[$i]->response($2);
            $self->sequence->[$i - 1]->response($response);
        }
    }
}

1;
