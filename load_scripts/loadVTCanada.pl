#!/usr/bin/perl -w

use IO::File;

use strict;

#$| = 1; # for debugging

use Datasources;
use WPInfo;

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

deleteWaypointData(Datasources::DATASOURCE_CA_VT);
deleteCommFreqData(Datasources::DATASOURCE_CA_VT);
deleteRunwayData(Datasources::DATASOURCE_CA_VT);

while (my $fn = shift)
{
print "doing $fn\n";
my $fh = new IO::File($fn) or die "Airport file $fn not found";

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

		my $country = "CA";
		if ($province eq "FR")
		{
			$country = "FR";
			$province = "";
		}
		if ($province eq "ND")
		{
			$country = "US";
		}
		$datasource_key = "CA_VT_".$type."_".$id;
		insertWaypoint($id, $datasource_key, $type, $name, "",
						$province, $country, $lat, $long, $decl, $elev,
						undef, Datasources::DATASOURCE_CA_VT, 1, 0, undef);
	}
	elsif ($rtype eq "RWY")
	{
    	my ($type, $designation, $length, $width, $surface) = @record;
		insertRunway($datasource_key, $designation, $length, $width,
			$surface, 0,
            undef, undef, undef, undef,
            undef, undef, undef, undef,
			Datasources::DATASOURCE_CA_VT, undef);
	}
	elsif ($rtype eq "COMM")
	{
    	my ($type, $comm_type, $name, $freq) = @record;
		if ($comm_type eq "UNICOM")
		{
			$comm_type = "UNIC";
		}
		insertCommunication($datasource_key, $comm_type, $name, $freq,
			Datasources::DATASOURCE_CA_VT, undef);
	}
}

}
updateDatasourceExtents(Datasources::DATASOURCE_CA_VT);

post_load();

finish();
print "Done\n";
