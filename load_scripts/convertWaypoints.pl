#!/usr/bin/perl -w
# Take the data that's currently in mysql and put it in postGIS.
#

BEGIN
{
  push @INC, "/home/ptomblin/navaid_local/perl";
}

use strict;
use DBI;
use Geo::WKT;
use Geo::Shape;
use Geo::Line;
use Data::Dumper;
use PostGIS;

PostGIS::initialize();

$| = 1; # for debugging

my $mysql_conn;
$mysql_conn = DBI->connect(
	"DBI:mysql:database=navaid",
	"ptomblin", "navaid") or die $mysql_conn->errstr;
$mysql_conn->{"AutoCommit"} = 0;

my $post_conn = PostGIS::dbConnection();

# Get ready
PostGIS::clearOld();

my $selectTypesStmt = $mysql_conn->prepare(
	"SELECT		type, category, selected_by_default ".
	"FROM		type_categories ");
my $selectWaypointStmt = $mysql_conn->prepare(
	"SELECT		id, datasource_key, type, name, address, state, country, ".
	"			latitude, longitude, declination, datasource, elevation, ".
	"			main_frequency, ispublic, chart_map, tpa, orig_datasource ".
	"FROM		waypoint ".
	"WHERE		datasource = 99");
my $selectRunwaysStmt = $mysql_conn->prepare(
	"SELECT		runway_designation, length, width, surface, closed, ".
	"			datasource, b_lat, b_long, b_heading, b_elev, ".
	"			e_lat, e_long, e_heading, e_elev, orig_datasource ".
	"FROM		runways ".
	"WHERE		datasource_key = ?");
my $selectFreqsStmt = $mysql_conn->prepare(
	"SELECT		comm_type, comm_name, frequency, datasource, ".
	"			orig_datasource ".
	"FROM		comm_freqs ".
	"WHERE		datasource_key = ?");
my $selectFixsStmt = $mysql_conn->prepare(
	"SELECT		navaid, navaid_type, radial_bearing, distance, ".
	"			datasource, orig_datasource ".
	"FROM		fix ".
	"WHERE		datasource_key = ?");

my $insertTypeStmt = $post_conn->prepare(
	"INSERT	".
	"INTO		type_categories ".
	"			(type, category, selected_by_default) ".
	"VALUES		(?, ?, ?)");

my $internalIDNextValStmt = $post_conn->prepare(
	"SELECT		NEXTVAL('waypoint_internalid_seq')");
my $insertWaypointStmt = $post_conn->prepare(
	"INSERT ".
	"INTO		waypoint ".
	"			(internalid, areaid, id, type, name, address, state, ".
	"			 country, latitude, longitude, declination, elevation, ".
	"			 main_frequency, ispublic, tpa, chart_map, deletedon, ".
	"			 lastupdate, datasource, orig_datasource, ".
	"			 lastmajorupdate, point) ".
	"VALUES		(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ".
	"			 NOW(), ?, ?, NOW(), GeomFromText(?, 4326))");
