#!/usr/bin/perl

use strict;
use warnings;

use Net::Appliance::Session;

# list of devices to contact
my @ios_device_ip_addresses = ('10.250.249.215', '10.250.249.216');

my $ios_username        = 'cisco';
my $ios_password        = 'cisco';

# step through each device in turn
for my $ios_device_ip ( @ios_device_ip_addresses ) {

    my @version_info; # array to hold data from device

    my $session_obj = Net::Appliance::Session->new(
        Host      => $ios_device_ip,
        Transport => 'SSH',
    );
    
    # start eval block to trap errors in interactive session
    eval {
    
        # try to login to the ios device, ignoring host check
        $session_obj->connect(
            Name => $ios_username,
            Password => $ios_password,
            SHKC => 0
        );
        
        # get our running config
        @version_info =  $session_obj->cmd('show ver');
        
        # close down our session
        $session_obj->close;
    };
    
    # check if we had an error
    if ($@) {
        my $err = $@;
        
        print "We had an issue when accessing the device : $ios_device_ip \n";
        print "The reported error was : $err \n\n";
    }
    else {
        print "Version infor for $ios_device_ip retrieved OK, here it is : \n\n"; 
        print @version_info;
    }

# end of for loop
}

#
# Copyright (c) Nigel Bowden 2007. All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 51 Franklin
# St, Fifth Floor, Boston, MA 02110-1301 USA
