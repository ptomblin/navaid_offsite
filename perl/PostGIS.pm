#!/usr/bin/perl -w
# TODO: remove runways, comm_freqs, and fixinfo if the waypoint is deleted
# TODO: runways-closed is going to null on entries that otherwise haven't
# changed.
# TODO: compare numeric fields numerically, so "48.0" to "48.0000" doesn't
# mark as a major change.

package PostGIS;

@ISA = "Exporter";
@EXPORT = qw(dbConnection getCell incrementAndSplitCell dbClose
rebalanceQuadTree fixBogusQuadCells
getProvince getMagVar getStateCountry getStateCountryFromLatLong
fixFrequency
getNextInternalID getNearestCountry
getWaypoint insertWaypoint
findBestMatch getEADIDMatch getNearInexactMatch
translateCountryCode
closeWaypoint closeOurAirportsWaypoint closeFAAWaypoint closeEADWaypoint
startDatasource endDatasource
postLoad
flushWaypoints
);

use strict;

use DBI;
use IO::Handle;
use IPC::Open2;

use Geo::WKT;
use Geo::Shape;
use Geo::Line;

use Data::Dumper;

use LWP;
use XML::Simple;

use Time::HiRes qw(tv_interval gettimeofday usleep);

use constant MAX_PER_QUAD		=> 250;
use constant SMALL_EPSILON		=> .05;
use constant LARGE_EPSILON		=> .10;
use constant SRID				=> 4326;
use constant FAKE_DATASOURCE	=> -1;
use constant HOMEDIR 			=> "/home/ptomblin/navaid_local/";
use constant GEONAMES_INTERVAL	=>	1000;

use constant TEST_MODE		=> 0;


my $post_conn;
my $provinceProgram = HOMEDIR . "bin/whatProvince " . HOMEDIR . "data/province_dd";

my ($provReader, $provWriter) = (IO::Handle->new, IO::Handle->new);
open2($provReader, $provWriter, $provinceProgram);

my $magvarProgram = HOMEDIR . "bin/magvar " . HOMEDIR . "data/WMM.COF";

my ($magvarReader, $magvarWriter) = (IO::Handle->new, IO::Handle->new);
open2($magvarReader, $magvarWriter, $magvarProgram);

my $ua = LWP::UserAgent->new;
my $simple = XML::Simple->new;

my @date = localtime();
my $year = $date[5] + 1900 + ($date[7]/365.25);

sub dbConnection()
{
  return $post_conn;
}

sub dbClose()
{
  if (TEST_MODE)
  {
	$post_conn->rollback();
  }
  else
  {
	$post_conn->commit();
  }
  $post_conn->disconnect();

  $provWriter->print("999 999\n");
  $magvarWriter->print("-999 999 -999 -999 -999\n");
}

sub clearOld()
{
  if (!TEST_MODE)
  {
  print "deleting runways\n";
  $post_conn->do("DELETE FROM runways");
  print "deleting comm_freqs\n";
  $post_conn->do("DELETE FROM comm_freqs");
  print "deleting fix\n";
  $post_conn->do("DELETE FROM fix");
  print "deleting waypoint\n";
  $post_conn->do("DELETE FROM waypoint");
  print "deleting categories\n";
  $post_conn->do("DELETE FROM type_categories");
  print "deleting areaids\n";
  $post_conn->do("DELETE FROM areaids");
  print "deleting country extents\n";
  $post_conn->do("DELETE FROM country_extents");
  print "deleting state/country extents\n";
  $post_conn->do("DELETE FROM state_country_extents");
  print "deleting id_mapping\n";
  $post_conn->do("DELETE FROM id_mapping");
  print "resetting values\n";
  $post_conn->do("SELECT SETVAL('areaids_areaid_seq', 1, true)");
  $post_conn->do("SELECT SETVAL('waypoint_internalid_seq', 1, true)");
  $post_conn->do("INSERT INTO areaids VALUES (1, NULL, NULL, 0, ST_GeomFromText('POLYGON((-180 -90, 180 -90, 180 90, -180 -90))', 4326))");
  print "done\n";
  }
}

sub deep_copy
{
  my $this = shift;
  if (not ref $this)
  {
	$this;
  }
  elsif (ref $this eq "ARRAY")
  {
	[map deep_copy($_), @$this];
  }
  elsif (ref $this eq "HASH")
  {
	+{map { $_ => deep_copy($this->{$_}) } keys %$this};
  }
  else
  {
	die "what type is $_?"
  }
}

my $maxPerQuad = MAX_PER_QUAD;

my $getQuadStmt;
my $quadIncStmt;
my $quadDecStmt;
my $quadSetStmt;
my $quadGetCountStmt;
my $quadGetOverBalanceStmt;
my $quadGetDuplicatesStmt;
my $quadGetDupIDsStmt;
my $quadDeDupIDStmt;
my $quadNextValStmt;
my $quadInsertStmt;
my $quadSupercedeStmt;
my $moveWaypointsQuadStmt;

my $getNextInternalIDStmt;

my $delWaypointStmt;
my $delRunwayStmt;
my $delFrequencyStmt;
my $delFixStmt;

my $getWaypointStmt;
my $getRunwayStmt;
my $getFrequencyStmt;
my $getFixStmt;

my $insWaypointStmt;
my $insRunwayStmt;
my $insFrequencyStmt;
my $insFixStmt;


my $findOurAirportsIDMatchStmt;
my $findFAAIDMatchStmt;
my $findEADIDMatchStmt;
my $findNearIDMatchStmt;
my $findNearNonIDMatchStmt;

my $startDatasourceStmt;
my $endDatasource1Stmt;
my $endDatasource2Stmt;

my $setDatasourceStmt;

my $stateStmt;

my $closeStmt;

my $translateCountryStmt;
my %isoCountries;

my %typeCategories;
my %states;

my @unprocessed = ();

