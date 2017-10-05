#!/usr/bin/perl -w

use DBI;

use strict;

#use Datasources;

use WPInfo;
use WaypointDB;

foreach my $country (sort(keys(%WaypointDB::countries)))
{
	my $cref = $WaypointDB::countries{$country};
	print "country = $country, max_lat = " . $cref->{"max_lat"} . "\n";
}

my ($sess_con, $wp_conn) = WaypointDB::connectDB();

$sess_con->disconnect();
$wp_conn->disconnect();
