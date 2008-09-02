package Net::Appliance::Session::Engine;

use strict;
use warnings FATAL => 'all';

use base 'Class::Data::Inheritable';
use Net::Appliance::Session::Exceptions;
use Net::Appliance::Session::Util;

__PACKAGE__->mk_classdata(
    privileged_phrases => [qw/
        privileged_prompt
        begin_privileged_cmd
        begin_privileged_with_user_cmd
        end_privileged_cmd
    /]
);

__PACKAGE__->mk_classdata(
    configure_phrases => [qw/
        configure_prompt
        begin_configure_cmd
        end_configure_cmd
    /]
);

# ===========================================================================

sub enable_paging {
    my $self = shift;

    return 0 unless $self->do_paging;
    return 0 unless $self->logged_in;
    raise_error "Definition of 'paging_cmd' missing from phrasebook!"
        if ! eval {$self->pb->fetch('paging_cmd')};

    $self->cmd(
        $self->pb->fetch('paging_cmd') .' '. $self->get_pager_enable_lines
    )
        or $self->error('Failed to enable paging');

    return $self;
}

sub disable_paging {
    my $self = shift;

    return 0 unless $self->do_paging;
    return 0 unless $self->logged_in;
    raise_error "Definition of 'paging_cmd' missing from phrasebook!"
        if ! eval {$self->pb->fetch('paging_cmd')};

    $self->cmd(
        $self->pb->fetch('paging_cmd') .' '. $self->get_pager_disable_lines
    )
        or $self->error('Failed to disable paging');

    return $self;
}

# ===========================================================================

# method to enter privileged mode on the remote device.
# optionally, use a different username and password to those
# used at login time. if using a different username then we'll
# explicily login rather than privileged.

sub begin_privileged {
    my $self = shift;
    my $match;

    return 0 unless $self->do_privileged_mode;
    return 0 if $self->in_privileged_mode;

    # (optionally) check all necessary words are in our loaded phrasebook
    if ($self->check_pb) {
        my %k_available = map {$_ => 1} $self->pb->keywords;
        foreach my $k (@{ __PACKAGE__->privileged_phrases }) {
            $k_available{$k} or
                raise_error "Definition of '$k' missing from phrasebook!";
        }
    }

    raise_error 'Must connect before you can begin_privileged'
        unless $self->logged_in;

    # default is to reuse login credentials
    my $username = $self->get_username;
    my $password = $self->get_password;

    # interpret params
    if (scalar @_ == 1) {
        $password = shift;
    }
    elsif (scalar @_ == 2) {
        ($username, $password) = @_;
    }
    elsif (scalar @_ == 4) {
        my %args = _normalize(@_);
        $username = $args{name};
        $password = $args{password};
    }

    if (! $password) {
        raise_error "A set password is required before begin_privileged";
    }

    # decide whether to explicitly login or just enable
    if ($username ne $self->get_username) {
        $self->print($self->pb->fetch('begin_privileged_with_user_cmd'));
    }
    else {
        $self->print($self->pb->fetch('begin_privileged_cmd'));
    }

    # whether login or enable, we still must be prepared for username:
    # prompt because it may appear even with privileged

    (undef, $match) = $self->waitfor($self->pb->fetch('userpass_prompt'))
        or $self->error('Failed to get first privileged prompt');

    if ($match =~ eval 'qr'. $self->pb->fetch('user_prompt')) {
        # delayed check, Name is now required
        if (! $username) {
            raise_error "A set username is required to enter priv on this host";
        }
    
        $self->print($username);
        $self->waitfor($self->pb->fetch('pass_prompt'))
            or $self->error('Failed to get privileged password prompt');
    }

    # XXX: don't try to optimise away this print() and waitfor() into a cmd()
    # because they are needed to get the $match back!

    $self->print($password);
    (undef, $match) = $self->waitfor($self->prompt)
        or $self->error('Failed to get prompt after entering privileged mode');

    # fairly dumb check to see that we're actually in privileged and
    # not back at a regular prompt
    $self->error('Failed to enter privileged mode')
        if $match !~ eval 'qr'. $self->pb->fetch('privileged_prompt');

    $self->in_privileged_mode(1);

    return $self;
}

sub end_privileged {
    my $self = shift;
    
    return 0 unless $self->do_privileged_mode;
    return 0 unless $self->in_privileged_mode;

    raise_error 'Must leave configure mode before leaving privileged mode'
        if $self->in_configure_mode;

    $self->cmd(
        String => $self->pb->fetch('end_privileged_cmd'),
        Match  => [$self->pb->fetch('basic_prompt')],
    );

    $self->in_privileged_mode(0);

    return $self;
}

# ===========================================================================

# login and enable in cisco-land are actually versions of privileged
foreach (qw( login enable )) {
    *{Symbol::qualify_to_ref($_)} = \&begin_privileged;
}

# ===========================================================================

sub begin_configure {
    my $self = shift;

    return 0 unless $self->do_configure_mode;
    return 0 if $self->in_configure_mode;

    # (optionally) check all necessary words are in our loaded phrasebook
    if ($self->check_pb) {
        my %k_available = map {$_ => 1} $self->pb->keywords;
        foreach my $k (@{ __PACKAGE__->configure_phrases }) {
            $k_available{$k} or
                raise_error "Definition of '$k' missing from phrasebook!";
        }
    }

    raise_error 'Must enter privileged mode before configure mode'
        unless $self->in_privileged_mode;

    # XXX: don't try to optimise away this print() and waitfor() into a cmd()
    # because they are needed to get the $match back!

    $self->print($self->pb->fetch('begin_configure_cmd'));
    my (undef, $match) = $self->waitfor($self->prompt)
        or $self->error('Failed to get prompt after entering configure mode');

    # fairly dumb check to see that we're actually in configure and
    # not still at a regular privileged prompt

    $self->error('Failed to enter configure mode')
        if $match !~ eval 'qr'. $self->pb->fetch('configure_prompt');

    $self->in_configure_mode(1);

    return $self;
}

sub end_configure {
    my $self = shift;

    return 0 unless $self->do_configure_mode;
    return 0 unless $self->in_configure_mode;

    # XXX: don't try to optimise away this print() and waitfor() into a cmd()
    # because they are needed to get the $match back!

    $self->print($self->pb->fetch('end_configure_cmd'));
    my (undef, $match) = $self->waitfor($self->prompt)
        or $self->error('Failed to get prompt after exit in configure mode');

    # we didn't manage to escape configure mode (must be nested?)
    if ($match =~ eval 'qr'. $self->pb->fetch('configure_prompt')) {
        my $caller3 = (caller(3))[3];

        # max out at three tries to exit configure mode
        if ( $caller3 and $caller3 =~ m/end_configure$/ ) {
             $self->error('Failed to leave configure mode');
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

    return $self;
}

# ===========================================================================

1;

# Copyright (c) The University of Oxford 2006. All Rights Reserved.
# 
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
# 
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 51
# Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
