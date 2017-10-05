#!/usr/bin/perl -w

# EAD AIXM
#

use warnings FATAL => 'all';

use DBI;
use IO::File;
use XML::SAX;

use strict;

binmode STDOUT, ":utf8";

$| = 1; # for debugging

use Datasources;
use WaypointTypes;
use WPInfo;

use PostGIS;

use XML::SAX::ParserFactory;

my $eadFile = shift;
my $dbName = "navaid_copilot";
my $selEADCountryStmt;
my $insEADCountryStmt;
print "loading $eadFile into $dbName\n";

my %orgUIDLookup;

package EADHandler;
use base qw(XML::SAX::Base);
use Data::Dumper;
use Node;
use PostGIS;

sub def
{
  my $str = shift;
  if (!defined($str))
  {
	return "undef";
  }
  return $str;
}

sub getStateCountryFromEADId($)
{
  my $ead_id = shift;
  my ($state, $country);
  $selEADCountryStmt->execute($ead_id);
  while (my @row = $selEADCountryStmt->fetchrow_array)
  {
	($state, $country) = @row;
print "getting state/country from ead_country : ",
		def($country), " - ", def($state), "\n";
  }
  return ($country, $state);
}

sub putStateCountryEAD($$$)
{
  my ($ead_id, $country, $state) = @_;
  if ($country ne "CA") # don't need US for now
  {
	$state = undef;
  }
print "saving state/country to ead_country : ",
		def($country), " - ", def($state), "\n";

  $insEADCountryStmt->execute($ead_id, $state, $country);
}

sub handleAnyRecord($$$$$$$)
{
  my ($wptRef, $lat, $long, $ead_id, $category,
	  $defaultType, $defaultChartMap) = @_;
  my ($rlat,$ns) = ($lat =~ m/([0-9\.]*)([NSEW])/);
  $rlat *= ($ns eq "S" || $ns eq "W") ? -1.0 : 1.0;
  my ($rlon,$ew) = ($long =~ m/([0-9\.]*)([NSEW])/);
  $rlon *= ($ew eq "S" || $ew eq "W") ? -1.0 : 1.0;

  $wptRef->{orig_datasource} = Datasources::DATASOURCE_EAD;
  $wptRef->{latitude} = $rlat;
  $wptRef->{longitude} = $rlon;
  $wptRef->{ead_id} = $ead_id;

  my $id = $wptRef->{id};

  print "before fixing, wptRef: ", Dumper(\$wptRef), "\n";

  # If we don't have country, type, elevation or declination, we see
  # if we have an existing point with this info
  if (!exists($wptRef->{country}) ||
	  !exists($wptRef->{type}) ||
	  !exists($wptRef->{elevation}) ||
	  !exists($wptRef->{declination}) ||
	  (!exists($wptRef->{chart_map}) && defined($defaultChartMap)))
  {
print "finding best match\n";
	my $wType = $wptRef->{type};
	if (!defined($wType))
	{
	  $wType = $defaultType;
	}
	my $oldRef = findBestMatch($wptRef, $id,
		$wType, $category, undef);
print "oldRef ", Dumper($oldRef), "\n";
	if (defined($oldRef))
	{
	  if (!exists($wptRef->{type}))
	  {
		$wptRef->{type} = $oldRef->{type};
	  }
	  if (!exists($wptRef->{country}))
	  {
		$wptRef->{country} = $oldRef->{country};
		if (exists($oldRef->{state}))
		{
		  $wptRef->{state} = $oldRef->{state};
		}
	  }
	  if (!exists($wptRef->{declination}))
	  {
		$wptRef->{declination} = $oldRef->{declination};
	  }
	  if (!exists($wptRef->{elevation}))
	  {
		$wptRef->{elevation} = $oldRef->{elevation};
	  }
	  if (!exists($wptRef->{chart_map}) && defined($defaultChartMap))
	  {
		$wptRef->{chart_map} = $oldRef->{chart_map};
	  }
	}

	if (!exists($wptRef->{type}))
	{
	  if (defined($defaultType))
	  {
		$wptRef->{type} = $defaultType;
	  }
	  else
	  {
		print "Skipping point because no type\n";
		return;
	  }
	}
	if (!exists($wptRef->{country}) || 
		($wptRef->{country} eq "CA" && !exists($wptRef->{state})))
	{
	    my ($country,$state) = getStateCountryFromEADId($ead_id);
		if (!defined($country))
		{
			($country,$state) = getStateCountryFromLatLong($rlat, $rlon);
			return if !$country;
			putStateCountryEAD($ead_id, $country, $state);
		}
		$wptRef->{country} = $country;
		if (defined($state))
		{
		  $wptRef->{state} = $state;
		}
	}
	if (!exists($wptRef->{declination}))
	{
	  $wptRef->{declination} = getMagVar($rlat, $rlon,
		  exists($wptRef->{elevation}) ? $wptRef->{elevation} : 0);
	}
	if (!exists($wptRef->{chart_map}) && defined($defaultChartMap))
	{
	  $wptRef->{chart_map} = $defaultChartMap;
	}
  }
  print "after fixing, wptRef: ", Dumper(\$wptRef), "\n";
  if ($wptRef->{country} eq "US")
  {
	print "skipping US\n";
	return;
  }

  insertWaypoint($wptRef);
}

