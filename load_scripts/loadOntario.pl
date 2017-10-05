#!/usr/bin/perl -w

use IO::File;

use strict;

#$| = 1; # for debugging

use WaypointTypes;
use Datasources;

use DBLoad;
DBLoad::initialize();

sub convLatLong($$$$)
{
	my ($deg, $min, $sec, $nsew) = @_;
    my $latlong = $deg + ($min / 60.0) + ($sec / 3600.0);
    if ($nsew eq "S" || $nsew eq "E")
    {
        $latlong = -$latlong;
    }
	return $latlong;
}

my $fn = shift;

my $fh = new IO::File($fn) or die "Airport file $fn not found";

deleteWaypointData(Datasources::DATASOURCE_ON);
deleteCommFreqData(Datasources::DATASOURCE_ON);
deleteRunwayData(Datasources::DATASOURCE_ON);

my $datasource_key;

while (<$fh>)
{
	chomp;

	next if /^$/;
	next if /^#/;

	my @record = split(",", uc $_);
	my $rtype = $record[0];
	if ($rtype eq "AIRPORT")
	{
    	my ($type, $id, $name, $province,
			$latns, $latdeg, $latmin, $latsec,
            $longew, $longdeg, $longmin, $longsec,
            $decstring, $elev) = @record;
		my $lat = convLatLong($latdeg, $latmin, $latsec, $latns);
		my $long = convLatLong($longdeg, $longmin, $longsec, $longew);

		my ($decl, $ew) = ($decstring =~ m/(.*)([EW])/);
		if ($ew eq "E")
		{
			$decl = -$decl;
		}

		$datasource_key = "ON_".$type."_".$id;
		insertWaypoint($id, $datasource_key, $type, $name, "",
						$province, "CA", $lat, $long, $decl, $elev,
						undef, Datasources::DATASOURCE_ON, 1, 0, 0);
	}
	elsif ($rtype eq "VFR-WP")
	{
    	my ($type, $id, $name, $province,
			$latns, $latdeg, $latmin, $latsec,
            $longew, $longdeg, $longmin, $longsec)  = @record;
		my $lat = convLatLong($latdeg, $latmin, $latsec, $latns);
		my $long = convLatLong($longdeg, $longmin, $longsec, $longew);

        my $decl = getMagVar($lat, $long, 0);

		$datasource_key = "ON_".$type."_".$id;
		insertWaypoint($id, $datasource_key, $type, $name, "",
						$province, "CA", $lat, $long, $decl, 0,
						undef, Datasources::DATASOURCE_ON, 1,
                        WaypointTypes::WPTYPE_VFR, 0);
	}
	elsif ($rtype eq "RWY")
	{
    	my ($type, $designation, $length, $width, $surface) = @record;
		insertRunway($datasource_key, $designation, $length, $width,
			$surface, 0,
            undef, undef, undef, undef,
            undef, undef, undef, undef,
			Datasources::DATASOURCE_ON, 0);
	}
	elsif ($rtype eq "COMM")
	{
    	my ($type, $comm_type, $name, $freq) = @record;
		if ($comm_type eq "UNICOM")
		{
			$comm_type = "UNIC";
		}
		insertCommunication($datasource_key, $comm_type, $name, $freq,
			Datasources::DATASOURCE_ON, 0);
	}
}

updateDatasourceExtents(Datasources::DATASOURCE_ON);

print "Done loading\n";

post_load();

finish();
print "Done\n";

undef $fh;
