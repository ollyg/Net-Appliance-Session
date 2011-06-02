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

    # poke remote device (whether logging in or not)
    $self->find_prompt($self->wake_up);

    # optionally, log in to the remote host
    if ($self->do_login and not $self->prompt_looks_like('prompt')) {

        if ($self->prompt_looks_like('user_prompt')) {
            if (not $options->has_username) {
                die "'username' is a required parameter for this host";
            }

            $self->cmd($options->username, { match => 'pass_prompt' });
        }

        if (not $options->has_password) {
            die "'password' is a required parameter for this host";
        }

        $self->cmd($options->password, { match => 'prompt' });

        $self->set_username($options->username)
            if $options->has_username and not $self->get_username;

        $self->set_password($options->password)
            if exists $options->has_password and not $self->get_password;
    }

    $self->prompt_looks_like('prompt')
        or die 'login failed to remote host';

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

    $self->nci->disconnect;
    $self->logged_in(0);
}

1;
