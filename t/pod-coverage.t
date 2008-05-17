#!perl -T

use Test::More;

eval "use Test::Pod::Coverage 1.04";
if ($@) {
    plan skip_all =>
        "Test::Pod::Coverage 1.04 required for testing POD coverage";
}
else {
    plan tests => 3;
}

pod_coverage_ok('Net::Appliance::Session');
pod_coverage_ok('Net::Appliance::Session::Transport', {also_private => [ qr/^new/, qr/connect/, 'REAPER' ]});
pod_coverage_ok('Net::Appliance::Session::Transport::SSH', {also_private => [ qr/^new/ ]});

