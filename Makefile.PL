use inc::Module::Install 0.67;
perl_version '5.008001';
  
name        'Net-Appliance-Session';
all_from    'lib/Net/Appliance/Session.pm';

requires    'IO::Pty' => 0;
requires    'Net::Telnet' => 0;
requires    'Exception::Class' => 0;
requires    'UNIVERSAL::require' => 0;
requires    'Class::Accessor::Fast::Contained' => 0;
requires    'Class::Accessor' => 0.25;
requires    'Class::Data::Inheritable' => 0;
requires    'Net::Appliance::Phrasebook' => 1.7;

recommends  'IO::Interactive' => 0;
recommends  'Devel::REPL' => 0;
recommends  'Devel::REPL::Plugin::NAS' => 0;

test_requires  'Test::More' => 0;
test_requires  'Test::Pod' => 0;
test_requires  'Test::Pod::Coverage' => 0;

WriteAll;

