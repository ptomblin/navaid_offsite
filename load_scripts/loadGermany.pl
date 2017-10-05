#!/usr/bin/perl -w

use IO::File;

use strict;

#$| = 1; # for debugging

use Datasources;
use WPInfo;
use WaypointTypes;

use DBLoad;
DBLoad::initialize();

my %typemap = (
	"DEM"		=>	"DME",
	"DME"		=>	"DME",
	"DVOR"		=>	"VOR",
	"DVORDME"	=>	"VOR/DME",
	"DVORTAC"	=>	"VORTAC",
	"NDB"		=>	"NDB",
	"NDBDME"	=>	"NDB/DME",
	"TVOR"		=>	"TVOR",
	"TVORDME"	=>	"TVOR/DME",
	"VOR"		=>	"VOR",
	"VORDME"	=>	"VOR/DME",
	"VORTAC"	=>	"VORTAC"
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

deleteWaypointData(Datasources::DATASOURCE_GR);

<$fh>;
<$fh>;

while (<$fh>)
{
	chomp;
	my $line = uc;

    my ($id, $name, $latdeg, $latmin, $latsec, $latns,
                    $longdeg, $longmin, $longsec, $longew,
                    $magvar, $elev) =
            split("\t", $line);

	next if ($latdeg eq "" and $longdeg eq "");

	my $lat = parseLatLong($latns, $latdeg, $latmin, $latsec);
	my $long = parseLatLong($longew, $longdeg, $longmin, $longsec);

	if (!defined($elev) || $elev eq "" || $elev =~ /^\s*$/)
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
		$magvar =~ s/,/./;
		$decl = 0 - $magvar;
	}
	if ($decl == 0)
	{
		$decl = getMagVar($lat, $long, $elev);
	}

	my $type = 'VFR-WP';
	my $freq = "";
	if ($id =~ /-/)
	{
		my ($posid, $postype) = split("-",$id);
		if (exists($typemap{$postype}))
		{
			$type = $typemap{$postype};
			$id = $posid;
			print "name = [$name] ...";
			$name =~ s/ CH [0-9]+[XY]//;
			if ($name =~ s?^[A-Z/]+\s+??)
			{
				if ($name =~ m/\s/)
				{
					($name, $freq) = ($name =~ m/^(.*)\s(\S*)/);
				}
			}
			print "name = [$name], freq = [$freq]\n";
		}
	}
	else
	{
		if ($id =~ /^E/)
		{
			$type = 'AIRPORT';
		}
	}
	$id = substr($id, 0, 10);

    my $chart_map = ($type eq "VFR-WP") ? WaypointTypes::WPTYPE_VFR : 0;
	my $datasource_key = "GV_".$type."_".$id;
	insertWaypoint($id, $datasource_key, $type, $name, "",
					"", "GM", $lat, $long, $decl, $elev,
					$freq, Datasources::DATASOURCE_GR, 1, $chart_map);
}

updateDatasourceExtents(Datasources::DATASOURCE_GR);

post_load();

finish();
print "Done\n";

undef $fh;
