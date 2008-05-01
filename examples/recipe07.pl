use strict;
use warnings;

use Net::Appliance::Session;

my $device_ip = shift @ARGV; # get the IP address from the command line
my @cmd       = @ARGV; # get the commands from the command line

# check we have passed at least one command
unless ($cmd[0]) {
    print qq(Usage : Recipe_07.pl <device_ip> "<ios_conf_command>" );
    print qq([ "<ios_conf_command>" .. "<ios_conf_command>" ]\n);
    exit 1;
}

# common username and password for all devices
my $ios_username        = 'cisco';
my $ios_password        = 'cisco';

my $session_obj = Net::Appliance::Session->new(
    Host      => $device_ip,
    Transport => 'Telnet',
);

$session_obj->input_log(*STDOUT);

# tell our object we'll be in privileged mode straight after login
$session_obj->do_privileged_mode(0);    

# start eval block to trap errors in interactive session
eval {
    
    # try to login to the ios device, ignoring host check
    $session_obj->connect(Name => $ios_username, Password => $ios_password);
    
    # go in to conf mode (i.e. 'conf t')
    $session_obj->begin_configure;
    
    for my $conf_cmd (@cmd) {
        $session_obj->cmd($conf_cmd);
    }
    
    # uncomment these lines to write the changes to the startup config
    #$session_obj->end_configure;
    #$session_obj->cmd("write memory");
    
};

# close down our session
$session_obj->close;

# did we get an error ?
if ($@) {
    print error_report($@, $device_ip);
}
    
sub error_report {
    
    # standard subroutine used to extract failure info when
    # interactive session fails
    
    my $err         = shift or croak("No err !");
    my $device_name = shift or croak("No device name !");
    
    my $report; # holder for report message to return to caller
    
    if ( UNIVERSAL::isa($err, 'Net::Appliance::Session::Exception') ) {
            
        # fault description from Net::Appliance::Session
        $report  =  "We had an error during our Telnet/SSH session to device  : $device_name \n"; 
        $report .= $err->message . " \n";
            
        # message from Net::Telnet
        $report .= "Net::Telnet message : " . $err->errmsg . "\n"; 
            
        # last line of output from your appliance  
        $report .=  "Last line of output from device : " . $err->lastline . "\n\n";

    }
    elsif (UNIVERSAL::isa($err, 'Net::Appliance::Session::Error') ) {
        
        # fault description from Net::Appliance::Session
        $report  = "We had an issue during program execution to device : $device_name \n";
        $report .=  $err->message . " \n";

    }
    else {
        
        # we had some other error that wasn't a deliberately created exception
        $report  = "We had an issue when accessing the device : $device_name \n";
        $report .= "The reported error was : $err \n";
    }
        
    return $report;
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
