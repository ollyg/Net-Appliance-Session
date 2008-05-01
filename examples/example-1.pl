#!/usr/bin/perl -n

# This (fictional) example shows how you can save time if there are many
# devices that require manual login reconfiguration (e.g. no SNMP).
# 
# The program is a filter, so wants a list of hosts on standard input or a
# filename containing hosts as an argument, and will go through each one,
# connecting to and reconfiguring the device.

BEGIN {
    use strict;
    use warnings FATAL => 'all';

    use Net::Appliance::Session;
}

my $host = $_; chomp $host;
die "one and only param is a device FQDN or IP!\n"
    if ! defined $host;

my $s = Net::Appliance::Session->new($host);
$s->input_log(*STDOUT); # echo all I/O

eval {
    $s->connect(
        Name     => $username,
        Password => $password,
        SHKC     => 0, # SSH Strict Host Key Checking disabled
    );
    $s->begin_privileged; # use same pass as login

    # is this a device with FastEthernet or GigabitEthernet ports?
    # let's do a test and find out, for use in the later commands.

    my $type;
    $s->cmd(
        String => 'show interfaces status | incl 1/0/24',
        Output => \$type,
    );
    $type = $type =~ m/^Gi/ ? 'GigabitEthernet' : 'FastEthernet';

    # now actually do some work...

    $s->begin_configure;

    $s->cmd("interface ${type}1/0/13");
    $s->cmd('spanning-tree bpdufilter enable');
    $s->cmd("interface ${type}1/0/14");
    $s->cmd('spanning-tree bpdufilter enable');
    $s->cmd("interface ${type}1/0/15");
    $s->cmd('spanning-tree bpdufilter enable');

    $s->end_configure;
    $s->cmd('write memory');
    $s->end_privileged;
};
die $@ if $@;

$s->close;
