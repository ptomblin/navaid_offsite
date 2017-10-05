#!/usr/bin/perl -w

use strict;

use DBI;
use Data::Dumper;

use PostGIS;
PostGIS::initialize();

use Datasources;
use WPInfo;

startDatasource(Datasources::DATASOURCE_WO_OA);

my %typeLookup = (
  "heliport"		=> 'HELIPORT',
  "small_airport"	=> 'AIRPORT',
  "medium_airport"	=> 'AIRPORT',
  "large_airport"	=> 'AIRPORT',
  "seaplane_base"	=> 'SEAPLANE BASE',
);

sub nullsAreZeros($)
{
  my $rec = shift;
  if (!defined($rec))
  {
	return 0;
  }
  return $rec;
}

sub roundIt($)
{
  my $rec = shift;
  if (defined($rec))
  {
	$rec = int($rec + 0.5);
  }
  return $rec;
}

sub truncateSurface($)
{
  my $rec = shift;
  if (defined($rec))
  {
	$rec =~ s/&amp;/&/g;
	$rec =~ s/,.*//;
  }
  return $rec;
}

$| = 1; # for debugging
my $dbh = DBI->connect ("DBI:CSV:f_dir=../nav_data/our_airports/data/") or
die "Cannot connect: $DBI::errstr";
$dbh->{csv_null} = 1;

$dbh->{csv_tables}{airports} = {
        eol         => "\n",
        file        => "airports.csv",
        col_names   => [qw( id wpt_ident type name
				  latitude_deg longitude_deg elevation_ft
				  continent iso_country iso_region
				  municipality scheduled_service
				  gps_code iata_code local_code
				  home_link wikipedia_link keywords)],
		skip_first_row	=> 1,
        };
$dbh->{csv_tables}{frequencies} = {
        eol         => "\n",
        file        => "airport-frequencies.csv",
        col_names   => [qw( id airport_ref airport_ident
				  type description frequency_mhz)],
		skip_first_row	=> 1,
        };
$dbh->{csv_tables}{navaids} = {
        eol         => "\n",
        file        => "navaids.csv",
        col_names   => [qw( id filename wpt_ident
				  name type frequency_khz 
				  latitude_deg longitude_deg elevation_ft
				  iso_country dme_frequency_khz dme_channel
				  dme_latitude_deg dme_longitude_deg dme_elevation_ft
				  slaved_variation_deg magnetic_variation_deg 
				  usageType power associated_airport)],
		skip_first_row	=> 1,
        };
$dbh->{csv_tables}{runways} = {
        eol         => "\n",
        file        => "runways.csv",
        col_names   => [qw( id airport_ref airport_ident
				  length_ft width_ft surface lighted closed
				  le_ident le_latitude_deg le_longitude_deg
				  le_elevation_ft le_heading_degT
				  le_displaced_threshold_ft
				  he_ident he_latitude_deg he_longitude_deg
				  he_elevation_ft he_heading_degT
				  he_displaced_threshold_ft)],
		skip_first_row	=> 1,
        };

my $airportsSelectStmt = $dbh->prepare (qq/
		SELECT		*
		FROM		airports/)
or die "Cannot prepare: " . $dbh->errstr();
my $runwaysStmt = $dbh->prepare (qq/
		SELECT		*
		FROM		runways
		WHERE		airport_ref = ?/)
or die "Cannot prepare: " . $dbh->errstr();
my $frequencyStmt = $dbh->prepare (qq/
		SELECT		*
		FROM		frequencies
		WHERE		airport_ref = ?/)
or die "Cannot prepare: " . $dbh->errstr();
my $navaidsStmt = $dbh->prepare(qq/
		SELECT		*
		FROM		navaids/);

$airportsSelectStmt->execute()
or die "Cannot execute: " . $airportsSelectStmt->errstr();

