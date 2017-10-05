#!/usr/bin/perl -w

use IO::File;

use strict;

$| = 1; # for debugging

use Datasources;
use WPInfo;

use PostGIS;

my $default_wpt_type = "AIRPORT";

my $fn = shift;
my $dbName = "navaid";
if ($fn eq "-d")
 {
  $dbName = shift;
  $fn = shift;
}
print "loading $fn into $dbName\n";

PostGIS::initialize($dbName);

my $fh = new IO::File($fn) or die "Airport file $fn not found";

startDatasource(Datasources::DATASOURCE_CA_GP);

# First two lines are header
<$fh>;
<$fh>;

while (<$fh>)
{
	chomp;

	next if /^$/;
	next if /^#/;
	next if /^\t/;

	my @record = split("\t", $_);

	my ($id, $name, $type, $province,
		$utc, $junk, $elev, $magvar, $notam, $stat1, $stat2,
		$customs,
		$runway, $surface, $fuel,
		$n, $latdeg, $latmin, $latsec,
		$w, $londeg, $lonmin, $lonsec,
		$latdec, $londec, 
		$filler, $operator, $contact_number,
		$morefiller) = @record;

	next if ($province eq "USA");

	my $country = "CA";

	if ($province eq "FRANCE")
	{
	  $province = "";
	  $country = "SB";
	}

	if ($province eq "NL")
	{
	  $province = "NF";
	}

	my $lat = $latdec;
	my $long = $londec;

	# Fucking Microsoft - you tell it to export as Tab Delimited,
	# and it does a quote thing like it was CSV.
	if ($name =~ m/^"/)
	{
	  $name =~ s/^"(.*)"$/$1/;
	  $name =~ s/""/"/g;
	}
	# Heliports are marked in the name.
	if ($name =~ m/\(Heli\)/ || $type eq "Heli")
	{
	  $name =~ s/(.*)\(Heli\)/$1/;
	  $type = "HELIPORT";
	}
	else
	{
	  $type = $default_wpt_type;
	}

	$elev =~ s/\s*aprx\s*//;

	#print "getting mag var for $id ($lat, $long, $elev)\n";
	#my $decl = getMagVar($lat, $long, $elev);
	#print "got $decl\n";
	my $decl;
	if ($magvar eq "0_")
	{
	  $decl = getMagVar($lat, $long, $elev);
	}
	else
	{
	  print "magvar = $magvar\n";
	  my $ew;
	  ($decl, $ew) = ($magvar =~ m/([0-9]*)_([EW])/);
	  print "decl, ew = $decl - $ew\n";
	  if ($ew eq "E")
	  {
		$decl = -$decl;
	  }
	}

	utf8::upgrade($name);

	my %waypoint;
	$waypoint{id} = $id;
	$waypoint{type} = $type;
	$waypoint{name} = $name;
	$waypoint{state} = $province;
	$waypoint{country} = $country;
	$waypoint{latitude} = $lat * 1.0;
	$waypoint{longitude} = $long * 1.0;
	if (defined($decl))
	{
	  $decl += 0;
	}
	$waypoint{declination} = $decl;
	if (defined($elev))
	{
	  $elev += 0;
	}
	$waypoint{elevation} = $elev;
	$waypoint{ispublic} = 1;
	if ($fuel ne "")
	{
	  $waypoint{hasfuel} = 1;
	}
	$waypoint{orig_datasource} = Datasources::DATASOURCE_CA_GP;

	insertWaypoint(\%waypoint);
}

close($fh);

$default_wpt_type = "SEAPLANE BASE";

$fn = shift;
print "doing $fn\n";
$fh = new IO::File($fn) or die "Seaplane base file $fn not found";


# First two lines are header
<$fh>;
<$fh>;

while (<$fh>)
{
	chomp;

	next if /^$/;
	next if /^#/;
	next if /^\t/;

	my @record = split("\t", $_);

	my ($id, $name, $province,
		$utc, $aprx, $elev, $magvar, $notam, $stat1, $stat2,
		$customs, $fuel,
		$n, $latdeg, $latmin, $latsec,
		$w, $londeg, $lonmin, $lonsec,
		$latdec, $londec, 
		$filler2, $operator, $contact_number,
		$morefiller) = @record;
	my $lat = $latdec;
	my $long = $londec;

	my $type = $default_wpt_type;

	my $country = "CA";

	if ($province eq "FRANCE")
	{
	  $province = "";
	  $country = "SB";
	}

	if ($province eq "NL")
	{
	  $province = "NF";
	}

	# Fucking Microsoft - you tell it to export as Tab Delimited,
	# and it does a quote thing like it was CSV.
	if ($name =~ m/^"/)
	{
	  $name =~ s/^"(.*)"$/$1/;
	  $name =~ s/""/"/g;
	}
	# Heliports are marked in the name.
	if ($name =~ m/\(Heli\)/)
	{
		$name =~ s/(.*)\(Heli\)/$1/;
		  $type = "HELIPORT";
	}

	$elev =~ s/\s*aprx\s*//;

	print "getting mag var for $id ($lat, $long, $elev)\n";
	my $decl = getMagVar($lat, $long, $elev);
	#my $decl = 0;
	print "got $decl\n";

	utf8::upgrade($name);

	my %waypoint;
	$waypoint{id} = $id;
	$waypoint{type} = $type;
	$waypoint{name} = $name;
	$waypoint{state} = $province;
	$waypoint{country} = $country;
	$waypoint{latitude} = $lat * 1.0;
	$waypoint{longitude} = $long * 1.0;
	if (defined($decl))
	{
	  $decl += 0;
	}
	$waypoint{declination} = $decl;
	if (defined($elev))
	{
	  $elev += 0;
	}
	$waypoint{elevation} = $elev;
	$waypoint{ispublic} = 1;
	if ($fuel ne "")
	{
	  $waypoint{hasfuel} = 1;
	}
	$waypoint{orig_datasource} = Datasources::DATASOURCE_CA_GP;

	insertWaypoint(\%waypoint);
}

endDatasource(Datasources::DATASOURCE_CA_GP);

postLoad();

dbClose();
print "Done\n";
