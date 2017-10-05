#!/usr/bin/perl -w

use IO::File;

use strict;

use Datasources;

use WPInfo;
use DBLoad;

my $wp_db_name = WPInfo::getLoadDB();
DBLoad::initialize($wp_db_name);

my $fn = shift;

my $fh = new IO::File($fn) or die "Airport file $fn not found";

deleteWaypointData(Datasources::DATASOURCE_SG_GP);

<$fh>;

while (<$fh>)
{
	chomp;

	next if /^#/;

	my $line = uc;
	$line =~ s/"([^"]*)"/$1/g;

    my ($junk1, $junk2, $id, $latitude, $longitude, $decl, $type,
		$junk3, $elev, $name, $state, $country) = 
            split(",", $line);

	next if ($type ne "PLATFORM");

	if (!defined($elev) || $elev eq "" || $elev == 99999)
	{
		$elev = 0.0;
	}

	if ($decl == 0)
	{
		$decl = getMagVar($latitude, $longitude, $elev);
	}

	my $freq = "";

	if ($state eq "" || $state eq "#1")
	{
		$state = "OG";
	}

	my $datasource_key = "SG_GP_".$id;
	insertWaypoint($id, $datasource_key, $type, $name, "",
					$state, "US", $latitude, $longitude, $decl, $elev,
					$freq, Datasources::DATASOURCE_SG_GP, 1, 0);
}

updateDatasourceExtents(Datasources::DATASOURCE_SG_GP);

finish();

undef $fh;
