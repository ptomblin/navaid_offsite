#!/usr/bin/perl -w

use IO::File;

use strict;

#$| = 1; # for debugging

use Datasources;

use WPInfo;
use DBLoad;

my $wp_db_name = WPInfo::getLoadDB();
DBLoad::initialize($wp_db_name);

my $fn = shift;

my $fh = new IO::File($fn) or die "Airport file $fn not found";

deleteWaypointData(Datasources::DATASOURCE_AUS_PR);

<$fh>;

while (<$fh>)
{
	chomp;
	my $line = uc;

    my ($name, $id, $state, $charlat, $charlong, $magVar, $lat, $long) =
            split(",", $line);
    $long = -$long;

    my $decl = getMagVar($lat, $long, 0);

	$id = substr($id, 0, 10);

	my $datasource_key = "AUSPR_".$id;
	insertWaypoint($id, $datasource_key, "AIRPORT", $name, "",
					$state, "AS", $lat, $long, $decl, 0,
					"", Datasources::DATASOURCE_AUS_PR, 1, 0);
}

updateDatasourceExtents(Datasources::DATASOURCE_AUS_PR);

finish();

undef $fh;
