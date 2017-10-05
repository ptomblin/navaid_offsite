#!/usr/bin/perl -w
#
# Test the new functions in PostGIS.

BEGIN
{
  push @INC, "/home/ptomblin/navaid_local/perl";
}

use PostGIS;

use strict;

PostGIS::initialize();

my $kroc = getWaypoint(82857);

$kroc->{lastmajorupdate} = localtime();
PostGIS::deleteWaypoint($kroc->{internalid}, $kroc->{areaid});
PostGIS::putWaypoint($kroc);

dbClose();
