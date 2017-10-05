#!/usr/bin/perl -w

# Load a transfer file.  The command line consists of the datasource, a
# "datasource_key" prefix, and the file name.  This will replace the
# record for that datasource, and then attempt to update the USER waypoint
# as much as possible.

use IO::File;

use strict;

#$| = 1; # for debugging

use WaypointTypes;

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

my $datasource = shift;
my $ds_prefix = shift;
my $fn = shift;

my $fh = new IO::File($fn) or die "Airport file $fn not found";

my @airportTypes = (
    "AIRPORT",
    "BALLOONPORT",
    "GLIDERPORT",
    "HELIPORT",
    "PLATFORM",
    "SEAPLANE BASE",
    "STOLPORT",
    "ULTRALIGHT",
    "PARACHUTE"
    );

my @navaidTypes = (
    "DME",
    "DVOR/DME",
    "FAN MARKER",
    "MARINE NDB",
    "NDB",
    "NDB/DME",
    "TACAN",
    "TVOR",
    "TVOR/DME",
    "UHF/NDB",
    "UNSPECIFIED NAVAID",
    "VOR",
    "VOR/DME",
    "VOR/TACAN",
    "VORTAC",
    "VOT");

my @fixTypes = (
    "AWY-INTXN",
    "CNF",
    "COORDN-FIX",
    "GPS-WP",
    "MIL-REP-PT",
    "MIL-WAYPOINT",
    "NRS-WAYPOINT",
    "RADAR",
    "REP-PT",
    "RNAV-WP",
    "VFR-WP",
    "WAYPOINT");

deleteWaypointData($datasource, 0);

my $datasource_key;
my $rep_pt_id;

while (<$fh>)
{
	chomp;

	next if /^\s*$/;
	next if /^\s*#/;

    # Get rid of any superflous spaces after commas.
    s/,  */,/g;
	my @record = split(",");
	my $rtype = $record[0];
	if (grep(/^$rtype$/, @airportTypes))
	{
    	my ($type, $id, $name, $state, $country,
			$latns, $latdeg, $latmin, $latsec,
            $longew, $longdeg, $longmin, $longsec,
            $decstring, $elev, $private) = @record;

        if ($id eq "")
        {
            print "can't load a record without an id", @_, "\n";
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

		$datasource_key = generateDSKey($id, $ds_prefix, $type, $state,
            $country, $lat, $long);
        if (!defined($private) || $private ne "1")
        {
            $private = 0;
        }
		insertWaypoint($id, $datasource_key, $type, $name, "",
						$state, $country, $lat, $long, $decl, $elev,
						undef, $datasource, !$private,
                        0, undef);
	}
	elsif ($rtype eq "RWY")
	{
    	my ($type, $designation, $length, $width, $surface) = @record;

        next if (!defined($datasource_key));

        if ($width eq "")
        {
            $width = 0;
        }
		my ($len, $lm) = ($length =~ m/([0-9\.]*)([mf]?)/);
		if (defined($lm) && $lm eq "m")
		{
		  $len = $len / 0.3048;
		}

		my ($wid, $wm) = ($width =~ m/([0-9\.]*)([mf]?)/);
		if (defined($wm) && $wm eq "m")
		{
		  $wid = $wid / 0.3048;
		}

		insertRunway($datasource_key, $designation,
            $len, $wid,
			$surface, 0,
            undef, undef, undef, undef,
            undef, undef, undef, undef,
			$datasource, 0);
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
			$datasource, 0);
	}
	elsif ($rtype eq "TPA")
	{
    	my ($type, $tpa) = @record;

        next if (!defined($datasource_key));

		insertTPA($datasource_key, $tpa);
	}
	elsif (grep(/^$rtype$/, @navaidTypes))
	{
    	my ($type, $id, $name, $state, $country,
			$latns, $latdeg, $latmin, $latsec,
            $longew, $longdeg, $longmin, $longsec,
            $decstring, $freq) = @record;

        next if ($id eq "");

        # Get rid of ILS, LO, LLZ, and GP
        next if ($rtype =~ m/^GP /);
        next if ($rtype =~ m/^ILS /);
        next if ($rtype =~ m/^LO /);
        next if ($rtype =~ m/^LLZ /);

        $rtype =~ s/ .*//;
        $rtype =~ s?DVOR/DME?VOR/DME?;

		my $lat = convLatLong($latdeg, $latmin, $latsec, $latns);
		my $long = convLatLong($longdeg, $longmin, $longsec, $longew);

		$datasource_key = generateDSKey($id, $ds_prefix, $type, $state,
            $country, $lat, $long);

		my ($decl, $ew) = ($decstring =~ m/(.*)([EW])/);
        if (!defined($decl) || $decl eq "" || !defined($ew) || $ew eq "")
        {
            $decl = getMagVar($lat, $long, 0);
        }
        else
        {
            if ($ew eq "E")
            {
                $decl = -$decl;
            }
        }

		insertWaypoint($id, $datasource_key, $rtype, $name, "",
						$state, $country, $lat, $long, $decl, undef,
						$freq, $datasource, 1, 0, undef);
	}
	elsif (grep(/^$rtype$/, @fixTypes))
	{
    	my ($type, $id, $name, $state, $country,
			$latns, $latdeg, $latmin, $latsec,
            $longew, $longdeg, $longmin, $longsec,
            $sectional, $ifr_lo, $ifr_hi, $iap, $rnav) = @record;

		my $lat = convLatLong($latdeg, $latmin, $latsec, $latns);
		my $long = convLatLong($longdeg, $longmin, $longsec, $longew);

        if ($rtype eq "CRP")
        {
            $rtype = "REP-PT";
        }

		$datasource_key = generateDSKey($id, $ds_prefix, $type, $state,
            $country, $lat, $long);

		my $decl = getMagVar($lat, $long, 0);

        my $chartMap = 0;
        if (defined($sectional) &&
            ($sectional eq "Y" || $sectional eq "1"))
        {
            $chartMap |= WaypointTypes::WPTYPE_VFR;
        }
        if (defined($ifr_lo) &&
            ($ifr_lo eq "Y" || $ifr_lo eq "1"))
        {
            $chartMap |= WaypointTypes::WPTYPE_LOW_ENROUTE;
        }
        if (defined($ifr_hi) &&
            ($ifr_hi eq "Y" || $ifr_hi eq "1"))
        {
            $chartMap |= WaypointTypes::WPTYPE_HIGH_ENROUTE;
        }
        if (defined($iap) &&
            ($iap eq "Y" || $iap eq "1"))
        {
            $chartMap |= WaypointTypes::WPTYPE_APPROACH;
        }
        if (defined($rnav) &&
            ($rnav eq "Y" || $rnav eq "1"))
        {
            $chartMap |= WaypointTypes::WPTYPE_RNAV;
        }

		insertWaypoint($id, $datasource_key, $rtype, $name, "",
						$state, $country, $lat, $long, $decl, undef,
						undef, $datasource, 1, $chartMap, undef);
        $rep_pt_id = $id;
	}
	elsif ($rtype eq "FIX")
	{
    	my ($type, $navaid, $navaid_type, $radial, $distance) = @record;

        $navaid_type =~ s?DVOR/DME?VOR/DME?;

		insertFix($rep_pt_id, $datasource_key, $datasource, 
            $navaid, $navaid_type, $radial, $distance, undef);
	}
    elsif ($rtype eq "NOTE")
    {
    }
    else
    {
        print "unknown type $rtype\n";
    }
}

updateDatasourceExtents($datasource, 0);

print "Done loading\n";

post_load();

finish();
print "Done\n";

undef $fh;
