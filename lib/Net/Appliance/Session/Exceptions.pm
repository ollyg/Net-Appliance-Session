package Net::Appliance::Session::Exceptions;

use strict;
use warnings FATAL => 'all';

use Symbol;

# ===========================================================================

sub import {

    # Exception::Class looks at caller() to insert raise_error into that
    # Namespace, so this hack means whoever use's us, they get a raise_error
    # of their very own.

    *{Symbol::qualify_to_ref('raise_error',caller())}
        = sub { Net::Appliance::Session::Error->throw(@_) };
}


# Rationale: normally tend to avoid exceptions in perl, because they're a
# little ugly to catch, however they are handy when we want to bundle extra
# info along with the usual die/croak string argument. Here, we're going to
# send some debugging from the SSH session along with exceptions.

use Exception::Class (
    'Net::Appliance::Session::Exception' => {
        description => 'Errors encountered during SSH sessions',
        fields      => ['errmsg', 'lastline'],
    },

    'Net::Appliance::Session::Error' => {
        description => 'Errors encountered during program execution',
#        alias       => 'raise_error',
    },
);

# just a wee hack to add newlines so we can miss them off in calls to
# raise_error -- overrides Exception::Class::full_message()
sub Net::Appliance::Session::Error::full_message {
    my $self = shift;
    
    my $msg = $self->message;
    $msg .= "\n" if $msg !~ /\n$/;
    
    return $msg;
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
