#!/usr/bin/perl -w
# Load Blake Crosby's VFR Waypionts.
#
use IO::File;

use strict;

$| = 1; # for debugging

use Datasources;
use WPInfo;

use PostGIS;
PostGIS::initialize();

my $default_wpt_type = "VFR-WP";

my $fn = shift;
print "doing $fn\n";
my $fh = new IO::File($fn) or die "VFR Waypoint file $fn not found";

startDatasource(Datasources::DATASOURCE_CA_BC);

while (<$fh>)
{
	chomp;

	next if /^$/;
	next if /^#/;
	next if /^\t/;

	s/$//g;

	my @record = split(/\|/, $_);

	my ($name, $province, $country, $id, $lat, $long)
		= @record;
print "name = $name, lat = $lat, long = $long\n";

	my $type = $default_wpt_type;

	if ($province eq "NL")
	{
	  $province = "NF";
	}

	#print "getting mag var for $id ($lat, $long, $elev)\n";
	my $decl = getMagVar($lat, $long, 0);
	#print "got $decl\n";

	utf8::upgrade($name);

	my %waypoint;
	$waypoint{id} = $id;
	$waypoint{type} = $type;
	$waypoint{name} = $name;
	$waypoint{state} = $province;
	$waypoint{country} = $country;
	$waypoint{latitude} = $lat;
	$waypoint{longitude} = $long;
	if (defined($decl))
	{
	  $decl += 0;
	}
	$waypoint{declination} = $decl;
	$waypoint{ispublic} = 1;
	$waypoint{orig_datasource} = Datasources::DATASOURCE_CA_BC;

	insertWaypoint(\%waypoint);
}

close($fh);

endDatasource(Datasources::DATASOURCE_CA_BC);

postLoad();

dbClose();
print "Done\n";
