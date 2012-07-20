package Net::Appliance::Session::Async;
{
  $Net::Appliance::Session::Async::VERSION = '3.122020_001';
}

use Moose::Role;

sub put {
    my ($self, $cmd, $opts) = @_;
    $opts ||= {};
    return $self->nci->transport->put($cmd,
        ($opts->{no_ors} ? () : $self->nci->transport->ors));
}

sub say { return $_[0]->put( $_[1] ) }

sub gather {
    my ($self, $opts) = @_;
    $opts ||= {};
    $opts->{no_ors} = 1; # force no newline
    return $self->cmd('', $opts);
}

1;
