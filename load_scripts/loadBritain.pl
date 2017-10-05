#!/usr/bin/perl -w
# Dave Crispin's Britain data

use IO::File;

use strict;

#$| = 1; # for debugging

use WaypointTypes;
use Datasources;
use WPInfo;

use DBLoad;
my $wp_db_name = WPInfo::getLoadDB();
DBLoad::initialize($wp_db_name);

sub convLatLong($$$)
{
	my ($deg, $min, $nsew) = @_;
    my $latlong = $deg + ($min / 60.0);
    if ($nsew eq "S" || $nsew eq "E")
    {
        $latlong = -$latlong;
    }
	return $latlong;
}

my $fn = shift;

my $fh = new IO::File($fn) or die "Airport file $fn not found";

deleteWaypointData(Datasources::DATASOURCE_UK_DC);
deleteCommFreqData(Datasources::DATASOURCE_UK_DC);
deleteRunwayData(Datasources::DATASOURCE_UK_DC);

my $datasource_key = "";

while (<$fh>)
{
	chomp;

	next if /^$/;
	next if /^#/;

	my @record = split(",", uc $_);
	my $rtype = $record[0];
	if ($rtype eq "AIRPORT")
	{
    	my ($type, $id, $name, $country,
			$latns, $latdeg, $latmin, 
            $longew, $longdeg, $longmin,
            $null, $elev) = @record;
print "type = $type, id = $id, elev = $elev\n";

        if ($id eq "")
        {
            $datasource_key = "";
            next;
        }

		my $lat = convLatLong($latdeg, $latmin, $latns);
		my $long = convLatLong($longdeg, $longmin, $longew);
        # Ignore the given declination and get a new one.
        my $decl = getMagVar($lat, $long, $elev);

		$datasource_key = "UK_DC_".$type."_".$id;
		insertWaypoint($id, $datasource_key, $type, $name, "",
						"", $country, $lat, $long, $decl, $elev,
						undef, Datasources::DATASOURCE_UK_DC, 1, 0);
	}
	elsif ($rtype eq "RWY")
	{
        next if ($datasource_key eq "");

    	my ($type, $designation, $length, $width, $surface) = @record;
        $length = $length / .3048;
        $width = $width / .3048;
		insertRunway($datasource_key, $designation, $length, $width,
			$surface, 0,
            undef, undef, undef, undef,
            undef, undef, undef, undef,
			Datasources::DATASOURCE_UK_DC);
	}
	elsif ($rtype eq "COMM")
	{
        next if ($datasource_key eq "");

    	my ($type, $comm_type, $name, $freq) = @record;
		if ($comm_type eq "UNICOM")
		{
			$comm_type = "UNIC";
		}
		insertCommunication($datasource_key, $comm_type, $name, $freq,
			Datasources::DATASOURCE_UK_DC);
	}
	elsif ($rtype eq "NOTE")
	{
        next if ($datasource_key eq "");

        # We don't do anything with these.
    }
    else
    {
        die "unknown type $rtype";
    }
}

updateDatasourceExtents(Datasources::DATASOURCE_UK_DC);

finish();
print "Done\n";

undef $fh;