my $firstWpt = 1;

sub handleWptRecord($)
{
  if ($firstWpt)
  {
	flushWaypoints();
	$firstWpt = 0;
  }

  my $nodeRef = shift;
#print "handleWptRecord: ", Dumper($nodeRef), "\n";
  my $ahpUID = $nodeRef->subNode("AhpUid");
  if (defined($ahpUID))
  {
	print "skipping record at an airport\n";
	return;
  }
  my $ahpUIDAssoc = $nodeRef->subNode("AhpUidAssoc");
#  if (defined($ahpUIDAssoc))
#  {
#	print "skipping record associated with an airport\n";
#	return;
#  }
  my $rcpUID = $nodeRef->subNode("RcpUid");
  if (defined($rcpUID))
  {
	print "skipping record at an runway\n";
	return;
  }
  my $dpnUidSN = $nodeRef->subNode("DpnUid");
  my $mainId = $dpnUidSN->subNodeText("codeId");
  my $txtName = $nodeRef->subNodeText("txtName");
  my $dpnUidMid = $dpnUidSN->attrs->{mid};
  my $lat = $dpnUidSN->subNodeText("geoLat");
  my $long = $dpnUidSN->subNodeText("geoLong");
  print "mainId = ", def($mainId), ", txtName = ", def($txtName),
	", ead_id = ", def($dpnUidMid), "\n";
  print "ll = (", def($lat), ",", def($long), ")\n";
  my %waypoint;
  $waypoint{id} = $mainId;
  $waypoint{name} = $txtName;
  handleAnyRecord(\%waypoint, $lat, $long, $dpnUidMid, 3, "REP-PT", 7);
}

