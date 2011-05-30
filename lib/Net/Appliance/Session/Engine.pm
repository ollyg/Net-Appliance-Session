package Net::Appliance::Session::Engine;

use Moose::Role;

sub enable_paging {
    my $self = shift;

    return 0 unless $self->do_paging;
    return 0 unless $self->logged_in;

    my $privstate = $self->in_privileged_mode;
    $self->begin_privileged if $self->privileged_paging;

    $self->macro('paging_cmd', { params => [
        $self->get_pager_enable_lines
    ]} );

    $self->end_privileged
        if $self->privileged_paging and not $privstate;
}

sub disable_paging {
    my $self = shift;

    return 0 unless $self->do_paging;
    return 0 unless $self->logged_in;

    my $privstate = $self->in_privileged_mode;
    $self->begin_privileged if $self->privileged_paging;

    $self->macro('paging_cmd', { params => [
        $self->get_pager_disable_lines
    ]} );

    $self->end_privileged
        if $self->privileged_paging and not $privstate;
}

# method to enter privileged mode on the remote device.
# optionally, use a different username and password to those
# used at login time. if using a different username then we'll
# explicily login rather than privileged.

sub begin_privileged {
    my $self = shift;

    return 0 unless $self->do_privileged_mode;
    return 0 if $self->in_privileged_mode;

    confess 'must connect before you can begin_privileged'
        unless $self->logged_in;

    # rt.cpan#47214 check if we are already enabled by peeking the prompt
    if ($self->prompt_looks_like('privileged_prompt')) {
        $self->in_privileged_mode(1);
        return;
    }

    # default is to re-use login credentials
    my $username = $self->get_username;
    my $password = $self->get_password;

    # interpret optional params
    if (scalar @_ == 1) {
        $password = shift;
    }
    elsif (scalar @_ == 2) {
        ($username, $password) = @_;
    }

    confess 'a set password is required before begin_privileged'
        if not $password;

    # decide whether to explicitly login or just enable
    if (defined($username) && $username ne $self->get_username) {
        $self->macro('begin_privileged_with_user_cmd');
    }
    else {
        $self->macro('begin_privileged_cmd');
    }

    # whether login or enable, we still must be prepared for username:
    # prompt because it may appear even with privileged
    if ($self->prompt_looks_like('user_prompt')) {
        confess 'a set username is required to enter priv on this host'
            if not $username;
  
        $self->cmd($username, { match => 'pass_prompt' });
    }

    $self->cmd($password, { match => 'prompt' });

    # fairly dumb check to see that we're actually in privileged and
    # not back at a regular prompt
    confess 'failed to enter privileged mode'
        unless $self->prompt_looks_like('privileged_prompt');

    $self->in_privileged_mode(1);
}

sub end_privileged {
    my $self = shift;
    
    return 0 unless $self->do_privileged_mode;
    return 0 unless $self->in_privileged_mode;

    confess 'must leave configure mode before leaving privileged mode'
        if $self->in_configure_mode;

    $self->macro('end_privileged_cmd');

    $self->in_privileged_mode(0);
}

sub begin_configure {
    my $self = shift;

    return 0 unless $self->do_configure_mode;
    return 0 if $self->in_configure_mode;

    confess 'must enter privileged mode before configure mode'
        unless $self->in_privileged_mode;

    # rt.cpan#47214 check if we are already in config by peeking the prompt
    if ($self->prompt_looks_like('configure_prompt')) {
        $self->in_configure_mode(1);
        return;
    }

    $self->macro('begin_configure_cmd');

    # fairly dumb check to see that we're actually in configure and
    # not still at a regular privileged prompt
    confess 'failed to enter configure mode'
        unless $self->prompt_looks_like('configure_prompt');

    $self->in_configure_mode(1);
}

sub end_configure {
    my $self = shift;

    return 0 unless $self->do_configure_mode;
    return 0 unless $self->in_configure_mode;

    $self->macro('end_configure_cmd');

    # we didn't manage to escape configure mode (must be nested?)
    if ($self->prompt_looks_like('configure_prompt')) {
        my $caller3 = (caller(3))[3];

        # max out at three tries to exit configure mode
        if ( $caller3 and $caller3 =~ m/end_configure$/ ) {
             confess 'failed to leave configure mode';
        }
        # try again to exit configure mode
        else {
            $self->end_configure;
        }
    }

    # return if recursively called
    my $caller1 = (caller(1))[3];
    if ( defined $caller1 and $caller1 =~ m/end_configure$/ ) {
        return;
    }

    $self->in_configure_mode(0);
}

1;
