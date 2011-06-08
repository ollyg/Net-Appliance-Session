package Net::Appliance::Session::Transport;

{
    package # hide from pause
        Net::Appliance::Session::Transport::ConnectOptions;
    use Moose;

    has username => (
        is => 'ro',
        isa => 'Str',
        required => 0,
        predicate => 'has_username',
    );

    has password => (
        is => 'ro',
        isa => 'Str',
        required => 0,
        predicate => 'has_password',
    );
}

use Moose::Role;

sub connect {
    my $self = shift;
    my $options = Net::Appliance::Session::Transport::ConnectOptions->new(@_);

    $self->set_username($options->username) if $options->has_username;
    $self->set_password($options->password) if $options->has_password;

    # SSH transport takes a username if we have one
    $self->nci->transport->connect_options->username($self->username)
        if $self->has_username
           and $self->nci->transport->connect_options->meta->find_attribute_by_name('username');

    # poke remote device (whether logging in or not)
    $self->find_prompt($self->wake_up);

    # optionally, log in to the remote host
    if ($self->do_login and not $self->prompt_looks_like('prompt')) {

        if ($self->prompt_looks_like('user')) {
            die 'a set username is required to connect to this host'
                if not $self->has_username;

            $self->cmd($self->username, { match => 'pass' });
        }

        die 'a set password is required to connect to this host'
            if not $self->has_password;

        $self->cmd($self->password, { match => 'prompt' });
    }

    $self->prompt_looks_like('prompt')
        or die 'login failed to remote host - prompt does not match';

    $self->close_called(0);
    $self->logged_in(1);

    $self->in_privileged_mode( $self->do_privileged_mode ? 0 : 1 );
    $self->in_configure_mode( $self->do_configure_mode ? 0 : 1 );

    # disable paging... this is undone in our close() method
    $self->disable_paging if $self->do_paging;

    return $self;
}

sub close {
    my $self = shift;

    # protect against death spiral (rt.cpan #53796)
    return if $self->close_called;
    $self->close_called(1);

    $self->end_configure
        if $self->do_configure_mode and $self->in_configure_mode;
    $self->end_privileged
        if $self->do_privileged_mode and $self->in_privileged_mode;

    # re-enable paging
    $self->enable_paging if $self->do_paging;

    $self->nci->transport->disconnect;
    $self->logged_in(0);
}

1;
