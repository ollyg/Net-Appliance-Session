#!/usr/bin/perl -w
use strict;
use Test::More tests => 29;

# ------------------------------------------------------------------------

my $class;
BEGIN {
    $class = 'Net::Appliance::Session';
    use_ok($class);
}

# ------------------------------------------------------------------------

my $obj = undef;

eval {$obj = $class->new()};
isa_ok($obj => $class, 'new without Host' );

eval {$obj = $class->new('testhost.example')};
isa_ok( $obj => $class, 'new with Host' );

foreach (qw(
    logged_in
    in_privileged_mode
    in_configure_mode
    do_paging
    do_login
    do_privileged_mode
    do_configure_mode
    get_username
    get_password
    get_pager_disable_lines
    get_pager_enable_lines
    set_username
    set_password
    set_pager_disable_lines
    set_pager_enable_lines
    connect
    enable_paging
    disable_paging
    begin_privileged
    end_privileged
    in_privileged_mode
    begin_configure
    end_configure
    in_configure_mode
    close
    pb
)) {
    ok( $obj->can($_), "can do method $_");
}

