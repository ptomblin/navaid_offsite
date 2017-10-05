#!/usr/bin/perl -w

use IO::File;

use strict;

#$| = 1; # for debugging

use WaypointTypes;
use Datasources;

use DBLoad_lite;
DBLoad_lite::initialize();

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

deleteWaypointData(Datasources::DATASOURCE_EI_AM);
deleteCommFreqData(Datasources::DATASOURCE_EI_AM);
deleteRunwayData(Datasources::DATASOURCE_EI_AM);

my $datasource_key;
my $rep_pt_id;

while (<$fh>)
{
	chomp;

	next if /^\s*$/;
	next if /^\s*#/;

    # Sometimes he puts spaces after the commas.  I don't know why.
    s/, /,/g;
	my @record = split(",", uc $_);
	my $rtype = $record[0];
	if ($rtype eq "AIRPORT")
	{
    	my ($type, $id, $name, $country,
			$latns, $latdeg, $latmin, $latsec,
            $longew, $longdeg, $longmin, $longsec,
            $decstring, $elev, $private) = @record;

        if ($id eq "")
        {
            $datasource_key = undef;
            next;
        }

		my $lat = convLatLong($latdeg, $latmin, $latsec, $latns);
		my $long = convLatLong($longdeg, $longmin, $longsec, $longew);

		my ($decl, $ew) = ($decstring =~ m/(.*)([EW])/);
		if ($ew eq "E")
		{
			$decl = -$decl;
		}

		$datasource_key = "EI_".$type."_".$id;
        if (!defined($private) || $private ne "1")
        {
            $private = 0;
        }
		insertWaypoint($id, $datasource_key, $type, $name, "",
						"", $country, $lat, $long, $decl, $elev,
						undef, Datasources::DATASOURCE_EI_AM, !$private, 0);
	}
	elsif ($rtype eq "RWY")
	{
    	my ($type, $designation, $length, $width, $surface) = @record;

        next if (!defined($datasource_key));

        if ($width eq "")
        {
            $width = 0;
        }

		insertRunway($datasource_key, $designation,
            $length / 0.3048,
            $width / 0.3048,
			$surface, 0,
            undef, undef, undef, undef,
            undef, undef, undef, undef,
			Datasources::DATASOURCE_EI_AM);
	}
	elsif ($rtype eq "COMM")
	{
    	my ($type, $comm_type, $name, $freq) = @record;

        next if (!defined($datasource_key));

		if ($comm_type eq "UNICOM")
		{
			$comm_type = "UNIC";
		}
		insertCommunication($datasource_key, $comm_type, $name, $freq,
			Datasources::DATASOURCE_EI_AM);
	}
	elsif ($rtype eq "NAVAID")
	{
    	my ($type, $rtype, $id, $name, $country,
			$latns, $latdeg, $latmin, $latsec,
            $longew, $longdeg, $longmin, $longsec,
            $decstring, $elev, $freq) = @record;

        next if ($id eq "");

        # Get rid of ILS, LO, LLZ, and GP
        next if ($rtype =~ m/^GP /);
        next if ($rtype =~ m/^ILS /);
        next if ($rtype =~ m/^LO /);
        next if ($rtype =~ m/^LLZ /);

        $rtype =~ s/ .*//;

		my $lat = convLatLong($latdeg, $latmin, $latsec, $latns);
		my $long = convLatLong($longdeg, $longmin, $longsec, $longew);

		my ($decl, $ew) = ($decstring =~ m/(.*)([EW])/);
		if ($ew eq "E")
		{
			$decl = -$decl;
		}

		$datasource_key = "EI_".$rtype."_".$id;
		insertWaypoint($id, $datasource_key, $rtype, $name, "",
						"", $country, $lat, $long, $decl, $elev,
						$freq, Datasources::DATASOURCE_EI_AM, 1, 0);
	}
	elsif ($rtype eq "REP-PT")
	{
    	my ($type, $rtype, $id, $name, $country,
			$latns, $latdeg, $latmin, $latsec,
            $longew, $longdeg, $longmin, $longsec) = @record;
		my $lat = convLatLong($latdeg, $latmin, $latsec, $latns);
		my $long = convLatLong($longdeg, $longmin, $longsec, $longew);

        if ($rtype eq "CRP")
        {
            $rtype = "REP-PT";
        }

		my $decl = getMagVar($lat, $long, 0);

		$datasource_key = "EI_".$rtype."_".$id;
		insertWaypoint($id, $datasource_key, $rtype, $name, "",
						"", $country, $lat, $long, $decl, undef,
						undef, Datasources::DATASOURCE_EI_AM, 1, 1);
        $rep_pt_id = $id;
	}
	elsif ($rtype eq "DEFN")
	{
    	my ($type, $navaid, $navaid_type, $radial, $distance) = @record;
        $radial =~ s/R//;
        $distance =~ s/D//;

		insertFix($rep_pt_id, $datasource_key, Datasources::DATASOURCE_EI_AM, 
            $navaid, $navaid_type, $radial, $distance);
	}
    elsif ($rtype eq "NOTE")
    {
    }
    else
    {
        print "unknown type $rtype\n";
    }
}

updateDatasourceExtents(Datasources::DATASOURCE_EI_AM);

print "Done loading\n";

post_load();

finish();
print "Done\n";

undef $fh;
