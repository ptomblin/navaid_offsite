#!/usr/bin/perl -w

use IO::File;

use strict;

#$| = 1; # for debugging

use Datasources;
use WaypointTypes;
use WPInfo;

use DBLoad;
my $wp_db_name = WPInfo::getLoadDB();
DBLoad::initialize($wp_db_name);

my %country_codes = (
    "SWITZERLAND" => "SZ");

sub translateCountryCode($)
{
    my $longCountry = shift;
    my $shortCountry = $country_codes{$longCountry};
    if (!defined($shortCountry))
    {
        die "Unknown country code ". $longCountry;
    }
    return $shortCountry;
}

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

deleteWaypointData(Datasources::DATASOURCE_CH_MR);
deleteCommFreqData(Datasources::DATASOURCE_CH_MR);
deleteRunwayData(Datasources::DATASOURCE_CH_MR);

my $datasource_key;

while (<$fh>)
{
	chomp;

	next if /^$/;
	next if /^#/;

	my @record = split(",", uc $_);
	my $rtype = $record[0];
	if ($rtype eq "AIRPORT" || $rtype eq "GLIDERPORT" ||
        $rtype eq "HELIPORT")
	{
    	my ($type, $id, $name, $country,
			$latns, $latdeg, $latmin, $latsec,
            $longew, $longdeg, $longmin, $longsec,
            $decstring, $elev, $private) = @record;
		my $lat = convLatLong($latdeg, $latmin, $latsec, $latns);
		my $long = convLatLong($longdeg, $longmin, $longsec, $longew);
        my $cc = translateCountryCode($country);

		my ($decl, $ew) = ($decstring =~ m/(.*)([EW])/);
		if ($ew eq "E")
		{
			$decl = -$decl;
		}

        my $isPublic = (defined($private) && $private eq "PRIVATE") ? 0 : 1;

		$datasource_key = "CH_MR_".$type."_".$id;
		insertWaypoint($id, $datasource_key, $type, $name, "",
						"", $cc, $lat, $long, $decl, $elev,
						undef, Datasources::DATASOURCE_CH_MR, $isPublic, 0);
	}
	elsif ($rtype eq "RWY")
	{
    	my ($type, $designation, $length, $width, $surface) = @record;
        if (defined($length) && $length ne "")
        {
            $length = $length / .3048;
        }
        else
        {
            $length = 0;
        }
        if (defined($width) && $width ne "")
        {
            $width = $width / .3048;
        }
        else
        {
            $width = 0;
        }
		insertRunway($datasource_key, $designation, $length, $width,
			$surface, 0,
            undef, undef, undef, undef,
            undef, undef, undef, undef,
			Datasources::DATASOURCE_CH_MR);
	}
	elsif ($rtype eq "COMM")
	{
    	my ($type, $comm_type, $name, $freq) = @record;

        next if (!defined($freq));

		if ($comm_type eq "UNICOM")
		{
			$comm_type = "UNIC";
		}
		insertCommunication($datasource_key, $comm_type, $name, $freq,
			Datasources::DATASOURCE_CH_MR);
	}
	elsif ($rtype eq "VFR-WP")
	{
    	my ($type, $id, $name, $country,
			$latns, $latdeg, $latmin, $latsec,
            $longew, $longdeg, $longmin, $longsec, $decstring)  = @record;
		my $lat = convLatLong($latdeg, $latmin, $latsec, $latns);
		my $long = convLatLong($longdeg, $longmin, $longsec, $longew);
        my $cc = translateCountryCode($country);

        my ($decl, $ew);

        if (defined($decstring) && $decstring ne "")
        {
            ($decl, $ew) = ($decstring =~ m/(.*)([EW])/);
            if ($ew eq "E")
            {
                $decl = -$decl;
            }
        }
        else
        {
            $decl = getMagVar($lat, $long, 0);
        }

		$datasource_key = "CH_MR_".$type."_".$id;
		insertWaypoint($id, $datasource_key, $type, $name, "",
						"", $cc, $lat, $long, $decl, 0,
						undef, Datasources::DATASOURCE_CH_MR, 1,
                        WaypointTypes::WPTYPE_VFR);
	}
	elsif ($rtype eq "NOTE")
	{
        # We don't do anything with those yet
    }
	else
	{
        print "*** Unknown type $rtype ***\n";
    }
}

updateDatasourceExtents(Datasources::DATASOURCE_CH_MR);

finish();
print "Done\n";

undef $fh;
