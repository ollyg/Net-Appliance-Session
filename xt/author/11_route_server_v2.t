#!/usr/bin/perl

use strict; use warnings FATAL => 'all';
use Test::More 0.88;

BEGIN { use_ok( 'Net::Appliance::Session::APIv2') }

my $s = new_ok( 'Net::Appliance::Session::APIv2' => [
    Transport => "Telnet",
    Host => "route-server.bb.pipex.net",
    Platform => "cisco",
]);

ok( eval {$s->do_login(0);1} );
ok( eval {$s->do_paging(0);1} );
ok( $s->connect );

ok( $s->cmd('show ip bgp 163.1.0.0/16'), 'ran show ip bgp 163.1.0.0/16' );

like( $s->nci->last_prompt, qr/\w+ ?>$/, 'command ran and prompt looks ok' );

my @out = $s->last_response;
cmp_ok( scalar @out, '>=', 5, 'sensible number of lines in the command output');

done_testing;