my $insertRunwayStmt = $post_conn->prepare(
	"INSERT ".
	"INTO		runways ".
	"			(internalid, runway_designation, length, width, surface, ".
	"			 closed, b_lat, b_long, b_heading, b_elev, ".
	"			 e_lat, e_long, e_heading, e_elev, datasource, ".
	"			 orig_datasource) ".
	"VALUES		(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
my $insertFreqStmt = $post_conn->prepare(
	"INSERT ".
	"INTO		comm_freqs ".
	"			(internalid, comm_type, comm_name, frequency, datasource, ".
	"			 orig_datasource) ".
	"VALUES		(?, ?, ?, ?, ?, ?)");
my $insertFixStmt = $post_conn->prepare(
	"INSERT ".
	"INTO		fix ".
	"			(internalid, navaid, navaid_type, radial_bearing, ".
	"			 distance, datasource, orig_datasource) ".
	"VALUES		(?, ?, ?, ?, ?, ?, ?)");

my $selectPdbIDStmt = $mysql_conn->prepare(
	"SELECT		id, pdb_id ".
	"FROM		id_mapping ");
my $insertPdbIDStmt = $post_conn->prepare(
	"INSERT ".
	"INTO		id_mapping ".
	"			(id, pdb_id) ".
	"VALUES		(?, ?)");

sub getWptID()
{
  my $id = undef;
  $internalIDNextValStmt->execute();
  while (my @row = $internalIDNextValStmt->fetchrow_array())
  {
	$id = $row[0];
  }
  return $id;
}

$selectTypesStmt->execute();
while (my @row = $selectTypesStmt->fetchrow_array)
{
  my ($type, $category, $selected_by_default) = @row;
  $insertTypeStmt->execute($type, $category, $selected_by_default);
}

$selectWaypointStmt->execute();
while (my @row = $selectWaypointStmt->fetchrow_array)
{
  my (	$id, $datasource_key, $type, $name, $address, $state, $country,
		$latitude, $longitude, $declination, $datasource, $elevation,
		$main_frequency, $ispublic, $chart_map, $tpa, $orig_datasource) = @row;

  $longitude = -$longitude;
  utf8::upgrade($name);
  utf8::upgrade($address);

  my $internal = getWptID();
print "internal $internal,lat-long = ($latitude,$longitude)\n";
  my $pnt = wkt_point(Geo::Point->latlong($latitude, $longitude));
print "pnt = $pnt\n";
  my $cell = getCell($pnt);
  $insertWaypointStmt->execute(
  	$internal, $cell, $id, $type, $name, $address, $state,
	$country, $latitude, $longitude, $declination, $elevation,
	$main_frequency, $ispublic, $tpa, $chart_map, $datasource,
	$orig_datasource, $pnt);
  incrementAndSplitCell($cell);

  
  # get runways
  $selectRunwaysStmt->execute($datasource_key);
  while (my @rwyRow = $selectRunwaysStmt->fetchrow_array)
  {
	my ($runway_designation, $length, $width, $surface, $closed,
		$datasource, $b_lat, $b_lon, $b_heading, $b_elev, 
		$e_lat, $e_lon, $e_heading, $e_elev,  $orig_datasource) = @rwyRow;
	if (defined($b_lon))
	{
	  $b_lon = -$b_lon;
	}
	if (defined($e_lon))
	{
	  $e_lon = -$e_lon;
	}
	$insertRunwayStmt->execute($internal, $runway_designation, $length,
		$width, $surface, $closed, $b_lat, $b_lon, $b_heading, $b_elev,
		$e_lat, $e_lon, $e_heading, $e_elev, $datasource,
		$orig_datasource);
  }

  # get comm freqs
  $selectFreqsStmt->execute($datasource_key);
  while (my @freqRow = $selectFreqsStmt->fetchrow_array)
  {
	my ($comm_type, $comm_name, $frequency, $datasource,
	  $orig_datasource) = @freqRow;
	$insertFreqStmt->execute($internal, $comm_type, $comm_name,
		$frequency, $datasource, $orig_datasource);
  }

  # get fixes
  $selectFixsStmt->execute($datasource_key);
  while (my @fixRow = $selectFixsStmt->fetchrow_array)
  {
	my ($navaid, $navaid_type, $radial_bearing, $distance, $datasource,
	  $orig_datasource) = @fixRow;
	$insertFixStmt->execute($internal, $navaid, $navaid_type,
	  $radial_bearing, $distance, $datasource, $orig_datasource);
  }
}

print "copying ids\n";
$selectPdbIDStmt->execute();
while (my @row = $selectPdbIDStmt->fetchrow_array)
{
  my ($id, $pdb_id) = @row;
print "id = $id, pdb_id = $pdb_id\n";
  $insertPdbIDStmt->execute($id, $pdb_id);
}
print "finished copying\n";

postLoad();

$mysql_conn->disconnect;
dbClose();

