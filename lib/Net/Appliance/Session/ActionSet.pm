package Net::Appliance::Session::ActionSet;

use Moose;
use Net::Appliance::Session::Action;

has '_sequence' => (
    is => 'rw',
    isa  => 'ArrayRef[Net::Appliance::Session::Action]',
    auto_deref => 1,
    required => 1,
);

# fiddly only because of auto_deref
sub count { return scalar @{ scalar (shift)->_sequence } }

sub first { return (shift)->_sequence->[0]  }
sub last  { return (shift)->_sequence->[-1] }

sub insert_at {
    my ($self, $pos, @rest) = @_;
    my @seq = $self->_sequence;
    splice @seq, $pos, 0, @rest;
    $self->_sequence( \@seq );
}

sub append {
    my $self = shift;
    $self->insert_at( $self->count - 1, (shift)->clone->_sequence );
}

has '_position' => (
    is => 'rw',
    isa => 'Int',
    default => -1,
);

sub idx {
    my $self = shift;
    my $pos = $self->_position;
    confess "attempt to read iter index before pulling a value\n"
        if scalar @_ == 0 and $pos == -1;
    $self->_position(shift) if scalar @_;
    return $pos;
}

sub next {
    my $self = shift;
    confess "er, please check has_next before next\n"
        if not $self->has_next;

    my $position = $self->_position;
    confess "fell off end of iterator\n"
        if ++$position == $self->count;

    $self->_position($position);
    return $self->_sequence->[ $position ];
}

sub has_next {
    my $self = shift;
    return ($self->_position < ($self->count - 1));
}

sub peek {
    my $self = shift;
    return $self->_sequence->[ $self->_position + 1 ]
        if $self->has_next;
}

sub reset { (shift)->_position(-1) }

sub BUILDARGS {
    my ($class, @rest) = @_;
    # accept single hash ref or naked hash
    my $params = (ref $rest[0] eq ref {} and scalar @rest == 1 ? $rest[0] : {@rest});

    if (exists $params->{actions} and ref $params->{actions} eq ref []) {
        foreach my $a (@{$params->{actions}}) {
            if (ref $a eq 'Net::Appliance::Session::ActionSet') {
                push @{$params->{_sequence}}, $a->_sequence;
                next;
            }

            if (ref $a eq 'Net::Appliance::Session::Action') {
                push @{$params->{_sequence}}, $a;
                next;
            }

            if (ref $a eq ref {}) {
                push @{$params->{_sequence}},
                    Net::Appliance::Session::Action->new($a);
                next;
            }

            confess "don't know what to do with a: '$a'\n";
        }
        delete $params->{actions};
    }

    return $params;
}

sub clone {
    my $self = shift;
    return Net::Appliance::Session::ActionSet->new({
        actions => [ map { $_->clone } $self->_sequence ],
        _callbacks => $self->_callbacks,
    });
}

# store params to the set, used when send is passed via sprintf
sub apply_params {
    my ($self, @params) = @_;

    $self->reset;
    while ($self->has_next) {
        my $next = $self->next;
        $next->params($params[$self->idx] || []);
    }

    return $self; # required
}

has _callbacks => (
    is => 'rw',
    isa => 'ArrayRef[CodeRef]',
    required => 0,
    default => sub { [] },
);

sub register_callback {
    my $self = shift;
    $self->_callbacks([ @{$self->_callbacks}, shift ]);
}

sub execute {
    my $self = shift;
    $self->reset;
    while ($self->has_next) {
        $_->($self->next) for @{$self->_callbacks};
    }
}

# pad out the Actions with match Actions if needed between send pairs
before 'execute' => sub {
    my ($self, $current_match) = @_;
    confess "execute requires the current match action as a parameter\n"
        unless defined $current_match
            and ref $current_match eq 'Net::Appliance::Session::Action'
            and $current_match->type eq 'match';

    $self->reset;
    while ($self->has_next) {
        my $this = $self->next;
        my $next = $self->peek or last; # careful...
        next unless $this->type eq 'send' and $next->type eq 'send';

        $self->insert_at($self->idx + 1, $current_match);
    }
};

# carry-forward a continuation beacause it's the match
# which really does the heavy lifting there
before 'execute' => sub {
    my $self = shift;

    $self->reset;
    while ($self->has_next) {
        my $this = $self->next;
        my $next = $self->peek or last; # careful...
        next unless $this->type eq 'send'
            and defined $this->continuation
            and $next->type eq 'match';

        $next->continuation( $this->continuation );
    }
};

# marshall the responses so as to move data from match to send
after 'execute' => sub {
    my $self = shift;

    $self->reset;
    while ($self->has_next) {
        my $send = $self->next;
        my $match = $self->peek or last; # careful...
        next unless $match->type eq 'match';

        my $response = $match->response; # need an lvalue
        my $cmd = $send->value;
        $response =~ s/^$cmd\s+//;

        if ($response =~ s/(\s+)(\S+)\s*$/$1/) {
            $match->response($2);
            $send->response($response);
        }
    }
};

1;
