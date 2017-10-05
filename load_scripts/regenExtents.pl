#!/usr/bin/perl -w

# FAA ed8
#

use DBI;

$| = 1; # for debugging

use Datasources;
use WaypointTypes;
use WPInfo;

use DBLoad;
DBLoad::initialize();

#updateDatasourceExtents(Datasources::DATASOURCE_COMBINED_USER,0);

print "Done loading\n";

post_load();

finish();