while (my $airportRow = $airportsSelectStmt->fetchrow_hashref())
{
  print "airportRow = ", Dumper($airportRow), "\n";
  my $airportref = $airportRow->{id};
  next if ($airportref eq "id");
  # Don't trust his US airports
  next if ($airportRow->{iso_country} eq "US");

  my %waypoint;
  $waypoint{id} = $airportRow->{wpt_ident};
  my $type = $airportRow->{type};
  if ($type eq "closed")
  {
	closeOurAirportsWaypoint($airportref);
	next;
  }

  $waypoint{type} = $typeLookup{$type};
  die "invalid type $type\n" if (!defined($waypoint{type}));

  $waypoint{country} = translateCountryCode($airportRow->{iso_country});
  die "Invalid country ", $airportRow->{iso_country}, "\n" if (!defined($waypoint{country}));

  $waypoint{name} = $airportRow->{name};
  $waypoint{address} = $airportRow->{municipality};
  if ($airportRow->{iso_country} eq "CA")
  {
	my $prov = $airportRow->{iso_region};
	$prov =~ s/CA-//;
	$waypoint{state} = $prov;
  }
  $waypoint{latitude} = $airportRow->{latitude_deg};
  $waypoint{longitude} = $airportRow->{longitude_deg};
  $waypoint{elevation} = $airportRow->{elevation_ft};
  $waypoint{declination} = getMagVar(
  		$waypoint{latitude},
		$waypoint{longitude},
		$waypoint{elevation});
  $waypoint{category} = 1;
  $waypoint{our_airports_id} = $airportref;

  $runwaysStmt->execute($airportref)
  or die "Cannot execute: " . $runwaysStmt->errstr();
  while (my $runwayRow = $runwaysStmt->fetchrow_hashref())
  {
	print "runway = ", Dumper($runwayRow), "\n";
	if (!defined($waypoint{runways}))
	{
	  $waypoint{runways} = [];
	}
	my $runwayRef = $waypoint{runways};
	my %record;
	my $designation;
	if ($runwayRow->{le_ident} eq $runwayRow->{he_ident})
	{
	  $designation = $runwayRow->{le_ident};
	}
	else
	{
	  $designation = $runwayRow->{le_ident} . "/" . $runwayRow->{he_ident};
	}
	if (!defined($designation))
	{
	  if ($waypoint{type} eq 'HELIPORT')
	  {
		$designation = 'H1';
	  }
	  else
	  {
		next; # skip the damn thing.
	  }
	}
	$record{designation} = $designation;
	$record{length} = nullsAreZeros($runwayRow->{length_ft});
	$record{width} = nullsAreZeros($runwayRow->{width_ft});
	$record{surface} = truncateSurface($runwayRow->{surface});
	$record{b_lat} = $runwayRow->{le_latitude_deg};
	$record{b_long} = $runwayRow->{le_longitude_deg};
	$record{b_heading} = roundIt($runwayRow->{le_heading_degt});
	$record{b_elev} = $runwayRow->{le_elevation_ft};
	$record{e_lat} = $runwayRow->{he_latitude_deg};
	$record{e_long} = $runwayRow->{he_longitude_deg};
	$record{e_heading} = roundIt($runwayRow->{he_heading_degt});
	$record{e_elev} = $runwayRow->{he_elevation_ft};
	push @$runwayRef, \%record;
  }

  $frequencyStmt->execute($airportref)
  or die "Cannot execute: " . $frequencyStmt->errstr();
  while (my $frequencyRow = $frequencyStmt->fetchrow_hashref())
  {
	print "frequency = ", Dumper($frequencyRow), "\n";
  }

  print "Waypoint = ", Dumper(\%waypoint), "\n";

  insertWaypoint(\%waypoint);
}

$airportsSelectStmt->finish;
$runwaysStmt->finish;
$frequencyStmt->finish;
$navaidsStmt->finish;
$dbh->disconnect;

endDatasource(Datasources::DATASOURCE_WO_OA);

print "postload\n";
postLoad();

print "dbclose\n";
dbClose();
print "Done\n";
