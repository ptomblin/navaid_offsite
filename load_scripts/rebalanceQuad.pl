#!/usr/bin/perl -w

use strict;

$| = 1; # for debugging

use PostGIS;
PostGIS::initialize();

fixBogusQuadCells();

#rebalanceQuadTree();

postLoad();

dbClose();
print "Done\n";
