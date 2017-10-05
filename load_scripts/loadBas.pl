#!/usr/bin/perl -w
# Load Australian VFR-WP from Bas Scheffers
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
my $fh = new IO::File($fn) or die "Airport file $fn not found";

startDatasource(Datasources::DATASOURCE_AS_BS);

while (<$fh>)
{
	chomp;

	#next if /^$/;
	#next if /^#/;
	#next if /^\t/;

	my @record = split(",", $_);

	my ($long, $lat,
		$id, $name, $state) = @record;
	
	my $country = "AS";

	my $type = $default_wpt_type;

	#print "getting mag var for $id ($lat, $long, $elev)\n";
	#my $decl = getMagVar($lat, $long, $elev);
	#print "got $decl\n";

	utf8::upgrade($name);

	my %waypoint;
	$waypoint{id} = $id;
	$waypoint{type} = $type;
	$waypoint{name} = $name;
	$waypoint{state} = $state;
	$waypoint{country} = $country;
	$waypoint{latitude} = $lat;
	$waypoint{longitude} = $long;
	$waypoint{ispublic} = 1;
	$waypoint{orig_datasource} = Datasources::DATASOURCE_AS_BS;

	insertWaypoint(\%waypoint);
}

close($fh);

endDatasource(Datasources::DATASOURCE_AS_BS);

postLoad();

dbClose();
print "Done\n";
