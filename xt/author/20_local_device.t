#!/usr/bin/perl

use strict; use warnings FATAL => 'all';
use Test::More 0.88;

BEGIN { use_ok( 'Net::Appliance::Session') }

my $s = new_ok( 'Net::Appliance::Session' => [{
    transport => "Telnet",
    ($^O eq 'MSWin32' ?
        (app => '..\..\..\Desktop\plink.exe') : () ),
    host => '192.168.0.55',
    personality => "cisco",
    do_paging => 0,
}]);

ok( $s->connect({ username => 'Cisco', password => ($ENV{IOS_PASS} || 'letmein') );

ok( $s->cmd('show clock'), 'ran show clock' );
cmp_ok( (scalar $s->last_response), '=', 1, 'one line of clock');

ok( $s->cmd('show version'), 'ran show ver, paging' );
cmp_ok( (scalar $s->last_response), '>', 20, 'lots of ver lines');

ok( $s->disable_paging );
ok( $s->cmd('show version'), 'ran show ver, no paging' );
cmp_ok( (scalar $s->last_response), '>', 20, 'lots of ver lines');

ok( $s->begin_privileged, 'begin priv, no pass' );
ok( $s->end_privileged, 'end priv' );
ok( $s->begin_privileged({password => ($ENV{IOS_PASS} || 'letmein')}),
    'begin priv, with pass' );

ok( $s->cmd('show ip int br'), 'ran show ip int br' );
cmp_ok( (scalar $s->last_response), '=', 6, 'six interface lines');

ok( $s->begin_configure, 'begin configure' );
ok( $s->end_configure, 'end configure' );

ok( $s->close, 'disconnected, backed out of privileged' );

done_testing;
