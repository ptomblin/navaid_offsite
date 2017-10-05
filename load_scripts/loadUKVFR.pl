#!/usr/bin/perl -w

use IO::File;

use strict;

$| = 1; # for debugging

use Datasources;
use WPInfo;
use WaypointTypes;

use PostGIS;

sub convertLatLong($)
{
  my $latLongDec = shift;
print "latLongDec = [$latLongDec]\n";
  my ($nsew, $deg, $min) = ($latLongDec =~ m/([NSEW])([0-9]*)([0-9][0-9]\.[0-9]*)/);
print "splits into $nsew, $deg, $min\n";
  my $ret = $deg + ($min/60.0);
  if ($nsew eq "S" or $nsew eq "W")
  {
	$ret = -$ret;
  }
  return $ret;
}

my $default_wpt_type = "VFR-WP";

my $fn = shift;
my $dbName = "navaid";
if ($fn eq "-d")
 {
  $dbName = shift;
  $fn = shift;
}
print "loading $fn into $dbName\n";

PostGIS::initialize($dbName);

my $fh = new IO::File($fn) or die "VFR WP file $fn not found";

startDatasource(Datasources::DATASOURCE_HANGAR);

my $idnum = 1;

while (<$fh>)
{
	chomp;

	my @record = split(/ *\t */, $_);

	my ($id, $lat, $lon, $name, $type, $crap)
		 = @record;
print "id = [$id], [$lat], [$lon], [$name], [$type]\n";

	$id =~ s/^ *//;

	my $country = "UK";

	$lat = convertLatLong($lat);
	$lon = convertLatLong($lon);

	$type = $default_wpt_type;

	my $decl = getMagVar($lat, $lon, 0.0);
	#print "got $decl\n";

	utf8::upgrade($name);

	my %waypoint;
	$waypoint{id} = "UKVRP" . $idnum;
	$idnum++;
	$waypoint{type} = $type;
	$waypoint{name} = $name;
	$waypoint{country} = $country;
	$waypoint{latitude} = $lat * 1.0;
	$waypoint{longitude} = $lon * 1.0;
	if (defined($decl))
	{
	  $decl += 0;
	}
	$waypoint{declination} = $decl;
	$waypoint{ispublic} = 1;
	$waypoint{chart_map} = WaypointTypes::WPTYPE_VFR;
	$waypoint{orig_datasource} = Datasources::DATASOURCE_HANGAR;

	insertWaypoint(\%waypoint);
}

close($fh);


endDatasource(Datasources::DATASOURCE_HANGAR);

postLoad();

dbClose();
print "Done\n";
