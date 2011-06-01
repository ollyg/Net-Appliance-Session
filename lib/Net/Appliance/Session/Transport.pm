package Net::Appliance::Session::Transport;

{
    package # hide from pause
        Net::Appliance::Session::Transport::ConnectOptions;
    use Moose;

    has name => (
        is => 'ro',
        isa => 'Str',
        required => 0,
        predicate => 'has_name',
    );

    has password => (
        is => 'ro',
        isa => 'Str',
        required => 0,
        predicate => 'has_password',
    );
}

use Moose::Role;

# login using the specific transport
sub connect {
    my $self = shift;
    my $options = Net::Appliance::Session::Transport::ConnectOptions->new(@_);

    # poke remote device (whether logging in or not)
    $self->find_prompt($self->wake_up);

    # optionally, log in to the remote host
    if ($self->do_login and not $self->prompt_looks_like('prompt')) {

        if ($self->prompt_looks_like('user_prompt')) {
            if (not $options->has_name) {
                confess "'name' is a required parameter to Telnet connect "
                            . "when connecting to this host";
            }

            $self->cmd($options->name, { match => 'pass_prompt' });
        }

        if (not $options->has_password) {
            confess "'password' is a required parameter to connect";
        }

        $self->cmd($options->password, { match => 'prompt' });

        $self->set_username($options->name)
            if $options->has_name and not $self->get_username;

        $self->set_password($options->password)
            if exists $options->has_password and not $self->get_password;
    }

    $self->prompt_looks_like('prompt')
        or confess 'login failed to remote host';

    $self->logged_in(1);

    $self->in_privileged_mode( $self->do_privileged_mode ? 0 : 1 );
    $self->in_configure_mode( $self->do_configure_mode ? 0 : 1 );

    # disable paging... this is undone in our close() method
    $self->disable_paging if $self->do_paging;

    return $self;
}

1;

# ABSTRACT: Base class for Session Transports

=head1 DESCRIPTION

This package is the base class for all C<< Net::Appliance::Session >>
Transports. It is effectively a C<< Net::Telnet >> factory, which then calls
upon a derived class to do something with the guts of the TELNET connection
(perhaps rip it out and shove an SSH connection in there instead).

=head1 AVAILABLE TRANSPORTS

=over 4

=item *

L<Net::Appliance::Session::Transport::Serial>

=item *

L<Net::Appliance::Session::Transport::SSH>

=item *

L<Net::Appliance::Session::Transport::Telnet>

=back

=head1 ACKNOWLEDGEMENTS

The SSH command spawning code was based on that in C<Expect.pm> and is
copyright Roland Giersig and/or Austin Schutz.

=cut
