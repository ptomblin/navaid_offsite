#!/usr/bin/perl -w

use IO::File;

use strict;

#$| = 1; # for debugging

use WaypointTypes;
use Datasources;

use DBLoad;
DBLoad::initialize();

sub convDegrees($$)
{
	my ($deg, $dec) = @_;
    my $latlong = $deg + ($dec / 60.0);
	return $latlong;
}

my $apt_fn = shift;
my $vor_fn = shift;

my $apt_fh = new IO::File($apt_fn) or die "Airport file $apt_fn not found";
my $vor_fh = new IO::File($vor_fn) or die "VOR file $vor_fn not found";

deleteWaypointData(Datasources::DATASOURCE_CA_DR);
deleteCommFreqData(Datasources::DATASOURCE_CA_DR);
deleteRunwayData(Datasources::DATASOURCE_CA_DR);

my $datasource_key;
my $rep_pt_id;

while (<$apt_fh>)
{
	chomp;

	my @record = split(":", $_);
    my ($id, $location, $name, $elev, 
        $decldeg, $decldec,
        $latdeg, $latdec,
        $longdeg, $longdec,
        $freq, $other) = @record;

    my ($address, $prov) = ($location =~ m/(.*),\s+([A-Z][A-Z])/);
    my $decl = convDegrees($decldeg, $decldec);
    my $lat = convDegrees($latdeg, $latdec);
    my $long = convDegrees($longdeg, $longdec);

    $datasource_key = "CA_DR_APT_".$id;
    insertWaypoint($id, $datasource_key, "AIRPORT", $name, $address,
                    $prov, "CA", $lat, $long, $decl, $elev,
                    $freq, Datasources::DATASOURCE_CA_DR, 1, 0);
}

while (<$vor_fh>)
{
	chomp;
	my @record = split(":", $_);
    my ($id, $name, $freq, $null, 
        $decldeg, $decldec,
        $latdeg, $latdec,
        $longdeg, $longdec,
        $type, $other) = @record;
    my $decl = convDegrees($decldeg, $decldec);
    my $lat = convDegrees($latdeg, $latdec);
    my $long = convDegrees($longdeg, $longdec);
    my $prov = getProvince($lat, -$long);
    $datasource_key = "CA_DR_".$type."_".$id;
    if ($type eq "WPT")
    {
        $type = "WAYPOINT";
    }
    insertWaypoint($id, $datasource_key, $type, $name, "",
                    $prov, "CA", $lat, $long, $decl, 0,
                    $freq, Datasources::DATASOURCE_CA_DR, 1, 0);
}

updateDatasourceExtents(Datasources::DATASOURCE_CA_DR);

print "Done loading\n";

post_load();

finish();
print "Done\n";

undef $apt_fh;
undef $vor_fh;
