package Net::Appliance::Session::Transport;

use strict;
use warnings FATAL => 'all';

use Net::Appliance::Session::Exceptions;
use Net::Appliance::Session::Util;
use Net::Telnet;
use FileHandle;
use IO::Pty;
use POSIX qw(WNOHANG);

# ===========================================================================
# base class for transports - just a Net::Telnet instance factory, really.

sub new {
    my $class = shift;
    return Net::Telnet->new(
        @_,
        Errmode => 'return',
    );
}

sub connect {
    my $self = shift;

    # interpret params into hash
    if (scalar @_ % 2) {
        raise_error 'Odd number of arguments to connect()';
    }
    my %args = _normalize(@_);

    $self->_connect_core( %args );

    if (! $self->get_username and exists $args{name}) {
        $self->set_username($args{name});
    }
    if (! $self->get_password and exists $args{password}) {
        $self->set_password($args{password});
    }

    $self->logged_in(1);

    $self->in_privileged_mode( $self->do_privileged_mode ? 0 : 1 );
    $self->in_configure_mode( $self->do_configure_mode ? 0 : 1 );

    # disable paging... this is undone in our close() method
    $self->disable_paging if $self->do_paging;

    return $self;
}

sub disconnect {
    return shift; # a noop unless overridden in the Transport subclass
}

sub _connect_core { 
    raise_error 'Incomplete Transport or there is no Transport loaded!';
}

# this code is based on that in Expect.pm, and found to be the most reliable.
# minor alterations to use CORE::close and raise_error, and to reap child.

sub REAPER {
    # http://www.perlmonks.org/?node_id=10516
    my $stiff;
    1 while (($stiff = waitpid(-1, &WNOHANG)) > 0);
    $SIG{CHLD} = \&REAPER;
}

sub _spawn_command {
    my $self = shift;
    my @command = @_;
    my $pty = IO::Pty->new();

    # try to install handler to reap children
    $SIG{CHLD} = \&REAPER
        if !defined $SIG{CHLD};

    # set up pipe to detect childs exec error
    pipe(STAT_RDR, STAT_WTR) or raise_error "Cannot open pipe: $!";
    STAT_WTR->autoflush(1);
    eval {
        fcntl(STAT_WTR, F_SETFD, FD_CLOEXEC);
    };

    my $pid = fork;

    if (! defined ($pid)) {
        raise_error "Cannot fork: $!" if $^W;
        return undef;
    }

    if($pid) { # parent
        my $errno;

        CORE::close STAT_WTR;
        $pty->close_slave();
        $pty->set_raw();

        # now wait for child exec (eof due to close-on-exit) or exec error
        my $errstatus = sysread(STAT_RDR, $errno, 256);
        raise_error "Cannot sync with child: $!" if not defined $errstatus;
        CORE::close STAT_RDR;
        
        if ($errstatus) {
            $! = $errno+0;
            raise_error "Cannot exec(@command): $!\n" if $^W;
            return undef;
        }

        # store pid for killing if we're in cygwin
        $self->childpid( $pid );
    }
    else { # child
        CORE::close STAT_RDR;

        $pty->make_slave_controlling_terminal();
        my $slv = $pty->slave()
            or raise_error "Cannot get slave: $!";

        $slv->set_raw();
        
        CORE::close($pty);

        CORE::close(STDIN);
        open(STDIN,"<&". $slv->fileno())
            or raise_error "Couldn't reopen STDIN for reading, $!\n";
 
        CORE::close(STDOUT);
        open(STDOUT,">&". $slv->fileno())
            or raise_error "Couldn't reopen STDOUT for writing, $!\n";

        CORE::close(STDERR);
        open(STDERR,">&". $slv->fileno())
            or raise_error "Couldn't reopen STDERR for writing, $!\n";

        { exec(@command) };
        print STAT_WTR $!+0;
        raise_error "Cannot exec(@command): $!\n";
    }

    return $pty;
}

# ===========================================================================

1;

=head1 NAME

Net::Appliance::Session::Transport

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

=head1 AUTHOR

Oliver Gorwits C<< <oliver.gorwits@oucs.ox.ac.uk> >>

=head1 COPYRIGHT & LICENSE

Copyright (c) The University of Oxford 2006. All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under
the terms of version 2 of the GNU General Public License as published by the
Free Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 51
Franklin
St, Fifth Floor, Boston, MA 02110-1301 USA

=cut

