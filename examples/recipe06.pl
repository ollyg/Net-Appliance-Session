use strict;
use warnings;
use Carp;

use Net::Appliance::Session;
use Config::INI::Simple;
use Text::CSV_XS;
use File::Basename;

# create Config::INI::Simple object and read in our ini file data
my $ini_filename = dirname($0) . "/setup.ini"; # where we can find ini file
my %ini_data = parse_ini_file($ini_filename);

# get the device credentials for our devices
my @device_data = parse_data_file($ini_data{device_csv_file});

# step through each device and try to get and store our configs 
DEVICE:
for my $device_ref (@device_data) {
    
    my $device_name = $device_ref->{device_name} || $device_ref->{device_ip};
    
    # set up some logging
    my $debug_log = "$ini_data{debug_dir}/$device_name.debug.log";
    my $error_log = "$ini_data{error_dir}/$device_name.error.log";
    
    # create our config file name
    my $file_timestamp = file_timestamp();
    my $running_config_file = "$ini_data{repository_dir}/$device_name.$file_timestamp.conf";
    
    # create our Net::Appliance::Session with the transport for this device
    my $session_obj = Net::Appliance::Session->new(
        Host      => $device_ref->{device_ip},
        Transport => $device_ref->{transport},
    );
    
    # send the debug for this session to a device-specific file
    $session_obj->input_log($debug_log);
    my @running_config;
    
    # generate the required fields for the priv_array subroutine
    my @priv_array = priv_array($device_ref);
    
    # tell our session object we don't need enable password if none supplied
    unless ($priv_array[0]) {
        $session_obj->do_privileged_mode(0);
    }
    
    # do our interactive (Telnet/SSH) stuff...
    eval {
    
        # try to login to the ios device, ignoring host check
        $session_obj->connect( connect_hash($device_ref), SHKC => 0 );
          
        if ( $priv_array[0] ) {
    
            # if we need to use some enable credentials, supply them
            $session_obj->begin_privileged( @priv_array );
        }
        
        # get our running config
        @running_config =  $session_obj->cmd('show running');
    };
    
    # did we get an error ?
    if ($@) {
        
        # log error to file and move on to next device
        log_error( error_report($@, $device_name), $error_log );
        next DEVICE;
    }
    
    # chop out the extra info top and bottom of the config
    @running_config = @running_config[ 2 .. (@running_config -1)];
    
    # dump the config to a file
    open(CONFIG , " > $running_config_file")
       or warn("Unable to open config file for : $device_name : $!");
    print CONFIG @running_config;
    close CONFIG;
    
    # close down our session
    $session_obj->close;
}   

#####################################
# Subroutines
#####################################
sub parse_ini_file {

    # parse our ini file to get the parameters we need in to
    # some convenient variables
    
    my $ini_filename = shift or croak("No ini file name passed");
    
    my $config_obj = Config::INI::Simple->new();

    $config_obj->read($ini_filename) or die("Cannot open ini file : $ini_filename (reason: $!)");
    
    my %ini_data; # variable to use as data hash to hold all ini file data
    
    # set up some variables for later use
    $ini_data{error_dir}        = $config_obj->{Logs}->{error_dir};
    $ini_data{debug_dir}        = $config_obj->{Logs}->{debug_dir};
    $ini_data{device_csv_file}  = $config_obj->{CSV}->{device_csv_file};
    $ini_data{repository_dir}   = $config_obj->{Repository}->{repository_dir};
    $ini_data{timestamp_format} = $config_obj->{Repository}->{timestamp_format};

    return %ini_data;
}

sub parse_data_file {
    
    # parse the CSV data file we are using to hold our  device
    # credential data
    
    my $device_csv_file = shift or croak("No csv file named passed");

    # create our csv object ready to parse in the data from our csv file
    my $csv_obj = Text::CSV_XS->new();
    
    #read in our csv file
    open my $csv_fh, "< $device_csv_file"
       or croak("Cannot open device csv file : $device_csv_file (reason: $!)");
    
    # take off the top row that has the field names
    my $top_row = $csv_obj->getline($csv_fh); 
    
    my @device_data;
    
    # take each entry in the CSV file and massage it into a complex
    # data structure
    while (my $data_row = $csv_obj->getline($csv_fh)) {
        my $hash_ref;
        map { ($hash_ref->{$_} = shift @$data_row) } @$top_row;
        
        push(@device_data, $hash_ref);
    }
    
    close $csv_fh;
    return @device_data;
}

sub connect_hash {
    
    # depending on the combination of credentials supplied, determine
    # the combination of login username/password to use
    
    my $device_ref = shift or croak("No device credentials ref passed !");

    # decide which set of credentials we have
    if ( exists($device_ref->{username}) && exists($device_ref->{password}) ) {
        
        # username & password supplied
        return ( Name => $device_ref->{username}, Password => $device_ref->{password} );
    }
    elsif ( exists($device_ref->{password}) ) {
        
        # password only supplied
        return ( Password => $device_ref->{password} );
    }
    else {
        croak("Invalid or missing credentials to log in to this device : "
                   . $device_ref->{device_name} );
    }
}

sub priv_array {
    
    # depending on the combination of credentials supplied, determine
    # the combination of enable username/password to use
    
    my $device_ref = shift or croak("No device credentials ref passed !");

    # decide which set of priv credentials we have
    if ( $device_ref->{enable_username} && $device_ref->{enable_password} ) {
        
        # username & password supplied
        return( $device_ref->{enable_username}, $device_ref->{enable_password} );
    }
    elsif ( $device_ref->{enable_password} ) {
        
        # password only supplied
        return( $device_ref->{enable_password} );
    }    
    elsif ( $device_ref->{enable_username} ) {
        
        # username only supplied - error !
        croak( "Invalid enable login credentials provided (only username provided !" );
    }    
    else {
        
        # no enble pwd required (assume drop straight in to enable mode)
        return 0;
    }
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

sub log_error {
    
    # log an error message to a file
    
    my $error_message = shift;
    my $file_name     = shift;
    
    open(ERR , " > $file_name") or carp("Unable to error file : $file_name : $!");
    print ERR $error_message;
    close ERR;
}

sub file_timestamp {

    # create a timestamp to add to the conf files created

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    
    if ($ini_data{timestamp_format} eq 'uk') {
    
        # UK format
        return sprintf( "%02d-%02d-%4d-%02d%02d", $mday, ($mon + 1), ($year + 1900), $hour, $min );
    }
    else {
        
        # US format
        return sprintf( "%02d-%02d-%4d-%02d%02d", ($mon + 1), $mday, ($year + 1900), $hour, $min );   
    }
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
