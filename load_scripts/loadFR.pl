#!/usr/bin/perl -w

use IO::File;

use strict;

#$| = 1; # for debugging

use Datasources;
use WPInfo;

use DBLoad;
my $wp_db_name = WPInfo::getLoadDB();
DBLoad::initialize($wp_db_name);

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


	my $mult = 1.0;

	if ($nsew eq "E" || $nsew eq "S")
	{
		$mult = -1.0;
	}

	my $degrees = $deg + ($min/60.0) + ($sec/3600.0);

	return $degrees * $mult;
}

sub delete_FR_data()
{
	deleteWaypointData(Datasources::DATASOURCE_FR);
}

sub parseFRWaypointAirportRecord($)
{
	my ($line) = @_;

	my ($junk1, $junk2, $id, $name, $altitude, $junk3, $junk4,
	 $ns, $latdeg, $latmin, $latsec, $ew, $londeg, $lonmin, $lonsec,
	 $hpa, $vhftype, $freq, $junk5) =
			split("\t", $line);

	#$name =~ s/'/''/g;
	my $lat = parseLatLong($ns, $latdeg, $latmin, $latsec);

	my $long = parseLatLong($ew, $londeg, $lonmin, $lonsec);

	my $decl = getMagVar($lat, $long, $altitude);

	my $datasource_key = "FR_APT_$id";

	if ($freq eq "0")
	{
		$freq = "";
	}

	insertWaypoint($id, $datasource_key, "AIRPORT", $name, "",
					"", "FR", $lat, $long, $decl, $altitude,
					$freq, Datasources::DATASOURCE_FR, 1, 0);

	return $datasource_key;
}


sub parseFRWaypointVORRecord($)
{
	my ($line) = @_;

	my ($junk1, $junk2, $id, $name, $freq, $junk3, $junk4,
	 $ns, $latdeg, $latmin, $latsec, $ew, $londeg, $lonmin, $lonsec,
	 $type, $freq1, $junk5) = split("\t", $line);

	return if ($id eq "");

	if ($type =~ /^LLZ/)
	{
		return;
#		$type =~ s/^LLZ/LOC/;
#		$type =~ s/ .*$//;
	}
	elsif ($type =~ / /)
	{
		$type =~ s? ?/?g;
	}

	my $lat = parseLatLong($ns, $latdeg, $latmin, $latsec);

	my $long = parseLatLong($ew, $londeg, $lonmin, $lonsec);

	my $datasource_key = "FR_VOR_$id";

	my $decl = getMagVar($lat, $long, 0);

	if ($freq eq "0")
	{
		$freq = "";
	}

	insertWaypoint($id, $datasource_key, $type, $name, "",
					"", "FR", $lat, $long, $decl, 0,
					$freq, Datasources::DATASOURCE_FR, 1, 0);

	return $datasource_key;
}

sub parseFRWaypointNDBRecord($)
{
	my ($line) = @_;

	my ($junk1, $junk2, $id, $name, $freq, $junk3, $junk4,
	 $ns, $latdeg, $latmin, $latsec, $ew, $londeg, $lonmin, $lonsec,
	 $type, $freq1, $junk5) = split("\t", $line);

	return if ($id eq "");

	my $lat = parseLatLong($ns, $latdeg, $latmin, $latsec);

	my $long = parseLatLong($ew, $londeg, $lonmin, $lonsec);

	my $datasource_key = "FR_NDB_$id";

	my $decl = getMagVar($lat, $long, 0);

	if ($freq eq "0")
	{
		$freq = "";
	}

	insertWaypoint($id, $datasource_key, "NDB", $name, "",
					"", "FR", $lat, $long, $decl, 0,
					$freq, Datasources::DATASOURCE_FR, 1, 0);

	return $datasource_key;
}

sub parseFRWaypointRepPtRecord($)
{
	my ($line) = @_;

	my ($junk1, $junk2, $id, $name, $addr, $junk3, $junk4,
	 $ns, $latdeg, $latmin, $latsec, $ew, $londeg, $lonmin, $lonsec,
	 $junk5) = split("\t", $line);

	return if ($id eq "");

	my $lat = parseLatLong($ns, $latdeg, $latmin, $latsec);

	my $long = parseLatLong($ew, $londeg, $lonmin, $lonsec);

	my $datasource_key = "FR_WPT_$id";

	my $decl = getMagVar($lat, $long, 0);

	insertWaypoint($id, $datasource_key, "VFR-WP", $name, $addr,
					"", "FR", $lat, $long, $decl, 0,
					"", Datasources::DATASOURCE_FR, 1, 0);

	return $datasource_key;
}

sub read_FR($$)
{
    my $fn = shift;
	my $coderef = shift;

    my $fh = new IO::File($fn) or die "Airport file $fn not found";

	<$fh>;
    while (<$fh>)
    {
        chomp;
		s/  *\t/\t/;
		&$coderef(uc $_);
	}
    undef $fh;
}

my $FRapt = shift;
my $FRvor = shift;
my $FRndb = shift;
my $FRrep = shift;

delete_FR_data();
print "FR data is deleted\n";

print "loading FR airports\n";
read_FR($FRapt, \&parseFRWaypointAirportRecord);

print "loading FR VORs\n";
read_FR($FRvor, \&parseFRWaypointVORRecord);

print "loading FR NDBs\n";
read_FR($FRndb, \&parseFRWaypointNDBRecord);

print "loading FR Reporting Points\n";
read_FR($FRrep, \&parseFRWaypointRepPtRecord);

updateDatasourceExtents(Datasources::DATASOURCE_FR);

finish();
print "Done\n";

