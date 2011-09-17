#!/usr/bin/perl

BEGIN {
  if ($ENV{NOT_AT_HOME}) {
    require Test::More;
    Test::More::plan(skip_all => 'these tests can only be run by the author when at home');
  }
}

use strict; use warnings FATAL => 'all';
use Test::More 0.88;

BEGIN { use_ok( 'Net::Appliance::Session') }

my $s = new_ok( 'Net::Appliance::Session' => [{
    transport => "SSH",
    ($^O eq 'MSWin32' ?
        (app => '..\..\..\Desktop\plink.exe') : () ),
    host => '192.168.0.55',
    personality => "ios",
    connect_options => {
        shkc => 0,
        opts => [
            '-o', 'CheckHostIP=no',
        ],
    },
}]);

my @out = ();
ok( $s->connect({
    username => 'Cisco',
    password => ($ENV{IOS_PASS} || 'letmein'),
}), 'connected' );

# reported bug about using pipe command
ok( $s->cmd('show ver'), 'ran show ver' );

ok( $s->cmd('show ver | i PCA'), 'ran show ver - pipe for PCA' );
cmp_ok( (scalar $s->last_response), '=', 2, 'two lines of ver');

unlike ( scalar $s->cmd('show ver | i Processor'), qr/^\|/, 'no pipe at start of output' );
ok( eval{$s->close;1}, 'disconnected' );

done_testing;
