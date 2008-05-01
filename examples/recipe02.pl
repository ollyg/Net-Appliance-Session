#!/usr/bin/perl

use strict;
use warnings;

use Net::Appliance::Session;

my $ios_device_ip = '10.250.249.215';

my $ios_username        = 'cisco';
my $ios_password        = 'cisco';
my $ios_enable_password = 'cisco';

my $running_config_file = "$ENV{HOME}/running_config.txt";

my $session_obj = Net::Appliance::Session->new(
    Host      => $ios_device_ip,
    Transport => 'SSH',
);

# give verbose output whilst we run this script
$session_obj->input_log(*STDOUT);

# try to login to the ios device, ignoring host check
$session_obj->connect(
    Name => $ios_username,
    Password => $ios_password,
    SHKC => 0
);

# drop in to enable mode
$session_obj->begin_privileged($ios_enable_password);

# get our running config
my @running_config =  $session_obj->cmd('show running');

# chop out the extra info top and bottom of the config
@running_config = @running_config[ 2 .. (@running_config -1)];

open(FH, "> $running_config_file")
  or die("Cannot open config file : $!");
print FH @running_config;
close FH;

# close down our session
$session_obj->close;

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
