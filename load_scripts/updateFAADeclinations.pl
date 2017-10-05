#!/usr/bin/perl -w
# Take the FAA data and update the declination
#

BEGIN
{
  push @INC, "/home/ptomblin/navaid_local/perl";
}

use strict;
use DBI;
use Data::Dumper;
use PostGIS;

PostGIS::initialize();

$| = 1; # for debugging

my $post_conn = PostGIS::dbConnection();

my $selectWaypointStmt = $post_conn->prepare(
	"SELECT		internalid " .
	"FROM		waypoint a, type_categories b " .
	"WHERE		orig_datasource = 1 AND " .
	"			b.type = a.type AND " .
	"			a.type not like 'VOR%' AND " .
	"			b.category != 3");
#
#my $selectWaypointStmt = $post_conn->prepare(
#	"SELECT		internalid " .
#	"FROM		waypoint " .
#	"WHERE		orig_datasource = 1 AND " .
#	"			type not like 'VOR%'");

$selectWaypointStmt->execute();
while (my @row = $selectWaypointStmt->fetchrow_array())
{
  my $internalId = $row[0];

  my $rec = getWaypoint($internalId);

  my $decl = getMagVar($rec->{latitude}, $rec->{longitude}, $rec->{elevation});
  
  my $diff = $rec->{declination} - $decl;

  print $rec->{id}, "(", $rec->{type}, ") was decl ", $rec->{declination}, " is ", $decl,
	", diff is ", $diff;

  if (abs($diff) > 0.1)
  {
	print " - updating!";
	$rec->{declination} = $decl;
	$rec->{lastupdate} = localtime;

	PostGIS::deleteWaypoint($internalId, $rec->{areaid});
	PostGIS::putWaypoint($rec);
  }
  print "\n";
}

dbClose();

