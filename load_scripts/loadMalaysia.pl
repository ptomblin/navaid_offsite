#!/usr/bin/perl -w

use IO::File;

use strict;

#$| = 1; # for debugging

use Datasources;

use WPInfo;
use DBLoad;

my $wp_db_name = WPInfo::getLoadDB();
DBLoad::initialize($wp_db_name);

my %typemap = (
	"AIRPORT"				=>	"AIRPORT",
	"NDB"					=>	"NDB",
	"VFR REPORTING POINT"	=>	"VFR-WP",
	"LANDMARK"          	=>	"VFR-WP"
);

my %countrymap = (
	"MALAYSIA"				=>	"MY",
	"SINGAPORE"				=>	"SN"
);

sub parseLatLong($$$$)
{
	my ($nsew, $deg, $min, $sec) = @_;
	if ($min eq "")
	{
		$min = 0;
	}
	if ($sec eq "")
	{
		$sec = 0;
	}
	$sec =~ s/,/./;

	my $mult = 1.0;

	if ($nsew eq "E" || $nsew eq "S")
	{
		$mult = -1.0;
	}

	my $degrees = $deg + ($min/60.0) + ($sec/3600.0);

	return $degrees * $mult;
}


my $fn = shift;

my $fh = new IO::File($fn) or die "Airport file $fn not found";

deleteWaypointData(Datasources::DATASOURCE_MA_FC);

<$fh>;

while (<$fh>)
{
	chomp;
	my $line = uc;
    $line =~ s/"//g;

    my ($id, $name, $country, $latdeg, $latmin, $latsec, $latns,
                    $longdeg, $longmin, $longsec, $longew,
                    $magvar, $elev, $type, $freq, $source, $note) =
            split(",", $line);

    $country =~ s/^ //;
print "name = [$name], country = [$country]\n";

	if (exists($countrymap{$country}))
	{
		$country = $countrymap{$country};
	}
    else
    {
        die "invalid country $country";
    }

	my $lat = parseLatLong($latns, $latdeg, $latmin, $latsec);
	my $long = parseLatLong($longew, $longdeg, $longmin, $longsec);

	if (!defined($elev) || $elev eq "" || $elev =~ /^\s*$/ || $elev == 99999)
	{
		$elev = 0.0;
	}
	else
	{
		$elev =~ s/\s.*$//;
	}

	my $decl = 0;
	if ($magvar =~ m/[0-9]/)
	{
		$decl = 0 - $magvar;
	}
	if ($decl == 0)
	{
		$decl = getMagVar($lat, $long, $elev);
	}

	if (exists($typemap{$type}))
	{
		$type = $typemap{$type};
	}
    else
    {
        die "invalid type $type";
    }
	$id = substr($id, 0, 10);

	my $datasource_key = "MA_".$id;
	insertWaypoint($id, $datasource_key, $type, $name, "",
					"", $country, $lat, $long, $decl, $elev,
					"", Datasources::DATASOURCE_MA_FC, 1, 0);
}

updateDatasourceExtents(Datasources::DATASOURCE_MA_FC);

finish();

undef $fh;
