use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Net::Appliance::Session',
    AUTHOR              => 'Oliver Gorwits <oliver.gorwits@oucs.ox.ac.uk>',
    VERSION_FROM        => 'lib/Net/Appliance/Session.pm',
    ABSTRACT_FROM       => 'lib/Net/Appliance/Session.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'IO::Pty' => 0,
        'Net::Telnet' => 0,
        'Exception::Class' => 0,
        'UNIVERSAL::require' => 0,
        'Class::Accessor::Fast::Contained' => 0,
        'Class::Accessor' => 0.25,
        'Net::Appliance::Phrasebook' => 0.1,
    },
    LICENSE             => 'GPLv2',
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Net-Appliance-Session-*' },
);
