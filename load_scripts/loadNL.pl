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
	"DVOR/DME"		=>	"VOR/DME",
	"NDB"			=>	"NDB",
	"TACAN"			=> "TACAN",
	"VOR"			=> "VOR",
	"VOR/DME"		=> "VOR/DME"
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

deleteWaypointData(Datasources::DATASOURCE_NL_HV);

<$fh>;

while (<$fh>)
{
	chomp;
	my $line = uc;

    my ($id, $name, $latdeg, $latmin, $latsec, $latns,
                    $longdeg, $longmin, $longsec, $longew,
                    $magvar, $elev, $notes) =
            split("\t", $line);

	# some of the records don't have n/s/e/w indicators
	if ($longew eq "")
	{
		$longew = "E";
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
	$magvar =~ s/,/./;
	if ($magvar =~ m/[0-9]/)
	{
		$decl = 0 - $magvar;
	}
	if ($decl == 0)
	{
		$decl = getMagVar($lat, $long, $elev);
	}

	my $freq = "";
	my @names = split(" ", $name);
	my $type = $names[$#names];

	if (exists($typemap{$type}))
	{
		$type = $typemap{$type};
		$freq = $notes;
	}
	else
	{
		$type = 'AIRPORT';
	}
	$id = substr($id, 0, 10);

	my $datasource_key = "NL_HV_".$id;
	insertWaypoint($id, $datasource_key, $type, $name, "",
					"", "NL", $lat, $long, $decl, $elev,
					$freq, Datasources::DATASOURCE_NL_HV, 1, 0);
}

updateDatasourceExtents(Datasources::DATASOURCE_NL_HV);

finish();

undef $fh;
