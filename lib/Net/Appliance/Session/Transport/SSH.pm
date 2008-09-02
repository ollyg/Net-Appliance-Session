package Net::Appliance::Session::Transport::SSH;

use strict;
use warnings FATAL => 'all';

use base 'Net::Appliance::Session::Transport';
use Net::Appliance::Session::Exceptions;

# ===========================================================================

sub new {
    my $class = shift;
    my %args  = @_;

    my $self = $class->SUPER::new(
        %args,
        Binmode                 => 1,
        Cmd_remove_mode         => 1,
        Output_record_separator => "\r",
        Telnetmode              => 0,
    );

    return $self;
}

# sets up new pseudo terminal connected to ssh client running in
# a child process.

sub _connect_core {
    my $self = shift;
    my %args = @_;

    $args{opts} = []             if !exists $args{opts};
    $args{app}  = '/usr/bin/ssh' if !exists $args{app};

    if (! defined $args{name}) {
        raise_error "'Name' is a required parameter to SSH connect";
    }

    if ($self->do_login and ! defined $args{password}) {
        raise_error "'Password' is a required parameter to SSH connect"
                    . "when using active login";
    }

    if (! defined $self->host) {
        raise_error 'Cannot log in to an unspecified host!';
    }

    if (exists $args{shkc}) {
        push @{$args{opts}}, '-o', 'StrictHostKeyChecking='.
            ($args{shkc} ? 'yes' : 'no');
    }

    # start the SSH session, and get a pty for it
    my $pty = $self->_spawn_command(
        $args{app}, '-l', $args{name},
        @{$args{opts}},
        $self->host,
    )
        or raise_error 'Unable to launch ssh subprocess';

    # set new pty as Net::Telnet's IO
    $self->fhopen($pty);

    if ($self->do_login) {
        # from the Telnet Transport, we also check for username in SSH

        my $match;
        (undef, $match) = $self->waitfor($self->pb->fetch('userpass_prompt'))
            or $self->error('Failed to get first prompt');

        if ($match =~ eval 'qr'. $self->pb->fetch('user_prompt')) {

            # delayed check, only at this point do we know if Name was required
            if (! defined $args{name}) {
                raise_error "'Name' is a required parameter to SSH connect "
                            . "when connecting to this host";
            }

            $self->print($args{name});
            $self->waitfor($self->pb->fetch('pass_prompt'))
                or $self->error('Failed to get password prompt');
        }

        # cannot cmd() here because sometimes there's a "helpful"
        # login banner
        $self->print($args{password});
    }

    $self->waitfor($self->prompt)
        or $self->error('Login failed to remote host');

    return $self;
}

# ===========================================================================

1;

=head1 NAME

Net::Appliance::Session::Transport::SSH

=head1 SYNOPSIS

 $s = Net::Appliance::Session->new(
    Host      => 'hostname.example',
    Transport => 'SSH',
 );

 $s->connect(
    Name     => $username, # required
    Password => $password, # required if logging in
 );

=head1 DESCRIPTION

This package sets up a new pseudo terminal, connected to an SSH client running
in a spawned process, which is then bound into C<< Net::Telnet >> for IO
purposes.

=head1 CONFIGURATION

This module hooks into Net::Appliance::Session via its C<connect()> method.
Parameters are supplied to C<connect()> in a hash of named arguments.

=head2 Prerequisites

Before calling C<connect()> you must have set the C<Host> key in your
Net::Appliance::Session object, either via the named parameter to C<new()> or
the C<host()> object method inherited from Net::Telnet.

=head2 Required Parameters

=over 4

=item C<Name>

A username must be passed in the C<Name> parameter otherwise the call will
die. This value is stored for possible later use by C<begin_privileged()>.

=item C<Password>

If log-in is enabled (i.e. you have not disabled this via C<do_login()>) then
you must also supply a password in the C<Password> parameter value. The
password will be stored for possible later use by C<begin_privileged()>.

=back

=head2 Optional Parameters

=over 4

=item C<SHKC>

Setting the value for this key to any False value will disable C<openssh>'s
Strict Host Key Checking. See the C<openssh> documentation for further
details. This might be useful where you are connecting to appliances for which
an entry does not yet exist in your C<known_hosts> file, and you do not wish
to be interactively prompted to add it.

 $s->connect(
    Name     => $username,
    Password => $password,
    SHKC     => 0,
 );

The default operation is to let C<openssh> use its default setting for
StrictHostKeyChecking. You can also set this option to true, of course.

=item C<App>

You can override the default location of your SSH application binary by
providing a value to this named parameter. This module expects that the binary
is a version of OpenSSH.

 $s->connect(
    Name     => $username,
    Password => $password,
    App      => '/usr/local/bin/openssh',
 );

The default binary location is C</usr/bin/ssh>.

=item C<Opts>

If you want to pass any other options to C<openssh> on its command line, then
use this option. C<Opts> should be an array reference, and each item in the
array will be passed to C<openssh>, separated by a singe space character. For
example:

 $s->connect(
    Name     => $username,
    Password => $password,
    Opts     => [
        '-p', '222',            # connect to non-standard port on remote host
        '-o', 'CheckHostIP=no', # don't check host IP in known_hosts file
    ],
 );

=back

=head1 DEPENDENCIES

To be used, this module requires that your system have a working copy of the
OpenSSH SSH client application installed.

=head1 AUTHOR

Oliver Gorwits C<< <oliver.gorwits@oucs.ox.ac.uk> >>

=head1 COPYRIGHT & LICENSE

Copyright (c) The University of Oxford 2006. All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of version 2 of the GNU General Public License as published by the
Free Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 51 Franklin
St, Fifth Floor, Boston, MA 02110-1301 USA

=cut
