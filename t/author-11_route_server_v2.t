#!/usr/bin/perl

BEGIN {
  unless ($ENV{AUTHOR_TESTING}) {
    require Test::More;
    Test::More::plan(skip_all => 'these tests are for testing by the author');
  }
}


use strict; use warnings FATAL => 'all';
use Test::More 0.88;

BEGIN {
  if ($^O eq 'MSWin32') {
    Test::More::plan(skip_all => 'these tests are not for Win32 systems');
  }
}

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

like( $s->last_prompt, qr/\w+ ?>$/, 'command ran and last_prompt looks ok' );

my @out = $s->last_response;
cmp_ok( scalar @out, '==', 15, 'sensible number of lines in the command output');

done_testing;
