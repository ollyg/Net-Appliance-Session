package Net::Appliance::Session::Transport::Serial;

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

# sets up new pseudo terminal connected to cu, running in
# a child process.

sub _connect_core {
    my $self = shift;
    my %args = @_;

    $args{Parity} = 'none'        if !exists $args{Parity};
    $args{Nostop} = 1             if !exists $args{Nostop};
    $args{Line}   = '/dev/ttyS0'  if !exists $args{Line};
    $args{Speed}  = 9600          if !exists $args{Speed};
    $args{Sleep}  = 0             if !exists $args{Sleep};
    $args{App}    = '/usr/bin/cu' if !exists $args{App};

    if ($self->do_login and ! defined $args{Password}) {
        raise_error "'Password' is a required parameter to connect"
                    . "when using active login";
    }

    # start the cu session, and get a pty for it
    my $pty = $self->_spawn_command(
        $args{App},
        ($args{Nostop} ? '--nostop' : '' ),
        '--line',   $args{Line},
        '--parity', $args{Parity},
        '--speed',  $args{Speed},
    )
        or raise_error 'Unable to launch cu subprocess';

    # set new pty as Net::Telnet's IO
    $self->fhopen($pty);

    # wake the serial connection up
    sleep $args{Sleep};
    $self->put("\r");

    # optionally, log in to the remote host
    if ($self->do_login) {

        # some systems prompt for username, others don't, so we do this
        # the long way around...

        my $match;
        (undef, $match) = $self->waitfor($self->pb->fetch('userpass_prompt'))
            or $self->error('Failed to get first prompt');

        if ($match =~ eval 'qr'. $self->pb->fetch('user_prompt')) {

            # delayed check, only at this point know if Name was required
            if (! defined $args{Name}) {
                raise_error "'Name' is a required parameter to connect"
                            . "when connecting to this host";
            }

            $self->print($args{Name});
            $self->waitfor($self->pb->fetch('pass_prompt'))
                or $self->error('Failed to get password prompt');
        }

        $self->cmd($args{Password})
            or $self->error('Login failed at password prompt');
    }
    else {
        $self->waitfor($self->prompt)
            or $self->error('Connection failed');
    }

    return $self;
}

# ===========================================================================

1;

=head1 NAME

Net::Appliance::Session::Transport::Serial

=head1 SYNOPSIS

 $s = Net::Appliance::Session->new(
    Host      => 'hostname.example',
    Transport => 'Serial',
 );

 $s->connect(
    Name     => $username, # required if logging in
    Password => $password, # required if logging in
 );

=head1 DESCRIPTION

This package sets up a new pseudo terminal, connected to a serial
communication program running in a spawned process, which is then bound into
C<< Net::Telnet >> for IO purposes.

=head1 CONFIGURATION

This module hooks into Net::Appliance::Session via its C<connect()> method.
Parameters are supplied to C<connect()> in a hash of named arguments.

=head2 Required Parameters

=over 4

=item C<Name>

If log-in is enabled (i.e. you have not disabled this via C<do_login()>),
I<and> the remote host requests a username, then you must also supply a
username in the C<Name> parameter value. The username will be stored for
possible later use by C<begin_privileged()>.

=item C<Password>

If log-in is enabled (i.e. you have not disabled this via C<do_login()>) then
you must also supply a password in the C<Password> parameter value. The
password will be stored for possible later use by C<begin_privileged()>.

=back

=head2 Optional Parameters

=over 4

=item C<Parity>

You have a choice of C<even>, C<odd> or C<none> for the parity used in serial
communication. The default is C<none>, and override this by passing a value in
the C<Parity> named parameter.

=item C<Nostop>

You can control whether to use C<XON/XOFF> handling for the serial
communcation. The default is to disable this, so to enable it pass any False
value in the C<Nostop> named parameter (yes, this is counter-intuitive,
sorry).

=item C<Line>

This named parameter is used to specify the local system device through which
a serial connection is made. The default is C</dev/ttyS0> and you can override
that by passing an alternate value to the C<Line> named parameter. Make sure
you have write access to the device.

=item C<Speed>

You can set the speed (or I<baud rate>) of the serial line by passing a value
to this named parameter. The default is to use a speed of C<9600>.

=item C<Sleep>

After a connection is made to the device, one carriage return character is
sent, and then this module looks to see whether there is a login or command
prompt. If it doesn't see one after 10 seconds, it will time out and die.

Before the carriage return is sent you can request that the module pause,
perhaps to allow your device to display boot messages or other notices. The
default operation is not to sleep, so to override that pass an integer number
to the C<Sleep> named parameter, which will be the number of seconds to wait
before sending that carriage return.

=item C<App>

You can override the default location of your C<cu> application binary by
providing a value to this named parameter. This module expects that the binary
is a version of Ian Lance Taylor's C<cu> application.

 $s->connect(
    Name     => $username,
    Password => $password,
    App      => '/usr/local/bin/cu',
 );

The default binary location is C</usr/bin/cu>.

=back

=head1 DEPENDENCIES

To be used, this module requires that your system have a working copy of 
Ian Lance Taylor's C<cu> application installed.

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