sub handleAirportRecord
{
  my $nodeRef = shift;
#print "handleAirportRecord: ", Dumper($nodeRef), "\n";
  my $subNodeRef = $nodeRef->subNodes;

  my $ahpUidSN = $nodeRef->subNode("AhpUid");
  my $ahpUidMid = $ahpUidSN->attrs->{mid};
  print "mid: ", $ahpUidMid, "\n";
  # This airport is duplicated for Serbia and Kosovo!
  if ($ahpUidMid == 4590849)
  {
	return;
  }
  my $mainId = $ahpUidSN->subNodeText("codeId");
  my $txtName = $nodeRef->subNodeText("txtName");
  my $lat = $nodeRef->subNodeText("geoLat");
  my $long = $nodeRef->subNodeText("geoLong");
  my $elev = $nodeRef->subNodeText("valElev");
  my $uomDistVer = $nodeRef->subNodeText("uomDistVer");
  if (defined($elev)  && $uomDistVer eq "M")
  {
	$elev /= 0.3048;
  }
  my $orgUidRef = $nodeRef->subNode("OrgUid");
  my $orgUidMid = $orgUidRef->attrs->{mid};
  my $orgUidName = $orgUidRef->subNodeText("txtName");
  my $type = $nodeRef->subNodeText("codeType");
  my $city = $nodeRef->subNodeText("txtNameCitySer");
  my $magVar = $nodeRef->subNodeText("valMagVar");
  my $private = $nodeRef->subNodeText("codePriv");
  print "mainId = $mainId, type = $type, txtName = ", def($txtName), ",",
		def($city), ", ll = ($lat,$long), elev = ",
	def($elev), ", private = ", def($private), "\n";
  print "org = $orgUidMid, $orgUidName",
	defined($magVar) ? ", magVar = $magVar" : "", "\n";

  my %airportRef;
  $airportRef{id} = $mainId;
  my $rType;
  if (defined($type))
  {
	if ($type eq "AD" or $type eq "AH")
	{
	  $rType = "AIRPORT";
	}
	elsif ($type eq "HP")
	{
	  $rType = "HELIPORT";
	}
  }
  $airportRef{name} = $txtName;
  if (defined($city))
  {
	$airportRef{address} = $city;
  }
  if (!exists($orgUIDLookup{$orgUidMid}))
  {
	print "ERROR: unknown orguid $orgUidMid, $orgUidName\n";
	return;
  }
  my $country;
  if (defined($orgUIDLookup{$orgUidMid}))
  {
	$country = $orgUIDLookup{$orgUidMid};
	# The US is adequately covered by FAA data
	if ($country eq "US")
	{
	  print "skipping US\n";
	  return;
	}
	if (!($country =~ m!/! or $country eq "CA"))
	{
	  $airportRef{country} = $country;
	}
  }
  else
  {
	print "ERROR: unknown orguid $orgUidMid, $orgUidName\n";
	return;
  }

  if (defined($elev))
  {
	$airportRef{elevation} = $elev * 1.0;
  }
  if (defined($magVar))
  {
	$airportRef{declination} = $magVar * -1.0;
  }
  $airportRef{category} = 1;
  if (defined($private) && $private eq "Y")
  {
	$airportRef{ispublic} = 0;
  }
  else
  {
	$airportRef{ispublic} = 1;
  }

  handleAnyRecord(\%airportRef, $lat, $long, $ahpUidMid, 1, $rType, undef);
}

my $firstVor = 1;

sub handleVorRecord($)
{
  if ($firstVor)
  {
	flushWaypoints();
	$firstVor = 0;
  }

  my $nodeRef = shift;
print "handleVorRecord: ", Dumper($nodeRef), "\n";

  my $vorUidSN = $nodeRef->subNode("VorUid");
  my $mainId = $vorUidSN->subNodeText("codeId");
  my $vorUidMid = $vorUidSN->attrs->{mid};
  my $lat = $vorUidSN->subNodeText("geoLat");
  my $long = $vorUidSN->subNodeText("geoLong");
  print "mainId = ", def($mainId), ", ead_id = ", def($vorUidMid), "\n";
  print "ll = (", def($lat), ",", def($long), ")\n";

  my %waypoint;

  my $orgUidRef = $nodeRef->subNode("OrgUid");
  my $orgUidMid = $orgUidRef->attrs->{mid};
  if (!exists($orgUIDLookup{$orgUidMid}))
  {
	print "ERROR unknown orguid $orgUidMid\n";
	return;
  }
  my $country;
  if (defined($orgUIDLookup{$orgUidMid}))
  {
	$country = $orgUIDLookup{$orgUidMid};
	# The US is adequately covered by FAA data
	if ($country eq "US")
	{
	  print "skipping US\n";
	  return;
	}
	if (!($country =~ m!/! or $country eq "CA"))
	{
	  $waypoint{country} = $country;
	}
  }
  else
  {
	print "ERROR unknown orguid $orgUidMid\n";
	return;
  }

  $waypoint{id} = $mainId;
  $waypoint{name} = $nodeRef->subNodeText("txtName");
  $waypoint{main_frequency} = $nodeRef->subNodeText("valFreq");

  my $elev = $nodeRef->subNodeText("valElev");
  my $uomDistVer = $nodeRef->subNodeText("uomDistVer");
  if (defined($elev)  && $uomDistVer eq "M")
  {
	$elev /= 0.3048;
  }
  if (defined($elev))
  {
	$waypoint{elevation} = $elev * 1.0;
  }

  my $defaultType = $nodeRef->subNodeText("codeType");
  # We don't care if it's doppler or not!
  if ($defaultType eq "DVOR")
  {
	$defaultType = "VOR";
  }
  if ($defaultType eq "OTHER")
  {
	print "Warning skipping VOR type $defaultType\n";
    return;
  }
  handleAnyRecord(\%waypoint, $lat, $long, $vorUidMid, 2, $defaultType, undef);
}