sub initialize($)
{
  my $dbName = shift;
  if (!defined($dbName))
  {
	$dbName = "navaid";
  }
  $post_conn = DBI->connect(
	  "DBI:Pg:database=$dbName",
	  "navaid", "navaid") or die $post_conn->errstr;
  $post_conn->{"AutoCommit"} = 0;

#print "getQuadStmt\n";
  $getQuadStmt = $post_conn->prepare(
	"SELECT		areaid ".
	"FROM		areaids ".
	"WHERE		supercededon is null AND ".
	"			rectangle && ST_GeomFromText(?, " . SRID . ")");
#print "quadIncStmt\n";
  $quadIncStmt = $post_conn->prepare(
	"UPDATE		areaids ".
	"SET		numpoints = numpoints + 1 " .
	"WHERE		areaid = ?");
  $quadDecStmt = $post_conn->prepare(
	"UPDATE		areaids ".
	"SET		numpoints = numpoints - 1 " .
	"WHERE		areaid = ?");
#print "quadSetStmt\n";
  $quadSetStmt = $post_conn->prepare(
	"UPDATE		areaids ".
	"SET		numpoints = ? " .
	"WHERE		areaid = ?");
#print "quadGetCountStmt\n";
  #
  # Rebalancing Quads
  $quadGetCountStmt = $post_conn->prepare(
	"SELECT		numpoints, st_astext(rectangle) ".
	"FROM		areaids ".
	"WHERE		areaid = ?");
  $quadGetOverBalanceStmt= $post_conn->prepare(
	"SELECT		areaid, st_astext(rectangle) ".
	"FROM		areaids ".
	"WHERE		supercededon is null and numpoints > ?");
  #
  # Fixing up duplicate Quads
  $quadGetDuplicatesStmt= $post_conn->prepare(
	"SELECT		rectangle, supercedes, count(1) ".
	"FROM		areaids ".
	"GROUP BY	rectangle, supercedes ".
	"HAVING		count(1) > 1");
  $quadGetDupIDsStmt= $post_conn->prepare(
	"SELECT		areaid, numpoints ".
	"FROM		areaids ".
	"WHERE		rectangle = ? " .
	"ORDER BY	numpoints DESC");
  $quadDeDupIDStmt = $post_conn->prepare(
  	"DELETE " .
	"FROM		areaids ".
	"WHERE		areaid = ?");
#	"UPDATE		areaids ".
#	"SET		numpoints = 0, supercededon = NOW(), supercedes = -1 ".
  #
  # 
  $quadNextValStmt = $post_conn->prepare(
	"SELECT		NEXTVAL('areaids_areaid_seq')");
  $quadInsertStmt = $post_conn->prepare(
	"INSERT	".
	"INTO		areaids ".
	"			(areaid, supercededon, supercedes, numpoints, rectangle) ".
	"VALUES		(?, NULL, ?, 0, ST_GeomFromText(?, " . SRID . "))");

  $quadSupercedeStmt = $post_conn->prepare(
	"UPDATE		areaids ".
	"SET		numpoints = 0, supercededon = NOW() ".
	"WHERE		areaid = ?");

  $moveWaypointsQuadStmt = $post_conn->prepare(
	"UPDATE		waypoint ".
	"SET		areaid = ?, ".
	"			lastupdate = NOW(), lastmajorupdate = NOW() ".
	"WHERE		areaid = ? AND ".
	"			point && (".
	"	SELECT 		rectangle ".
	"	FROM		areaids ".
	"	WHERE		areaid = ?)");

#print "getNextInternalIDStmt\n";
  $getNextInternalIDStmt = $post_conn->prepare(
  	"SELECT		NEXTVAL('waypoint_internalid_seq')");

#print "getWaypointStmt\n";
  $getWaypointStmt = $post_conn->prepare(
        "SELECT     a.id, c.pdb_id, internalid, areaid, a.type, name, " .
        "           address, state, country, latitude, longitude, " .
        "           declination, elevation, main_frequency, " .
        "           b.category, chart_map, tpa, ispublic, " .
        "           deletedon, lastupdate, orig_datasource,  ".
		"			lastmajorupdate, ST_AsText(point), hasfuel, ".
		"			our_airports_id, faa_id, ead_id " .
        "FROM       waypoint a " .
		"JOIN		type_categories b ON (a.type = b.type) " .
        "LEFT JOIN	id_mapping c ON (a.id = c.id) " .
        "WHERE      internalid = ?");

#print "getRunwayStmt\n";
  $getRunwayStmt = $post_conn->prepare(
        "SELECT     runway_designation, length, width, surface, " .
                   "b_lat, b_long, b_heading, b_elev, " .
                   "e_lat, e_long, e_heading, e_elev " .
        "FROM       runways " .
        "WHERE      internalid = ? and (closed is null or not closed) " .
        "ORDER BY   runway_designation");

#print "getFrequencyStmt\n";
  $getFrequencyStmt = $post_conn->prepare(
        "SELECT     comm_type, frequency, comm_name " .
        "FROM       comm_freqs " .
        "WHERE      internalid = ? " .
        "ORDER BY   frequency, comm_type");
#print "getFixStmt\n";
  $getFixStmt = $post_conn->prepare(
        "SELECT     navaid, navaid_type, " .
        "           radial_bearing, distance " .
        "FROM       fix " .
        "WHERE      internalid = ?");

#print "delWaypointStmt\n";
  $delWaypointStmt = $post_conn->prepare(
  		"DELETE		".
		"FROM		waypoint ".
		"WHERE		internalid = ?");
#print "delRunwayStmt\n";
  $delRunwayStmt = $post_conn->prepare(
  		"DELETE		".
		"FROM		runways ".
		"WHERE		internalid = ?");
#print "delFrequencyStmt\n";
  $delFrequencyStmt = $post_conn->prepare(
  		"DELETE		".
		"FROM		comm_freqs ".
		"WHERE		internalid = ?");
#print "delFixStmt\n";
  $delFixStmt = $post_conn->prepare(
  		"DELETE		".
		"FROM		fix ".
		"WHERE		internalid = ?");

#print "insWaypointStmt\n";
  $insWaypointStmt = $post_conn->prepare(
		"INSERT ".
		"INTO		waypoint ".
		"			(id, internalid, areaid, type, name, address, state, ".
		"			 country, latitude, longitude, declination, elevation, ".
		"			 main_frequency, chart_map, tpa, ispublic, deletedon, ".
		"			 lastupdate, orig_datasource, ".
		"			 lastmajorupdate, point, hasfuel, our_airports_id, ".
		"			 faa_id, ead_id) ".
		"VALUES		(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ".
		"			 NOW(), ?, ?, ST_GeomFromText(?, ". SRID . "), ?, ?, ?, ?)");
#print "insRunwayStmt\n";
  $insRunwayStmt = $post_conn->prepare(
		"INSERT ".
		"INTO		runways ".
		"			(internalid, runway_designation, length, width, surface, ".
		"			 closed, b_lat, b_long, b_heading, b_elev, ".
		"			 e_lat, e_long, e_heading, e_elev) ".
		"VALUES		(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
#print "insFrequencyStmt\n";
  $insFrequencyStmt = $post_conn->prepare(
		"INSERT ".
		"INTO		comm_freqs ".
		"			(internalid, comm_type, comm_name, frequency) ".
		"VALUES		(?, ?, ?, ?)");
#print "insFixStmt\n";
  $insFixStmt = $post_conn->prepare(
		"INSERT ".
		"INTO		fix ".
		"			(internalid, navaid, navaid_type, radial_bearing, ".
		"			 distance) ".
		"VALUES		(?, ?, ?, ?, ?)");

  $findOurAirportsIDMatchStmt = $post_conn->prepare(
  		"SELECT		internalid " .
		"FROM		waypoint " .
		"WHERE		our_airports_id = ?");
  $findFAAIDMatchStmt = $post_conn->prepare(
  		"SELECT		internalid " .
		"FROM		waypoint " .
		"WHERE		faa_id = ?");
  $findEADIDMatchStmt = $post_conn->prepare(
  		"SELECT		internalid " .
		"FROM		waypoint " .
		"WHERE		ead_id = ?");
#print "findNearIDMatchStmt\n";
  $findNearIDMatchStmt = $post_conn->prepare(
  		"SELECT		internalid " .
		"FROM		waypoint a, type_categories b " .
		"WHERE		id = ? AND " .
		"			a.type = b.type AND ".
		"			b.category = ? AND ".
		"			(b.category in (1, 3) OR a.type like ?) AND ".
		"			(? = 0 OR deletedon IS NULL) AND ".
		"			ST_DWithin(point, ST_GeomFromText(?," . SRID .
		"			),".  LARGE_EPSILON . ") " .
		"ORDER BY 	ST_Distance(point, ST_GeomFromText(?,". SRID .
		"			)) " .
		"LIMIT 		1");
#print "findNearNonIDMatchStmt\n";
  $findNearNonIDMatchStmt = $post_conn->prepare(
  		"SELECT		internalid " .
		"FROM		waypoint a, type_categories b " .
		"WHERE		id != ? AND " .
		"			a.type = b.type AND " .
		"			b.category = ? AND " .
		"			orig_datasource NOT IN (" . FAKE_DATASOURCE . ",?) AND ".
		"			(b.category IN (1, 3) OR a.type LIKE ?) AND ".
		"			(? = 0 OR deletedon IS NULL) AND ".
		"			ST_DWithin(point, ST_GeomFromText(?," . SRID .
		"			),".  SMALL_EPSILON . ") " .
		"ORDER BY 	ST_Distance(point, ST_GeomFromText(?,". SRID .
		"			)) " .
		"LIMIT 		1");

  my $typeCategoryStmt = $post_conn->prepare(
  		"SELECT		type, category ".
		"FROM		type_categories ");
  $typeCategoryStmt->execute();
  while (my @row = $typeCategoryStmt->fetchrow_array)
  {
	my ($type, $category) = @row;
	$typeCategories{$type} = $category;
  }

  my $allStateStmt = $post_conn->prepare(
  		"SELECT		code, UPPER(long_name), country ".
		"FROM		state_prov_lookup ");
  $allStateStmt->execute();
  while (my @row = $allStateStmt->fetchrow_array)
  {
	my ($code, $name, $country) = @row;
	$states{$code} = { "name" => $name, "country" => $country};
  }

  $stateStmt = $post_conn->prepare(
  		"SELECT		code, long_name, country ".
		"FROM		state_prov_lookup ".
		"WHERE		UPPER(long_name) = ?");

  $startDatasourceStmt = $post_conn->prepare(
  		"UPDATE		waypoint " .
		"SET		orig_datasource = " . FAKE_DATASOURCE . " ".
		"WHERE		orig_datasource = ?");
  $endDatasource1Stmt = $post_conn->prepare(
  		"UPDATE		waypoint " .
		"SET		orig_datasource = ?, deletedon = NOW() " .
		"WHERE		orig_datasource = " . FAKE_DATASOURCE . " AND ".
		"			deletedon is null");
  $endDatasource2Stmt = $post_conn->prepare(
  		"UPDATE		waypoint " .
		"SET		orig_datasource = ? " .
		"WHERE		orig_datasource = " . FAKE_DATASOURCE);

  $setDatasourceStmt = $post_conn->prepare(
  		"UPDATE		waypoint ".
		"SET		orig_datasource = ? ".
		"WHERE		internalid = ?");

  $closeStmt = $post_conn->prepare(
  		"UPDATE		waypoint ".
		"SET		deletedon = NOW(), lastupdate = NOW(), ".
		"			lastmajorupdate = NOW() ".
		"WHERE		internalid = ? AND deletedon is null");
}

sub getStateCountry($)
{
  my $long_name = uc(shift);
  $stateStmt->execute($long_name);
  my $id = undef;
  my $country = undef;
  while (my @row = $stateStmt->fetchrow_array)
  {
	$id = $row[0];
	$country = $row[2];
  }
  return ($id, $country);
}

sub getProvince($$)
{
    my ($lat, $long) = @_;
	$provWriter->print("$lat $long\n");
	my $province = $provReader->getline();
	chomp($province);
    return $province;
}

sub procAddress($$$)
{
  my ($addressRef, $country, $state) = @_;

  my $typeRef = $addressRef->{type};
  my $isPolitical = 0;
  my $isCountry = 0;
  my $isState = 0;
  if (ref($typeRef) eq "ARRAY")
  {
	foreach my $type (@${typeRef})
	{
	  if ($type eq "political")
	  {
		$isPolitical = 1;
	  }
	  elsif ($type eq "country")
	  {
		$isCountry = 1;
	  }
	  elsif ($type eq "administrative_area_level_1")
	  {
		$isState = 1;
	  }
	}
  }
  else 
  {
	if ($typeRef eq "political")
	{
	  $isPolitical = 1;
	}
	elsif ($typeRef eq "country")
	{
	  $isCountry = 1;
	}
	elsif ($typeRef eq "administrative_area_level_1")
	{
	  $isState = 1;
	}
  }
  if (!$isPolitical)
  {
	return ($country, $state);
  }
  if ($isCountry && !defined($country))
  {
	$country = $addressRef->{short_name};
  }
  if ($isState && !defined($state))
  {
	$state = $addressRef->{short_name};
  }
  return ($country, $state);
}

sub procResult($$$)
{
  my ($resultRef, $country, $state) = @_;

  my $typeRef = $resultRef->{type};
  my $isPolitical = 0;
  if (ref($typeRef) eq "ARRAY")
  {
	foreach my $type (@${typeRef})
	{
	  if ($type eq "political")
	  {
		$isPolitical = 1;
	  }
	}
  }
  elsif ($typeRef eq "political")
  {
	$isPolitical = 1;
  }

  if ($isPolitical)
  {
	my $addressRef = $resultRef->{address_component};
	if (ref($addressRef) eq "HASH")
	{
	  ($country, $state) = procAddress($addressRef, $country, $state);
	}
	else
	{
	  foreach my $aRef (@${addressRef})
	  {
		if (!defined($country) || !defined($state))
		{
		  ($country, $state) = procAddress($aRef, $country, $state);
		}
	  }
	}
  }
  return ($country, $state);
}

sub getStateCountryFromLatLongGoogle($$)
{
  my ($lat, $long) = @_;

  my $state;
  my $country;

  my $req = HTTP::Request->new(
	  GET =>
	  	"http://maps.googleapis.com/maps/api/geocode/xml?latlng=$lat,$long&sensor=false");
  my $res = $ua->request($req);

  if ($res->is_success)
  {
	my $simpled = $simple->XMLin($res->content);
	if ($simpled->{status} eq "OK")
	{
	  my $resultRef = $simpled->{result};
	  if (ref($resultRef) eq "HASH")
	  {
		($country, $state) = procResult($resultRef, $country, $state);
	  }
	  else
	  {
		foreach my $rRef (@${resultRef})
		{
		  if (!defined($country) || !defined($state))
		  {
			($country, $state) = procResult($rRef, $country, $state);
		  }
		}
	  }
	}
  }
  else
  {
	die $res->status_line, "\n";
  }
  if (defined($country))
  {
	$country = translateCountryCode($country, $state);
  }
  print "getStateCountryFromLatLong returning  country = ",
	  defined($country) ? $country : "undef", ", state = ",
	  defined($state) ? $state : "undef", "\n";
  return ($country, $state);
}

sub procSubdivision($$$)
{
  my ($subDivisionRef, $country, $state) = @_;
  if (!defined($country) && ref($subDivisionRef->{countryCode}) ne "HASH")
  {
	$country = $subDivisionRef->{countryCode};
  }
  elsif (defined($country) && $subDivisionRef->{countryCode} ne $country)
  {
	return ($country, $state);
  }
  if (!defined($state) && exists($subDivisionRef->{adminName1})
	  && ref($subDivisionRef->{adminName1}) ne "HASH")
  {
	$state = $subDivisionRef->{adminName1};
  }
  return ($country, $state);
}

my %provinceLookup = 
(
  "Alberta" => "AB",
  "British Columbia" =>  "BC",
  "Manitoba" =>  "MB",
  "New Brunswick" =>  "NB",
  "Newfoundland" =>  "NF",
  "Newfoundland and Labrador" =>  "NF",
  "Northwest Territories" =>  "NT",
  "Nova Scotia" =>  "NS",
  "Nunavut" =>  "NU",
  "Ontario" =>  "ON",
  "Prince Edward Island" =>  "PE",
  "Quebec" =>  "QC",
  "Saskatchewan" =>  "SK",
  "Yukon Territory" =>  "YT",
  "Yukon" =>  "YT"
);


# Map ocean names to fake FIPS country codes
my %oceanLookup  = 
(
 "ARABIAN SEA"			=>	"XA",
 "BAY OF BENGAL"		=>	"XB",
 "BERING SEA"			=>	"XC",
 "CANARIAS SEA"			=>	"XD",
 "CARIBBEAN SEA"		=>	"XE",
 "CELTIC SEA"			=>	"XF",
 "DAVIS STRAIT"			=>	"XG",
 "EAST CHINA SEA"		=>	"XH",
 "GREENLAND SEA"		=>	"XI",
 "NORTH GREENLAND SEA"	=>	"XI",
 "GULF OF ADEN"			=>	"XJ",
 "GULF OF ALASKA"		=>	"XK",
 "GULF OF GUINEA"		=>	"XL",
 "GULF OF MEXICO"		=>	"XM",
 "GULF OF THAILAND"		=>	"XN",
 "HUDSON BAY"			=>	"XO",
 "ICELAND SEA"			=>	"XP",
 "LABRADOR SEA"			=>	"XQ",
 "LAKSHADWEEP SEA"		=>	"XR",
 "MOZAMBIQUE CHANNEL"	=>	"XS",
 "NORTH SEA"			=>	"XT",
 "NORWEGIAN SEA"		=>	"XU",
 "PHILIPPINE SEA"		=>	"XV",
 "SEA OF OKHOTSK"		=>	"XW",
 "SOUTH CHINA SEA"		=>	"XX",
 "MEDITERRANEAN SEA"	=>	"XY",
 "GULF OF TARTARY"		=>	"XZ",
 "ARCTIC OCEAN"			=>	"OA",
 "INDIAN OCEAN"			=>	"OB",
 "NORTH ATLANTIC OCEAN"	=>	"OC",
 "NORTH PACIFIC OCEAN"	=>	"ZY",
 "SOUTH ATLANTIC OCEAN"	=>	"OE",
 "SOUTH PACIFIC OCEAN"	=>	"OF",
 "ANDAMAN OR BURMA SEA"	=>	"OH",
 "BAY OF BISCAY"		=>	"OI",
 "BARENTS SEA"			=>	"OJ",
 "BLACK SEA"			=>	"OK",
 "TIRRENO SEA"			=>	"OL",
 "TASMAN SEA"			=>	"OM",
 "CORAL SEA"			=>	"ON",
 "JAPAN SEA"			=>	"OO",
 "TIMOR SEA"			=>	"OP",
 "ARAFURA SEA"			=>	"OQ",
 "GULF OF CARPENTARIA"	=>	"AS",
 "BAFFIN BAY"			=>	"OS",
 "LAPTEV SEA"			=>	"RS",
 "KARA SEA"				=>	"RS",
 "BALTIC SEA"			=>	"SW",
 "IONIAN SEA"			=>	"GR",
 "JAWA SEA"				=>	"ID",
 "GULF OF FINLAND"		=>	"FI",
 "GULF OF OMAN"			=>	"MU",
 "CASPIAN SEA"			=>	"RS",
 "ADRIATIC SEA"			=>	"IT",
 "LIGURE SEA"			=>	"IT",
 "PERSIAN GULF"			=>	"SA",
 "THE LITTLE BELT"		=>	"DA",
 "STRAIT OF SICILIA"	=>	"IT",
 "BO SEA"				=>	"CH",
 "COASTAL WATERS OF SOUTHEAST ALASKA AND BRITISH COLUMBIA"
 						=>	"CA",
 "SETO NAIKAI"			=>	"JA",
 "NORTHWESTERN PASSAGES"
						 =>	"CA",
 "NATUNA SEA"			=>	"ID",
 "BALEAR SEA"			=>	"SP",
 "SULU SEA"				=>	"RP",
 "YELLOW SEA"			=>	"CH",
 "ANADYRSKIY GULF"		=>	"RS",
 "SKAGERRAK"			=>	"DA",
 "MALACCA STRAIT"		=>	"MY",
 "SEA OF JAPAN"			=>	"JA",
 "THE SOUND"			=>	"DA",
 "GULF OF RIGA"			=>	"LG",
 "GULF OF BOTHNIA"	    =>	"SW",
 "BEAUFORT SEA" 	    =>	"CA",
 "SOLOMON SEA" 	        =>	"BP",
 "BASS STRAIT" 	        =>	"AS",
 "GULF OF ST LAWRENCE" 	=>	"CA",
 "HUDSON STRAIT" 	    =>	"CA",
 "BAY OF FUNDY" 	    =>	"CA",
 "IRISH SEA AND ST. GEORGE'S CHANNEL"
                        =>	"EI",
 "LINCOLN SEA" 	        =>	"CA",
 "EAST SIBERIAN SEA" 	=>	"RS",
 "ENGLISH CHANNEL" 	=>	"UK",
);

my $lastCall;

sub getStateCountryFromLatLong($$)
{
  my ($lat, $long) = @_;

  my $state;
  my $country;

  my $status = 15;
  my $radius = 1;
  while ($status == 15 && $radius < 126)
  {
print "getStateCountryFromLatLong: trying radius $radius\n";
	my $currentTime = [gettimeofday];
	if (defined($lastCall))
	{
	  my $interval = GEONAMES_INTERVAL -
		(tv_interval($lastCall, $currentTime) * 1000);
	  if ($interval > 0)
	  {
print "getStateCountryFromLatLong: sleeping for $interval\n";
		usleep($interval);
	  }
	  else
	  {
print "getStateCountryFromLatLong: it's been $interval\n";
	  }
	}

	my $req = HTTP::Request->new(
		GET =>
		  "http://api.geonames.org/countrySubdivision?lat=$lat&lng=$long&radius=$radius&username=ptomblin");

	my $res = $ua->request($req);
	$lastCall = [gettimeofday];

	if ($res->is_success)
	{
	  my $simpled = $simple->XMLin($res->content);
print "simpled = ", Dumper($simpled), "\n";
	  if (exists($simpled->{status}) &&
			exists($simpled->{status}->{value}))
	  {
		$status = $simpled->{status}->{value};
	  }
	  elsif (defined($simpled->{countrySubdivision}))
	  {
		$status = 0;
		my $hashRef = $simpled->{countrySubdivision};
		if (ref($hashRef) eq "HASH")
		{
		  ($country, $state) = procSubdivision($hashRef, $country, $state);
		}
		else
		{
		  foreach my $subDivision (@${hashRef})
		  {
			($country, $state) = procSubdivision($subDivision, $country,
				$state);
		  }
		}
		if (defined($country) && $country eq "CA" and !defined($state))
		{
		  $status = 15;
		}
	  }
	  else
	  {
		die "Can't figure out what to do with ", Dumper($simpled), "\n";
	  }
	}
	else
	{
	  die $res->status_line, "\n";
	}
	$radius *= 5;
  }
  if (defined($country))
  {
	$country = translateCountryCode($country, $state);
	die "can't translate country \n" if (!defined($country));
  }
  if (!defined($country))
  {
    my $status = 15;
    my $radius = 1;
    while ($status == 15 && $radius < 126)
    {
      my $currentTime = [gettimeofday];
      if (defined($lastCall))
      {
        my $interval =
          GEONAMES_INTERVAL - (tv_interval($lastCall, $currentTime) * 1000);
        if ($interval > 0)
        {
          print "getStateCountryFromLatLong: ocean sleeping for $interval\n";
          usleep($interval);
        }
        else
        {
          print "getStateCountryFromLatLong: ocean it's been $interval\n";
        }
      }
      my $req = HTTP::Request->new(GET =>
          "http://api.geonames.org/ocean?lat=$lat&lng=$long&radius=$radius&username=ptomblin");

      my $res = $ua->request($req);
      $lastCall = [gettimeofday];

      if ($res->is_success)
      {
print "is_success is true\n";
        my $simpled = $simple->XMLin($res->content);
        if ( exists($simpled->{status})
          && exists($simpled->{status}->{value}))
        {
          $status = $simpled->{status}->{value};
print "status = $status\n"
        }
        elsif (defined($simpled->{ocean}))
        {
          $status  = 0;
          $country = $simpled->{ocean}->{name};
          $country =~ s/,.*//;
print "country = $country\n";
          if (exists($oceanLookup{uc($country)}))
          {
            $country = $oceanLookup{uc($country)};
          }
          else
          {
            #die "No lookup for $country\n";
            printf "Error: No lookup for $country\n";
            return;
          }
        }
        else
        {
          die "Can't figure out what to do with ", Dumper($simpled), "\n";
        }
      }
      else
      {
	printf "ocean error $res->status_line\n";
        die $res->status_line, "\n";
      }
      $radius *= 5;
    }
  }
  if (!defined($country))
  {
	print "Error: unable to translate ($lat, $long) into a country!\n";
	return;
  }

  if ($country eq "CA" && defined($state))
  {
	if (!exists($provinceLookup{$state}))
	{
	  print "getStateCountryFromLatLong can't find $state\n";
	}
	else
	{
	  $state = $provinceLookup{$state};
	}
  }
  print "getStateCountryFromLatLong returning  country = ",
	  defined($country) ? $country : "undef", ", state = ",
	  defined($state) ? $state : "undef", "\n";
  return ($country, $state);
}

sub getMagVar($$$)
{
    my ($lat, $long, $elev) = @_;
	if (!defined($elev) or $elev eq "")
	{
		$elev = 0;
	}
	# I changed the sign convention for the longitude
	$long = -$long;
	$magvarWriter->print("$lat $long $elev $year\n");
	my $magvar = $magvarReader->getline();
	chomp($magvar);
    return $magvar + 0.0;
}

sub getQuadID()
{
  my $id = undef;
  $quadNextValStmt->execute();
  while (my @row = $quadNextValStmt->fetchrow_array())
  {
	$id = $row[0];
  }
  return $id;
}

sub getNextInternalID()
{
  my $id = undef;
  $getNextInternalIDStmt->execute();
  while (my @row = $getNextInternalIDStmt->fetchrow_array())
  {
	$id = $row[0];
  }
  return $id;
}

# Get the Cell for a given point.  Note that the point needs to be in WKT
# format.
sub getCell($)
{
  my ($pnt) = @_;
  $getQuadStmt->execute($pnt);
  my $cell = undef;
  while (my @row = $getQuadStmt->fetchrow_array)
  {
	$cell = $row[0];
  }
  return $cell;
}

sub splitCell($$)
{
  my ($cell, $line) = @_;

  my %resplit;

print "Splitting quadcell $cell\n";
#print "shape = ", Dumper($line), "\n";

  # We've exceeded the max, split it.
  # 1. Insert 4 new areas
  my ($min_long, $min_lat, $max_long, $max_lat) = $line->bbox;
  my $half_lat = ($min_lat + $max_lat) / 2.0;
  my $half_long = ($min_long + $max_long) / 2.0;
  my @cellIDs = ();
  # 1a. bottom left
  my $newCell = getQuadID();
  push @cellIDs, $newCell;
  my $area = Geo::Line->filled(
		Geo::Point->latlong($min_lat, $min_long),
		Geo::Point->latlong($half_lat, $min_long),
		Geo::Point->latlong($half_lat, $half_long),
		Geo::Point->latlong($min_lat, $half_long),
		Geo::Point->latlong($min_lat, $min_long));
  $quadInsertStmt->execute($newCell, $cell, wkt_polygon($area));
  my $newCount = $moveWaypointsQuadStmt->execute($newCell, $cell,
		  $newCell);
  $quadSetStmt->execute($newCount, $newCell) if ($newCount > 0);
  if ($newCount > $maxPerQuad)
  {
	$resplit{$newCell} = $area;
  }

print "$newCount in bottom left ($newCell)\n";

  # 1b. top left
  $newCell = getQuadID();
  push @cellIDs, $newCell;
  $area = Geo::Line->filled(
		Geo::Point->latlong($half_lat, $min_long),
		Geo::Point->latlong($max_lat, $min_long),
		Geo::Point->latlong($max_lat, $half_long),
		Geo::Point->latlong($half_lat, $half_long),
		Geo::Point->latlong($half_lat, $min_long)); 
  $quadInsertStmt->execute($newCell, $cell, wkt_polygon($area));
  $newCount = $moveWaypointsQuadStmt->execute($newCell, $cell,
		  $newCell);
  $quadSetStmt->execute($newCount, $newCell) if ($newCount > 0);
  if ($newCount > $maxPerQuad)
  {
	$resplit{$newCell} = $area;
  }
print "$newCount in top left ($newCell)\n";

  # 1c. bottom right
  $newCell = getQuadID();
  push @cellIDs, $newCell;
  $area = Geo::Line->filled(
		Geo::Point->latlong($min_lat, $half_long),
		Geo::Point->latlong($half_lat, $half_long),
		Geo::Point->latlong($half_lat, $max_long),
		Geo::Point->latlong($min_lat, $max_long),
		Geo::Point->latlong($min_lat, $half_long));
  $quadInsertStmt->execute($newCell, $cell, wkt_polygon($area));
  $newCount = $moveWaypointsQuadStmt->execute($newCell, $cell,
		  $newCell);
  $quadSetStmt->execute($newCount, $newCell) if ($newCount > 0);
  if ($newCount > $maxPerQuad)
  {
	$resplit{$newCell} = $area;
  }
print "$newCount in bottom right ($newCell)\n";

  # 1d. top right
  $newCell = getQuadID();
  push @cellIDs, $newCell;
  $area = Geo::Line->filled(
		Geo::Point->latlong($half_lat, $half_long),
		Geo::Point->latlong($max_lat, $half_long),
		Geo::Point->latlong($max_lat, $max_long),
		Geo::Point->latlong($half_lat, $max_long),
		Geo::Point->latlong($half_lat, $half_long));
  $quadInsertStmt->execute($newCell, $cell, wkt_polygon($area));
  $newCount = $moveWaypointsQuadStmt->execute($newCell, $cell,
		  $newCell);
  $quadSetStmt->execute($newCount, $newCell) if ($newCount > 0);
  if ($newCount > $maxPerQuad)
  {
	$resplit{$newCell} = $area;
  }
print "$newCount in top right ($newCell)\n";

  # Now supercede the old one
  $quadSupercedeStmt->execute($cell);

  foreach my $key (keys %resplit)
  {
	splitCell($key, $resplit{$key});
  }
}

# 
# After adding a point, call this to increment the count in a given cell,
# then check to see if a given quad cell has more than "$maxPerQuad" entries in
# it, and if so it will split the quad into 4 sub quads and assign all the 
# members of the quad to the appropriate sub quads
sub incrementAndSplitCell($)
{
  my ($cell) = @_;

  if (TEST_MODE)
  {
	return;
  }

  $quadIncStmt->execute($cell);
  
  my $count = 0;
  my $shape = undef;
  $quadGetCountStmt->execute($cell);
  while (my @row = $quadGetCountStmt->fetchrow_array)
  {
	$count = $row[0];
	$shape = parse_wkt($row[1]);
  }
  if ($count > $maxPerQuad)
  {
	splitCell($cell, $shape->geo_outer);
  }
}

sub fixBogusQuadCells()
{
  $quadGetDuplicatesStmt->execute();
  while (my @row = $quadGetDuplicatesStmt->fetchrow_array)
  {
	my $rectangle = $row[0];
	my $supercedes = $row[1];
    print "found a duplicate rectangle $rectangle\n";

	# Go through all the areas that are duplicates, starting with the 
	# one with the most points.  Move all the waypoints from the smaller
	# ones and delete their areaids.
	$quadGetDupIDsStmt->execute($rectangle)
	or die $quadGetDupIDsStmt->errstr;
	my @dupRow = $quadGetDupIDsStmt->fetchrow_array;
	my $goodCell = $dupRow[0];
	my $pointCount = $dupRow[1];
	while (@dupRow = $quadGetDupIDsStmt->fetchrow_array)
	{
		my $dupAreaID = $dupRow[0];

		my $incPoint = $moveWaypointsQuadStmt->execute($goodCell,
			$dupAreaID, $goodCell);
		print "moved $incPoint points from $dupAreaID to $goodCell\n";
		$pointCount += $incPoint;
		$quadDeDupIDStmt->execute($dupAreaID);
	}
	$quadSetStmt->execute($pointCount, $goodCell);
  }
}

sub rebalanceQuadTree()
{
  $quadGetOverBalanceStmt->execute($maxPerQuad);
  my $cell = undef;
  my $shape = undef;
  while (my @row = $quadGetOverBalanceStmt->fetchrow_array)
  {
	$cell = $row[0];
	$shape = parse_wkt($row[1]);

	splitCell($cell, $shape->geo_outer);
  }
}

sub postLoad()
{
	if (TEST_MODE)
	{
	  return;
	}

	my $getNextGapStmt = $post_conn->prepare(
		"SELECT		pdb_id+1 " .
		"FROM		id_mapping i1 " .
		"WHERE		NOT EXISTS (".
		"	SELECT		pdb_id ".
		"	FROM		id_mapping i2 ".
		"	WHERE		i1.pdb_id+1 = i2.pdb_id) ".
		"ORDER BY	pdb_id ".
		"LIMIT		1");
	my $selectStmt = $post_conn->prepare(
		"SELECT		distinct(a.id) " .
		"FROM		waypoint a " .
		"LEFT JOIN	id_mapping b " .
		"ON			a.id = b.id " .
		"WHERE		b.id is null");
	my $insertStmt = $post_conn->prepare(
		"INSERT " .
		"INTO		id_mapping(id, pdb_id) " .
		"VALUES		(?,?)");

	$selectStmt->execute() or die $selectStmt->errstr;
	my $maxNumber;

	while (my @row = $selectStmt->fetchrow_array)
	{
		my ($id) = @row;
		print "new ID: $id\n";

		$getNextGapStmt->execute() or die $getNextGapStmt->errstr;
		while (my @gngsRow = $getNextGapStmt->fetchrow_array)
		{
		  $maxNumber = $gngsRow[0];
		}
		print "inserting $id,  $maxNumber\n";
        $insertStmt->execute($id, $maxNumber);
	}

	print "Rebuilding country extents\n";
	$post_conn->do(
		"DELETE " .
		"FROM		country_extents");

	$post_conn->do(
		"INSERT " .
		"INTO		country_extents " .
		"			(country, min_long, min_lat, max_long, max_lat) " .
		"SELECT		country||'-E', min(longitude), min(latitude), " .
		"			max(longitude), max(latitude) " .
		"FROM		waypoint " .
        "WHERE      longitude >= 0 " .
		"GROUP BY	country");

	$post_conn->do(
		"INSERT " .
		"INTO		country_extents " .
		"			(country, min_long, min_lat, max_long, max_lat) " .
		"SELECT		country||'-W', min(longitude), min(latitude), " .
		"			max(longitude), max(latitude) " .
		"FROM		waypoint " .
        "WHERE      longitude <= 0  " .
		"GROUP BY	country");


	print "Rebuilding state/province extents\n";
	$post_conn->do(
		"DELETE " .
		"FROM		state_country_extents");
	$post_conn->do(
		"INSERT " .
		"INTO		state_country_extents " .
		"			(country, state, min_long, min_lat, max_long, max_lat) " .
		"SELECT		country, coalesce(state,'')||'-E', min(longitude), min(latitude), " .
		"			max(longitude), max(latitude) " .
		"FROM		waypoint " .
		"WHERE		country in ('US','CA')  AND longitude >= 0 " .
		"GROUP BY	country, coalesce(state,'')");
	$post_conn->do(
		"INSERT " .
		"INTO		state_country_extents " .
		"			(country, state, min_long, min_lat, max_long, max_lat) " .
		"SELECT		country, coalesce(state,'')||'-W', min(longitude), min(latitude), " .
		"			max(longitude), max(latitude) " .
		"FROM		waypoint " .
		"WHERE		country in ('US','CA') AND longitude <= 0 " .
		"GROUP BY	country, coalesce(state,'')");
}

sub getRunways($)
{
    my ($internalid) = @_;

    $getRunwayStmt->execute($internalid)
	or die $getRunwayStmt->errstr;

    my @runways = ();
    while (my @row = $getRunwayStmt->fetchrow_array)
    {
        my ($runway_designation, $length, $width, $surface,
            $b_lat, $b_long, $b_heading, $b_elev,
            $e_lat, $e_long, $e_heading, $e_elev) = @row;
        push @runways, {
            "designation" => $runway_designation,
            "length" => $length,
            "width" => $width,
            "surface" => $surface,
            "b_lat" => $b_lat,
            "b_long" => $b_long,
            "b_heading" => $b_heading,
            "b_elev" => $b_elev,
            "e_lat" => $e_lat,
            "e_long" => $e_long,
            "e_heading" => $e_heading,
            "e_elev" => $e_elev,
			"closed" => 0
        };
    }
    return \@runways;
}

sub fixFrequency($)
{
  my $freq = shift;
  $freq =~ s/ *M*$//;
  if ($freq =~ m/^[0-9]+\.?[0-9]*$/)
  {
	$freq = sprintf("%.3f", $freq);
  }
  return $freq;
}

sub getFrequencies($$)
{
    my ($internalid, $main_frequency) = @_;

    my @freqs = ();

    my $found = 0;

    $getFrequencyStmt->execute($internalid)
	or die $getFrequencyStmt->errstr;

    while (my @row = $getFrequencyStmt->fetchrow_array)
    {
        my ($comm_type, $frequency, $comm_name) = @row;

		# Get rid of that stupid "M" on the end
		$frequency = fixFrequency($frequency);

        $found = 1;
        push @freqs, {
            "type" => $comm_type,
            "frequency" => $frequency,
            "name" => $comm_name
        };
    }

    if ($main_frequency && !$found)
    {
		$main_frequency = fixFrequency($main_frequency);

        push @freqs, { 
            "type" => "CTAF",
            "frequency" => $main_frequency,
            "name" => "CTAF"
        };
    }

    return \@freqs;
}

sub getFIX($)
{
    my ($internalid) = @_;

    $getFixStmt->execute($internalid)
	or die $getFixStmt->errstr;

    my @fixes = ();
    while (my @row = $getFixStmt->fetchrow_array)
    {
        my ($navaid, $navaid_type,
            $radial_bearing, $distance) = @row;
        push @fixes, {
            "navaid" => $navaid,
            "navaid_type" => $navaid_type,
            "radial_bearing" => $radial_bearing,
            "distance" => $distance
        };
    }
    return \@fixes;
}

# Delete a waypoint - should only be used in preparation for re-inserting
# it, not for marking a waypoint as deleted - you do that by setting
# "deletedon" to date, and re-inserting it.
sub deleteWaypoint($$)
{
  my ($internalid, $areaid) = @_;
  if (TEST_MODE)
  {
	print "deleteWaypoint($internalid)\n";
	return;
  }
  $quadDecStmt->execute($areaid);
  $delRunwayStmt->execute($internalid);
  $delFrequencyStmt->execute($internalid);
  $delFixStmt->execute($internalid);
  $delWaypointStmt->execute($internalid);
}

sub copyAttribute($$$)
{
  my ($newRef, $oldRef, $attr) = @_;

  my $diff = 0;

  if (defined($newRef->{$attr}))
  {
	if (!defined($oldRef->{$attr}) ||
	  ($oldRef->{$attr} ne $newRef->{$attr}))
	{
print "attribute $attr was [",
defined($oldRef->{$attr}) ?  $oldRef->{$attr} : "undef", "], is [",
$newRef->{$attr}, "]\n";
	  $oldRef->{$attr} = $newRef->{$attr};
	  $diff = 1;
	}
  }
  return $diff;
}

# Runways are special, because DAFIF gave us data (end coordinates, etc)
# that nobody else gives us, and we don't want to lose that.
# - If the new data includes any runways that aren't in the old data, we
# need to use the one from the new data.
# - If there are runways in the old data that aren't in the new one,
# then we should probably toss them - assume the runways have closed or
# changed designation
# - If there are runways in both, and there are differences, copy from the
# new data to the old and set the "doWrite" flag.
sub copyRunways($$)
{
  my ($newRef, $oldRef) = @_;
  my $doWrite = 0;
  if (defined($newRef->{runways}) && scalar(@{$newRef->{runways}}))
  {
	if (defined($oldRef->{runways}) && scalar(@{$oldRef->{runways}}))
	{
	  my @runways = ();
	  # Both are defined, so we need to compare them.
	  my @newRefCopy = 
	  		sort { $a->{designation} cmp $b->{designation}} 
			@{$newRef->{runways}};
	  my @oldRefCopy = 
	  		sort { $a->{designation} cmp $b->{designation}} 
			@{$oldRef->{runways}};
	  my $newRec = shift @newRefCopy;
	  my $oldRec = shift @oldRefCopy;
	  while (defined($newRec) && defined($oldRec))
	  {
		if ($newRec->{designation} lt $oldRec->{designation})
		{
		  push @runways, $newRec;
		  $newRec = shift @newRefCopy;
		  $doWrite = 1;
		}
		elsif ($newRec->{designation} eq $oldRec->{designation})
		{
		  foreach my $attr("length", "width", "surface",
			"b_lat", "b_long", "b_heading", "b_elev",
			"e_lat", "e_long", "e_heading", "e_elev")
		  {
			$doWrite += copyAttribute($newRec, $oldRec, $attr);
		  }
		  push @runways, $oldRec;
		  $newRec = shift @newRefCopy;
		  $oldRec = shift @oldRefCopy;
		}
		else
		{
		  $oldRec = shift @oldRefCopy;
		}
	  }
	  # Take care of any left over newRecs
	  while (defined($newRec))
	  {
		push @runways, $newRec;
		$newRec = shift @newRefCopy;
		$doWrite = 1;
	  }
	  if ($doWrite)
	  {
		$oldRef->{runways} = \@runways;
	  }
	}
	else
	{
	  $oldRef->{runways} = $newRef->{runways};
	  $doWrite = 1;
	}
  }
print "different runways\n" if ($doWrite);
  return $doWrite;
}

# With communication frequencies, we don't care what we had before, only
# if it's different from what we had already.  If we have any records in
# the old that aren't in the new, or in the new that aren't in the old, or
# the records differ in any way, we use the new one.
sub copyCommFreqs($$)
{
  my ($newRef, $oldRef) = @_;
  my $doWrite = 0;
  if (defined($newRef->{frequencies}) &&
	 scalar(@{$newRef->{frequencies}}))
  {
	if (defined($oldRef->{frequencies}) &&
	  scalar(@{$oldRef->{frequencies}}))
	{
	  # Both are defined, so we need to compare them.
	  my @newRefCopy = 
	  		sort {	$a->{frequency} cmp $b->{frequency} ||
					$a->{type} cmp $a->{type} ||
					$a->{name} cmp $b->{name}} 
			@{$newRef->{frequencies}};
	  my @oldRefCopy = 
	  		sort {	$a->{frequency} cmp $b->{frequency} ||
					$a->{type} cmp $a->{type} ||
					$a->{name} cmp $b->{name}} 
			@{$oldRef->{frequencies}};
	  my $newRec = shift @newRefCopy;
	  my $oldRec = shift @oldRefCopy;
	  while (defined($newRec) && defined($oldRec))
	  {
		if ($newRec->{frequency} lt $oldRec->{frequency})
		{
		  $newRec = shift @newRefCopy;
		  $doWrite = 1;
		}
		elsif ($newRec->{frequency} eq $oldRec->{frequency})
		{
		  foreach my $attr("type", "name")
		  {
			$doWrite += copyAttribute($newRec, $oldRec, $attr);
		  }
		  $newRec = shift @newRefCopy;
		  $oldRec = shift @oldRefCopy;
		}
		else
		{
		  $oldRec = shift @oldRefCopy;
		}
	  }
	  # Take care of any left over newRecs
	  while (defined($newRec))
	  {
		$newRec = shift @newRefCopy;
		$doWrite = 1;
	  }
	}
	else
	{
	  $doWrite = 1;
	}
  }
  if ($doWrite)
  {
	$oldRef->{frequencies} = $newRef->{frequencies};
  }
print "different frequencies\n" if ($doWrite);
  return $doWrite;
}

# With fix info, we don't care what we had before, only if it's different
# from what we had already.  If we have any records in the old that aren't
# in the new, or in the new that aren't in the old, or the records differ
# in any way, we use the new one.
sub copyFix($$)
{
  my ($newRef, $oldRef) = @_;
  my $doWrite = 0;
  if (defined($newRef->{fixinfo}) &&
	 scalar(@{$newRef->{fixinfo}}))
  {
	if (defined($oldRef->{fixinfo}) &&
	  scalar(@{$oldRef->{fixinfo}}))
	{
	  # Both are defined, so we need to compare them.
	  my @newRefCopy = 
	  		sort { $a->{navaid} cmp $b->{navaid}} 
			@{$newRef->{fixinfo}};
	  my @oldRefCopy = 
	  		sort { $a->{navaid} cmp $b->{navaid}} 
			@{$oldRef->{fixinfo}};
	  my $newRec = shift @newRefCopy;
	  my $oldRec = shift @oldRefCopy;
	  while (defined($newRec) && defined($oldRec))
	  {
		if ($newRec->{navaid} lt $oldRec->{navaid})
		{
		  $newRec = shift @newRefCopy;
		  $doWrite = 1;
		}
		elsif ($newRec->{navaid} eq $oldRec->{navaid})
		{
		  foreach my $attr("navaid_type", "radial_bearing", "distance")
		  {
			$doWrite += copyAttribute($newRec, $oldRec, $attr);
		  }
		  $newRec = shift @newRefCopy;
		  $oldRec = shift @oldRefCopy;
		}
		else
		{
		  $oldRec = shift @oldRefCopy;
		}
	  }
	  # Take care of any left over newRecs
	  while (defined($newRec))
	  {
		$newRec = shift @newRefCopy;
		$doWrite = 1;
	  }
	}
	else
	{
	  $doWrite = 1;
	}
  }
  if ($doWrite)
  {
	$oldRef->{fixinfo} = $newRef->{fixinfo};
  }
print "different fixinfo\n" if ($doWrite);
  return $doWrite;
}

sub compareWaypoints($$)
{
  my ($newRef, $oldRef) = @_;
  my $doWrite = 0;
  my $isMajor = 0;

  # major changes
  foreach my $attr("id", "internalid", "type", "name",
	  "address", "state", "country", "latitude", "longitude",
	  "main_frequency", "tpa",
	  "ispublic")
  {
	$doWrite += copyAttribute($newRef, $oldRef, $attr);
  }

  # XXX Kluge alert - if we don't trust the new point's "deletedon"
  # status, we can set $newRef->{trust_deleted} to 0
  my $newDeleted = $newRef->{deletedon};
  my $oldDeleted = $oldRef->{deletedon};
  my $trustNew = defined($newRef->{trust_deleted}) ?
	   $newRef->{trust_deleted} : 1;
  if (!defined($oldDeleted))
  {
	if (defined($newDeleted))
	{
	  # It wasn't deleted before, and it is now.
	  $doWrite = 1;
	  $oldRef->{deletedon} = $newRef->{deletedon};
	}
  }
  else
  {
	if (!defined($newDeleted) && $trustNew)
	{
	  # It was deleted before, and it isn't now
	  $doWrite = 1;
	  $oldRef->{deletedon} = undef;
	}
  }

  if ($doWrite)
  {
	$isMajor = 1;
  }

  # minor changes
  foreach my $attr("declination", "elevation", "hasfuel",
	"our_airports_id", "faa_id", "ead_id")
  {
	$doWrite += copyAttribute($newRef, $oldRef, $attr);
  }

  # chart_map is a little different because it's a bitmap.
  if (exists($newRef->{chart_map}) &&
	  defined($newRef->{chart_map}) &&
	  exists($oldRef->{chart_map}) &&
	  defined($oldRef->{chart_map}) &&
	  $oldRef->{chart_map} !=
	  $newRef->{chart_map})
  {
print "chart map different: old [", $oldRef->{chart_map}, "], new [",
$newRef->{chart_map}, "]\n";
	  $oldRef->{chart_map} = $newRef->{chart_map};
	  $doWrite++;
  }
  else
  {
	$doWrite += copyAttribute($newRef, $oldRef, "chart_map");
  }

  # We treat runways special, because the "new" data might be missing
  # beginning and end coordinates like FAA and DAFIF data does.
  $doWrite += copyRunways($newRef, $oldRef);
  
  # We're going to assume that if the new data includes comm freqs or fix
  # definitions, it's complete, so we don't have do to anything special.
  $doWrite += copyCommFreqs($newRef, $oldRef);
  $doWrite += copyFix($newRef, $oldRef);

  return ($doWrite, $isMajor);
}

# Get a waypoint from the database by internalid, and stick it into a hash
# Values in the hash include:
#	id				- ICAO/FAA id
#	pdb_id  		- CoPilot id (unique by id, but not globally unique)
#	internalid		- Unique id
#	areaid			- Area id
#	type			- Data type
#	name			- Name
#	address			- Street address
#	state			- state or province (US or CA only)
#	country			- FIPS 10.4 country code
#	latitude		- latitude (+ve is North)
#	longitude		- longitude (+ve is East)
#	declination		- declination (+ve is East?)
#	elevation		- MSL feet
#	main_frequency 	- CTAF for airports, navigation freq for navaids
#	category		- 1 == aerodrome, 2 == navaid, 3 == fix
#	chart_map		- For fixes only, bitmap of charts it's on.
#	tpa				- Traffic Pattern Altitude, MSL feet
#	ispublic		- 1 if public, 0 is private
#	deletedon		- Date deleted, if it's deleted.
#	lastupdate		- Date of previous update.
#	orig_datasource	- Original datasource
# 	lastmajorupdate	- (Did we ever define what's major?)
#	point			- WKT version of lat/long
#	hasfuel			- Has fuel (boolean)
#	our_airports_id - id for ourairports.com
#	faa_id			- id from the FAA
#	ead_id			- id from Eurocontrol
#	runways			- Anonymous hash of 
#		designation		- both ends
#		length			- length in feet
#		width			- width in feet
#		surface			- surface
#		b_lat			- beginning latitude
#		b_long			- beginning longitude
#		b_heading		- magnetic heading of runway
#		b_elev			- beginning elevation in feet
#		e_lat			- Same as above for the end
#		e_long
#		e_heading
#		e_elev
#	frequencies		- Anonymous hash of
#		type			- Frequency type
#		frequency		- Frequency in MHz or KHz
#		name			- Name
#	fixinfo			- Anonymous hash of
#		navaid			- navaid id
#		navaid_type		- type
#		radial_bearing	- radial or bearing from navaid
#		distance		- distance from navaid in nautical miles
sub getWaypoint($)
{
  my ($internalid) = @_;
  my %record;

  $getWaypointStmt->execute($internalid)
  or die $post_conn->errstr;

  while (my @row = $getWaypointStmt->fetchrow_array)
  {
	my ($id, $pdb_id, $internalid, $areaid, $type, $name, $address,
		$state, $country, $latitude, $longitude, $declination, $elevation,
		$main_frequency, $category, $chart_map, $tpa, $ispublic,
		$deletedon, $lastupdate, $orig_datasource,
		$lastmajorupdate, $point, $hasfuel, $our_airports_id, $faa_id,
		$ead_id) = @row;
	$record{id} 			= $id;
	$record{pdb_id} 		= $pdb_id;
	$record{internalid} 	= $internalid;
	$record{areaid} 		= $areaid;
	$record{type}			= $type;
	$record{name}			= $name;
	$record{address}		= $address;
	$record{state}			= $state;
	$record{country}		= $country;
	$record{latitude}		= $latitude;
	$record{longitude}		= $longitude;
	$record{declination}	= $declination;
	$record{elevation}		= $elevation;
	$record{main_frequency}	= $main_frequency;
	$record{category}		= $category;
	$record{chart_map}		= $chart_map;
	$record{tpa}			= $tpa;
	$record{ispublic}		= $ispublic;
	$record{deletedon}		= $deletedon;
	$record{lastupdate}		= $lastupdate;
	$record{orig_datasource}
							= $orig_datasource;
	$record{lastmajorupdate}
							= $lastmajorupdate;
	$record{point}			= $point;
	$record{hasfuel}		= $hasfuel;
	$record{our_airports_id}
							= $our_airports_id;
	$record{faa_id}			= $faa_id;
	$record{ead_id}			= $ead_id;
	$record{runways}		= [];
	$record{frequencies}	= [];
	$record{fixinfo}		= [];

	if ($category == 1)
	{
	  $record{runways} 		= getRunways($internalid);
	  $record{frequencies}	= getFrequencies($internalid, $main_frequency);
	}
	elsif ($category == 3)
	{
	  $record{fixinfo}		= getFIX($internalid);
	}
  }
  return \%record;
}

sub putWaypoint($)
{
  my $ref = shift;

  my $internalid = $ref->{internalid};

  if (TEST_MODE)
  {
	print "putWaypoint called\n";
	print Dumper($ref), "\n";
	return;
  }

  $insWaypointStmt->execute(
  	$ref->{id},
	$internalid,
	$ref->{areaid},
	$ref->{type},
	$ref->{name},
	$ref->{address},
	$ref->{state},
	$ref->{country},
	$ref->{latitude},
	$ref->{longitude},
	$ref->{declination},
	$ref->{elevation},
	$ref->{main_frequency},
	$ref->{chart_map},
	$ref->{tpa},
	$ref->{ispublic},
	$ref->{deletedon},
	$ref->{orig_datasource},
	$ref->{lastmajorupdate},
	$ref->{point},
	$ref->{hasfuel}, 
	$ref->{our_airports_id},
	$ref->{faa_id},
	$ref->{ead_id})
  or die "dying in insWaypointStmt ", Dumper($ref), $insWaypointStmt->errstr;

  foreach my $runwayRef (@{$ref->{runways}})
  {
	$insRunwayStmt->execute(
		$internalid,
		$runwayRef->{designation},
		$runwayRef->{length},
		$runwayRef->{width},
		$runwayRef->{surface},
		$runwayRef->{closed},
		$runwayRef->{b_lat},
		$runwayRef->{b_long},
		$runwayRef->{b_heading},
		$runwayRef->{b_elev},
		$runwayRef->{e_lat},
		$runwayRef->{e_long},
		$runwayRef->{e_heading},
		$runwayRef->{e_elev})
	or die "dying in insRunwayStmt", Dumper($runwayRef), $insRunwayStmt->errstr;
  }

  foreach my $freqRef (@{$ref->{frequencies}})
  {
	if (!defined($ref->{main_frequency}) or
		$freqRef->{frequency} ne $ref->{main_frequency} or
		$freqRef->{type} ne "CTAF")
	{
	  $insFrequencyStmt->execute(
		  $internalid,
		  $freqRef->{type},
		  $freqRef->{name},
		  fixFrequency($freqRef->{frequency}))
	  or die "dying in insFrequencyStmt", Dumper($freqRef), $insFrequencyStmt->errstr;
	}
  }

  foreach my $fixRef (@{$ref->{fixinfo}})
  {
	my $radial_bearing = $fixRef->{radial_bearing};
	if (defined($radial_bearing))
	{
	  $radial_bearing = int($radial_bearing + 0.5);
	}
	my $distance = $fixRef->{distance};
	if (defined($distance))
	{
	  $distance = int($distance + 0.5);
	}
	$insFixStmt->execute(
		$internalid,
		$fixRef->{navaid},
		$fixRef->{navaid_type},
		$radial_bearing,
		$distance
		)
	or die "dying in insFixStmt ", Dumper($fixRef), $insFixStmt->errstr;
  }
  incrementAndSplitCell($ref->{areaid});

}

sub getOurAirportsIDMatch($)
{
  my $our_airports_id = shift;
  my $ret = undef;

  $findOurAirportsIDMatchStmt->execute($our_airports_id);
  while (my @row = $findOurAirportsIDMatchStmt->fetchrow_array)
  {
	my $internalid = $row[0];
print "found our_airports id match $internalid\n";
	$ret = getWaypoint($internalid);
  }
  return $ret;
}

sub getFAAIDMatch($)
{
  my $faa_id = shift;
  my $ret = undef;

  $findFAAIDMatchStmt->execute($faa_id);
  while (my @row = $findFAAIDMatchStmt->fetchrow_array)
  {
	my $internalid = $row[0];
print "found faa id match $internalid\n";
	$ret = getWaypoint($internalid);
  }
  return $ret;
}

sub getEADIDMatch($)
{
  my $ead_id = shift;
  my $ret = undef;

  $findEADIDMatchStmt->execute($ead_id);
  while (my @row = $findEADIDMatchStmt->fetchrow_array)
  {
	my $internalid = $row[0];
print "found ead id match $internalid\n";
	$ret = getWaypoint($internalid);
  }
  return $ret;
}

sub getNearExactMatch($$$$$)
{
  my ($id, $type, $category, $point, $undeletedOnly) = @_;
  my $ret = undef;

  if (!defined($category))
  {
  	$category = $typeCategories{$type};
  }
  if (!defined($category))
  {
	die "invalid type $type\n";
  }
  my $ltype;
  if (defined($type))
  {
	($ltype = $type) =~ s?/.*??;
	$ltype .= "%";
  }
  if ($category == 2 and !defined($type))
  {
	die "need type for category 2\n";
  }

  $findNearIDMatchStmt->execute($id, $category, $ltype,
	  $undeletedOnly, $point, $point);
  while (my @row = $findNearIDMatchStmt->fetchrow_array)
  {
	my $internalid = $row[0];
print "found id match $internalid\n";
	$ret = getWaypoint($internalid);
  }

  return $ret;
}

sub getNearInexactMatch($$$$$)
{
  my ($id, $datasource, $type, $point, $undeletedOnly) = @_;
  my $ret = undef;

  (my $ltype = $type) =~ s?/.*??;
  $ltype .= "%";

  my $category = $typeCategories{$type};
  if (!defined($category))
  {
	die "invalid type $type\n";
  }

  print "findNearNonIDMatchStmt->execute($id, $category, $datasource, $ltype, $undeletedOnly, $point, $point)\n";
  $findNearNonIDMatchStmt->execute($id, $category, $datasource,
		  $ltype, $undeletedOnly ? 1 : 0, $point, $point);
  while (my @row = $findNearNonIDMatchStmt->fetchrow_array)
  {
	my $internalid = $row[0];
print "found non id match $internalid";
	$ret = getWaypoint($internalid);
print ", (", $ret->{id}, ")\n";
  }

  return $ret;
}

sub processPoint($$)
{
  my ($newRef, $oldRef) = @_;

  my $datasource = $newRef->{orig_datasource};
  my $point = $newRef->{point};
  my $cell = $newRef->{areaid};

  if (!defined($oldRef))
  {
print "No oldref\n";
	# This is a new one.  Get a new internalid and insert it
	$newRef->{internalid} = getNextInternalID();
	$newRef->{lastmajorupdate} = localtime;
	putWaypoint($newRef);
  }
  else
  {
	# There is an old one.  See if there are enough differences to write
	# it.
	my ($doUpdate, $isMajor) = compareWaypoints($newRef, $oldRef);
print "doUpdate = $doUpdate\n";
	if ($doUpdate)
	{
	  deleteWaypoint($oldRef->{internalid}, $oldRef->{areaid});
	  $oldRef->{orig_datasource} = $datasource;
	  $oldRef->{point} = $point;
	  $oldRef->{areaid} = $cell;
	  if ($isMajor)
	  {
		$oldRef->{lastmajorupdate} = localtime;
	  }
	  putWaypoint($oldRef);
	}
	else
	{
	  # If it's not changed, change its datasource back so it doesn't get
	  # purged later.
	  $setDatasourceStmt->execute(
	  	$datasource, $oldRef->{internalid});
	}
  }
}

# Call this to add/update a waypoint.
# Given a hash (as defined in getWaypoint, but missing the internalid and
# possibly missing the point), it will find if the waypoint already exists in
# the database using either of the following criteria:
#	1. FAA id matches.
#	2. OurAirports id matches
#	3. EAD id matches
#	4. ICAO id matches, and point within "LARGE_EPSILON",
#	category matches,
#	category is 1 (aerodrome) or 3 (fix) or type matches up to the first
#	slash.
#	5. ICAO id doesn't match, but point within "SMALL_EPSILON", 
#	category matches, 
#	category is 1 (aerodrome) or 3 (fix) or type matches up to the first
#	slash,
#	not from this datasource (???)
# In either case, there might be multiple matches (although hopefully not
# in the id maches), so return the nearest.
#
# If that process finds a match, then any fields that are present in the
# new and not in the old, or that are in both but different in the two,
# are copied to the old, and the "updated" date set, and saved back out.
#
# If no match is found, then the new's areaid is found using getCell, and
# then it's inserted, and then we call incrementAndSplitCell.
#
# Note: Sometimes this process copies data from a waypoint to another nearby
# waypoint, and then loses that data when the real match comes along.  So if
# the match is of the "near match" type, it will be queued up in the
# "unprocessed" array until flushWaypoints is called (it's probably safe to
# call this at the end of every country or between airports and navaids,
# otherwise it's called automatically when you call endDatasource.
sub insertWaypoint($)
{
  my $newRef = shift;
  my $id = $newRef->{id};
  my $type = $newRef->{type};
  my $point = undef;
  if (!exists($newRef->{point}))
  {
	$point = getPoint($newRef->{latitude}, $newRef->{longitude});
	$newRef->{point} = $point;
  }
  else
  {
	$point = $newRef->{point};
  }
  my $datasource = $newRef->{orig_datasource};
  my $undeletedOnly = !exists($newRef->{deletedon});
  my $category = $newRef->{category};
print "inserting $id, type = ", $type, "\n";

  # Until we expand the field, ignore states for anybody other than US or
  # Canada
  if (exists($newRef->{state}) && $newRef->{country} ne "US" &&
		$newRef->{country} ne "CA")
  {
	$newRef->{state} = undef;
  }

  my $oldRef = findBestMatch($newRef, $id, $type, $category, $point);

  if (!defined($oldRef))
  {
	# If we don't have an exact id match, look to see if there is a near
	# one.  If there is, store this for later.
	 my $closeRef = getNearInexactMatch($id, $datasource, $type, $point,
		 $undeletedOnly);
	 if (defined($closeRef))
	 {
	   print "Saving $id for later\n";
	   push @unprocessed, $newRef;
	   return;
	 }
  }

  processPoint($newRef, $oldRef);
}

sub getPoint($$)
{
  my ($lat, $long) = @_;
  my $point = wkt_point(Geo::Point->latlong($lat, $long));
  return $point;
}

sub findBestMatch($$$$$)
{
  my ($newRef, $id, $type, $category, $point) = @_;

  if (!defined($point))
  {
	$point = getPoint($newRef->{latitude}, $newRef->{longitude});
	$newRef->{point} = $point;
  }

  my $cell = getCell($point);
  $newRef->{areaid} = $cell;

  my $oldRef = undef;
  # Do we have an faa id?
  if (!defined($oldRef) && defined($newRef->{faa_id}))
  {
	$oldRef = getFAAIDMatch($newRef->{faa_id});
  }
  # Do we have an our airports id?
  if (!defined($oldRef) && defined($newRef->{our_airports_id}))
  {
	$oldRef = getOurAirportsIDMatch($newRef->{our_airports_id});
  }
  # Do we have an ead id?
  if (!defined($oldRef) && defined($newRef->{ead_id}))
  {
	$oldRef = getEADIDMatch($newRef->{ead_id});
  }

  if (!defined($oldRef))
  {
	# Ignore "undeletedOnly" for the exact match.
  	$oldRef = getNearExactMatch($id, $type, $category, $point, 0);
  }
  return $oldRef;
}


# Close an existing waypoint (note that if the waypoint doesn't exist, OR
# it is already closed, this will have no effect).  Needs the type and
# latitude and longitude because we don't want to delete one that has the
# same id but isn't the same point (like a co-located navaid or something)
#
# Arguments
#	- id
#	- type
#	- latitude
#	- longitude
# 
# Returns the number of rows affected.
#
sub closeWaypoint($$$$)
{
  my ($id, $type, $latitude, $longitude) = @_;

  my $point = wkt_point(Geo::Point->latlong($latitude, $longitude));

  my $ref = getNearExactMatch($id, $type, undef, $point, 0);
  if (defined($ref))
  {
	return $closeStmt->execute($ref->{internalid});
  }
  return 0;
}

sub closeOurAirportsWaypoint($)
{
  my ($our_airports_id) = @_;
  my $ref = getOurAirportsIDMatch($our_airports_id);
  if (defined($ref))
  {
	return $closeStmt->execute($ref->{internalid});
  }
  return 0;
}

sub closeFAAWaypoint($)
{
  my ($faa_id) = @_;
  my $ref = getFAAIDMatch($faa_id);
  if (defined($ref))
  {
	return $closeStmt->execute($ref->{internalid});
  }
  return 0;
}

sub closeEADWaypoint($)
{
  my ($ead_id) = @_;
  my $ref = getEADIDMatch($ead_id);
  if (defined($ref))
  {
	return $closeStmt->execute($ref->{internalid});
  }
  return 0;
}

my %usMinorOutlyingIslands = 
(
 	"BAKER ISLAND"		=>	"FQ",
	"HOWLAND ISLAND"	=>	"HQ",
	"JARVIS ISLAND"		=>	"DQ",
 	"JOHNSTON ATOLL"	=>	"JQ",
	"KINGMAN REEF"		=>	"KQ",
	"MIDWAY ISLANDS"	=>	"MQ",
	"NAVASSA ISLAND"	=>	"BQ",
	"PALMYRA ATOLL"		=>	"LQ",
	"WAKE ISLAND"		=>	"WQ"
);


# Translate an ISO country to a FIPs country
#
# Arguments
# 	- iso country code
#
# Returns a fips country code, or undef if not found
sub translateCountryCode($$)
{
  my ($isoCode,$state) = shift;
print "translating ($isoCode, ", defined($state) ? $state : "undef", ")\n";
  # US Minor Outlying Islands is a royal pain
  if ($isoCode eq "UM")
  {
	if (!defined($state))
	{
	  # Kind of cheesy - any unknown UM is Johnston Atoll
	  return "JQ";
	}
	if (exists($usMinorOutlyingIslands{uc($state)}))
	{
	  return $usMinorOutlyingIslands{$state};
	}
	die "unknown UM code $state\n";
  }

  if (!exists($isoCountries{$isoCode}))
  {
	if (!defined($translateCountryStmt))
	{
	  $translateCountryStmt = $post_conn->prepare(
		  "SELECT		iso_code, fips_code, country_name ".
		  "FROM		country_lookups");
	}
	$translateCountryStmt->execute();
	while (my @row = $translateCountryStmt->fetchrow_array)
	{
	  $isoCountries{$row[0]} = $row[1];
	}
  }

  return $isoCountries{$isoCode};
}

# Flush any waypoints that were saved for later.
sub flushWaypoints()
{
  print "flushing queued waypoints\n"; 
  while (my $ref = pop @unprocessed)
  {
	print "processing ", $ref->{id}, "\n";
	my $id = $ref->{id};
	my $datasource = $ref->{orig_datasource};
	my $type = $ref->{type};
	my $point = $ref->{point};

	my $undeletedOnly = !exists($ref->{deletedon});

	my $oldRef = getNearInexactMatch($id, $datasource, $type, $point,
	  $undeletedOnly);
	processPoint($ref, $oldRef);
  }
}

sub startDatasource($)
{
  my $datasource = shift;

  $startDatasourceStmt->execute($datasource);
}

sub endDatasource($)
{
  my $datasource = shift;
  flushWaypoints();

  $endDatasource1Stmt->execute($datasource);
  $endDatasource2Stmt->execute($datasource);
}

1;
__END__
