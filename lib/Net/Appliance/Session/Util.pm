package Net::Appliance::Session::Util;

use strict;
use warnings FATAL => 'all';

use base 'Exporter';

our @EXPORT = qw(_normalize);

# ===========================================================================

sub _normalize {
    my %oldargs = @_;
    my %newargs;
    foreach my $oldkey (keys %oldargs) {
        $newargs{lc $oldkey} = $oldargs{$oldkey};
    }
    return %newargs;
}

# ===========================================================================

1;

# Copyright (c) The University of Oxford 2006. All Rights Reserved.
# 
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
# 
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 51
# Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