my $firstNdb = 1;

sub handleNdbRecord($)
{
  if ($firstNdb)
  {
	flushWaypoints();
	$firstNdb = 0;
  }

  my $nodeRef = shift;
print "handleNdbRecord: ", Dumper($nodeRef), "\n";

  my $ndbUidSN = $nodeRef->subNode("NdbUid");
  my $mainId = $ndbUidSN->subNodeText("codeId");
  my $ndbUidMid = $ndbUidSN->attrs->{mid};
  my $lat = $ndbUidSN->subNodeText("geoLat");
  my $long = $ndbUidSN->subNodeText("geoLong");
  print "mainId = ", def($mainId), ", ead_id = ", def($ndbUidMid), "\n";
  print "ll = (", def($lat), ",", def($long), ")\n";

  my %waypoint;

  my $orgUidRef = $nodeRef->subNode("OrgUid");
  my $orgUidMid = $orgUidRef->attrs->{mid};
  if (!exists($orgUIDLookup{$orgUidMid}))
  {
	print "ERROR unknown orguid $orgUidMid\n";
	return;
  }
  my $country;
  if (defined($orgUIDLookup{$orgUidMid}))
  {
	$country = $orgUIDLookup{$orgUidMid};
	# The US is adequately covered by FAA data
	if ($country eq "US")
	{
	  print "skipping US\n";
	  return;
	}
	if (!($country =~ m!/! or $country eq "CA"))
	{
	  $waypoint{country} = $country;
	}
  }
  else
  {
	print "ERROR unknown orguid $orgUidMid\n";
	return;
  }

  $waypoint{id} = $mainId;
  $waypoint{name} = $nodeRef->subNodeText("txtName");
  $waypoint{main_frequency} = $nodeRef->subNodeText("valFreq");

  my $elev = $nodeRef->subNodeText("valElev");
  my $uomDistVer = $nodeRef->subNodeText("uomDistVer");
  if (defined($elev)  && $uomDistVer eq "M")
  {
	$elev /= 0.3048;
  }
  if (defined($elev))
  {
	$waypoint{elevation} = $elev * 1.0;
  }
  handleAnyRecord(\%waypoint, $lat, $long, $ndbUidMid, 2, "NDB", undef);
}

my $firstDme = 1;

sub handleDmeRecord($)
{
  if ($firstDme)
  {
	flushWaypoints();
	$firstDme = 0;
  }

  my $nodeRef = shift;
print "handleDmeRecord: ", Dumper($nodeRef), "\n";

  # We use these records to add "/DME" to VOR records only, so we only
  # need this record if it has a VOR id.
  my $vorUidSN = $nodeRef->subNode("VorUid");
  if (!defined($vorUidSN))
  {
	return;
  }
  my $ead_id = $vorUidSN->attrs->{mid};
  my $oldRef = getEADIDMatch($ead_id);

  if (!defined($oldRef))
  {
	return;
  }

  my $type = $oldRef->{type};
print "DME applied to ", $type, "\n";
  if ($type eq "VOR")
  {
	$oldRef->{type} = "VOR/DME";
	insertWaypoint($oldRef);
  }
}
my $firstTcn = 1;

sub handleTcnRecord($)
{
  if ($firstTcn)
  {
	flushWaypoints();
	$firstTcn = 0;
  }

  my $nodeRef = shift;
print "handleTcnRecord: ", Dumper($nodeRef), "\n";

  # We use these records to change "VOR" to "VORTAC" only, so we only
  # need this record if it has a VOR id.
  my $vorUidSN = $nodeRef->subNode("VorUid");
  if (!defined($vorUidSN))
  {
	return;
  }
  my $ead_id = $vorUidSN->attrs->{mid};
  my $oldRef = getEADIDMatch($ead_id);

  if (!defined($oldRef))
  {
	return;
  }

  my $type = $oldRef->{type};
print "TACAN applied to ", $type, "\n";
  if ($type eq "VOR")
  {
	$oldRef->{type} = "VORTAC";
	insertWaypoint($oldRef);
  }
}

