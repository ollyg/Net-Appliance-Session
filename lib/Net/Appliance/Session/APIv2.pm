package Net::Appliance::Session::APIv2;

use Moose;
extends 'Net::Appliance::Session';

{
    package # hide from pause
        Net::Appliance::Session::Exception;
    use Moose;
    use overload '""' => '_error_str';
    
    sub _error_str {
        my $self = shift;
        return $self->errmsg .', '.
               $self->message .' preceded by '.
               $self->lastline;
    };

    has 'message'  => ( is => 'ro', isa => 'Str', required => 1 );
    has 'errmsg'   => ( is => 'ro', isa => 'Str', required => 1 );
    has 'lastline' => ( is => 'ro', isa => 'Str', required => 1 );
}

sub BUILDARGS {
    my ($class, @params) = @_;
    my $args = {};
    
    if (scalar @params == 1) {
        return {
            host => $params[0],
            personality => 'ios',
            transport => 'ssh',
        };
    }

    my $param_hash = { @params };
    if (exists $param_hash->{Source}) {
        die 'Source parameter to new() is no longer supported. Please convert '
            .'your phrasebook to the Net::CLI::Interact format';
    }

    my $map = {
        Host => 'host',
        Platform => 'personality',
        Transport => 'transport',
    };

    foreach my $k (keys %$map) {
        $args->{ $map->{$k} } = $param_hash->{$k}
            if exists $param_hash->{$k};
    }

    $args->{connect_options} = {
        map {lc $_ => $param_hash->{$_}} keys %$param_hash
    };

    return $args;
}

sub _wrap {
    my ($self, $sub, @args) = @_;
    my ($ret, @ret);

    if (wantarray) {
        @ret = eval { $sub->(@args) };
    }
    else {
        $ret = eval { $sub->(@args) };
    }

    if ($@) {
        my $e = Net::Appliance::Session::Exception->new(
            message => $@,
            errmsg => 'version 3 of Net::Appliance::Session does not support exception objects',
            lastline => (eval {$self->last_response } || 'no response data'),
        );
        die $e;
    }
    else {
        return wantarray ? @ret : $ret;
    }
}

override 'connect' => sub {
    my ($self, @params) = @_;
    my $param_hash = { @params };

    my $map = {
        SHKC => sub { (shift)->nci->transport->connect_options->shkc(shift) },
        App  => sub { (shift)->nci->transport->app(shift) },
        Opts => sub { (shift)->nci->transport->connect_options->opts(shift) },
        Name => sub { (shift)->set_username(shift) },
        Password => sub { (shift)->set_password(shift) },
        Timeout => sub { (shift)->nci->transport->timeout(shift) },
        Line => sub { (shift)->nci->transport->connect_options->device(shift) },
        Parity => sub { (shift)->nci->transport->connect_options->parity(shift) },
        Nostop => sub { (shift)->nci->transport->connect_options->nostop(shift) },
        Speed => sub { (shift)->nci->transport->connect_options->speed(shift) },
    };

    foreach my $k (keys %$param_hash) {
        next unless exists $map->{$k};
        $map->{$k}->($self, $param_hash->{$k});
    }

    return $self->_wrap( sub { super() } );
};

override 'cmd' => sub {
    my ($self, @params) = @_;

    if (scalar @params == 1) {
        return $self->_wrap( sub { $self->nci->cmd($params[0]) } );
    }

    my $param_hash = { @params };
    my $cmd = $param_hash->{String};
    $self->nci->transport->timeout($param_hash->{Timeout})
        if exists $param_hash->{Timeout};

    my @output = ();
    if (exists $param_hash->{Match}) {
        my $match = (map {eval "qr$param_hash->{Match}"}
                         @{ $param_hash->{Match} });
        @output = $self->_wrap( sub { $self->nci->cmd->($cmd, { match => $match }) } );
    }
    else {
        @output = $self->_wrap( sub { $self->nci->cmd->($cmd) } );
    }

    if (exists $param_hash->{Output} and ref $param_hash->{Output}) {
        if (ref $param_hash->{Output} eq ref \'') {
            ${$param_hash->{Output}} = join '', @output;
        }
        else {
            $param_hash->{Output} = \@output;
        }
    }

    return @output;
};

around 'begin_privileged' => sub {
    my ($orig, $self, @params) = @_;
    
    if (scalar @params == 1) {
        return $self->_wrap( sub { $self->$orig->({
            password => $params[0],
        }) } );
    }
    elsif (scalar @params == 2) {
        return $self->_wrap( sub { $self->$orig->({
            username => $params[0],
            password => $params[1],
        }) } );
    }
    elsif (scalar @params >= 4) {
        my $param_hash = { @params };
        return $self->_wrap( sub { $self->$orig->({
            username => $param_hash->{Username},
            password => $param_hash->{Password},
        }) } );
    }
    # and that's why this API was dumped by the roadside.

    return $self->_wrap( sub { $self->$orig->() } );
};

sub error {
    my $self = shift;
    $self->_wrap( sub { die "the error() method is no longer available to call" } );
}

sub input_log {
    my $self = shift;
    $self->_wrap( sub { $self->set_global_log_at('debug') } );
}

1;