my %nodesICareAbout = (
  "Ahp"	=>	\&handleAirportRecord,
  "Dpn"	=>	\&handleWptRecord,
  "Vor"	=>	\&handleVorRecord,
  "Ndb"	=>	\&handleNdbRecord,
  "Dme"	=>	\&handleDmeRecord,
  "Tcn"	=>	\&handleTcnRecord,
);

my $currentNode;
my @nodes;
my $text = undef;

sub start_document
{
  my $self = shift;
  print "start document\n";
}

sub start_element
{
  my ($self, $element) = @_;

  # If we're doing a known node, put in the sub nodes.
  my $localName = $element->{"LocalName"};
  if (defined($currentNode) ||
	  defined($nodesICareAbout{$localName}))
  {
	$text = "";
	my $newNode = Node->new("name" => $element->{"LocalName"});
	my %attributes;
	foreach my $key (keys(%{$element->{Attributes}}))
	{
		my $attrRef = $element->{"Attributes"}->{$key};
	  	$attributes{$attrRef->{"LocalName"}} = $attrRef->{"Value"};
	}
	$newNode->attrs(\%attributes);


	if (defined($currentNode))
	{
	  my $subNodeRef = $currentNode->subNodes;
	  push @$subNodeRef, $newNode;
	  $currentNode->subNodes($subNodeRef);
	  push @nodes, $currentNode;
	}
	$currentNode = $newNode;
  }
}
sub end_element
{
  my ($self, $element) = @_;
  #print "end element = ", Dumper($element), "\n";
  if (defined($currentNode))
  {
	#print "current = ", Dumper(\$currentNode), "\n";
	#print "text = ", (defined($text) ? $text : "null") , "\n";
	if (defined($text))
	{
	  $currentNode->text($text);
	}
	my $localName = $element->{"LocalName"};
	if (defined($nodesICareAbout{$localName}))
	{
	  my $subRef = $nodesICareAbout{$localName};
	  &$subRef($currentNode);
	}
	$text = undef;
	$currentNode = pop(@nodes);
	#print "after pop, currentNode = ", Dumper(\$currentNode), "\n";
  }
}

sub end_document
{
  my $self = shift;
  print "end document\n";
}

sub characters
{
  my ($self, $element) = @_;
  if (defined($text))
  {
	$text .= $element->{"Data"};
  }
}

package main;
#use Data::Dumper;

PostGIS::initialize($dbName);

# Get the list of countries
my $conn = dbConnection();
my $selOrgUIDsStmt = $conn->prepare(
	"SELECT		orguid, country " .
	"FROM		orguid_lookup ");
$selOrgUIDsStmt->execute();
while (my @row = $selOrgUIDsStmt->fetchrow_array)
{
  my ($orguid, $country) = @row;
  $orgUIDLookup{$orguid} = $country;
}

$selEADCountryStmt = $conn->prepare(
	"SELECT		state, country " .
	"FROM		ead_country " .
	"WHERE		ead_id = ?");
$insEADCountryStmt = $conn->prepare(
	"INSERT " .
	"INTO		ead_country " .
	"			(ead_id, state, country) " .
	"VALUES		(?, ?, ?)");


#print "orgUIDs: ", Dumper(\%orgUIDLookup), "\n";

startDatasource(Datasources::DATASOURCE_EAD);

use XML::SAX;

my $factory = XML::SAX::ParserFactory->new();
my $parser = $factory->parser( Handler => EADHandler->new() );

my $finOK = 1;
eval { $parser->parse_file($eadFile); };

if ($@)
{
  $finOK = 0;
}
print "Error parsing file: $@" if !$finOK;


print "finishing up\n";
flushWaypoints();

if ($finOK)
{
	endDatasource(Datasources::DATASOURCE_EAD);
}

print "Done loading\n";

postLoad();

dbClose();
