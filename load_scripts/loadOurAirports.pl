#!/usr/bin/perl -w

use IO::File;
use Text::CSV;

use strict;

$| = 1; # for debugging

use Datasources;
use WPInfo;

use PostGIS;
PostGIS::initialize();

my %typeMap = (
  "small_airport"	=>	"AIRPORT",
  "medium_airport"	=>	"AIRPORT",
  "large_airport"	=>	"AIRPORT",
  "heliport"		=>  "HELIPORT",
  "balloonport"		=>  "BALLOONPORT",
  "seaplane_base"	=>	"SEAPLANE BASE",
);

my $dir = shift;

my $airportsFile = $dir."/airports-sorted.csv";
my $runwaysFile = $dir."/runways-sorted.csv";
my $freqFile = $dir."/airport-frequency-sorted.csv";
my $navaidFile = $dir."/navaids-sorted.csv";
# Sort all the files by airport id
system("sort", "-n", "-t", ",", "-k", "1", "-o",
  $airportsFile, $dir."/airports.csv");
system("sort", "-n", "-t", ",", "-k", "2", "-o",
  $runwaysFile, $dir."/runways.csv");
system("sort", "-n", "-t", ",", "-k", "2", "-o",
  $freqFile, $dir."/airport-frequencies.csv");
system("sort", "-n", "-t", ",", "-k", "1", "-o",
  $navaidFile, $dir."/navaids.csv");


my $airportFH = new IO::File($airportsFile) or die "Airport file $airportsFile not found";
my $runwaysFH = new IO::File($runwaysFile) or die "Runways file $runwaysFile not found";
my $freqFH = new IO::File($freqFile) or die "Frequency file $freqFile not found";
my $navaidFH = new IO::File($navaidFile) or die "Navaid file $navaidFile not found";

my $airportCSV;
$airportCSV = Text::CSV->new({binary => 1})
#$airportCSV = Text::CSV->new({blank_is_undef => 1})
or die Text::CSV->error_diag();

$airportCSV->types([
	Text::CSV::IV(), # id
	Text::CSV::PV(), # ident
	Text::CSV::PV(), # type
	Text::CSV::PV(), # name
	Text::CSV::NV(), # latitude_deg
	Text::CSV::NV(), # longitude_deg
	Text::CSV::NV(), # elevation_ft
	Text::CSV::PV(), # continent
	Text::CSV::PV(), # iso_country
	Text::CSV::PV(), # iso_region
	Text::CSV::PV(), # municipality
	Text::CSV::PV(), # schedule_service
	Text::CSV::PV(), # gps_code
	Text::CSV::PV(), # iata_code
	Text::CSV::PV(), # local_code
	Text::CSV::PV(), # home_link
	Text::CSV::PV(), # wikipedia link
	Text::CSV::PV()  # keywords
	]);

my $runwaysCSV;
$runwaysCSV = Text::CSV->new({binary => 1})
or die Text::CSV->error_diag();
$runwaysCSV->types([
	Text::CSV::IV(), # id
	Text::CSV::IV(), # airport id
	Text::CSV::PV(), # airport_ident
	Text::CSV::NV(), # length_ft
	Text::CSV::NV(), # width_ft
	Text::CSV::PV(), # surface
	Text::CSV::IV(), # lighted
	Text::CSV::IV(), # closed
	Text::CSV::PV(), # le_ident
	Text::CSV::NV(), # le_latitude_deg
	Text::CSV::NV(), # le_longitude_deg
	Text::CSV::NV(), # le_elevation_ft
	Text::CSV::NV(), # le_heading_deg
	Text::CSV::NV(), # le_displaced_threshold_ft
	Text::CSV::PV(), # he_ident
	Text::CSV::NV(), # he_latitude_deg
	Text::CSV::NV(), # he_longitude_deg
	Text::CSV::NV(), # he_elevation_ft
	Text::CSV::NV(), # he_heading_deg
	Text::CSV::NV(), # he_displaced_threshold_ft
	]);

my $freqCSV;
$freqCSV = Text::CSV->new({binary => 1})
or die Text::CSV->error_diag();
$freqCSV->types([
	Text::CSV::IV(), # id
	Text::CSV::IV(), # airport id
	Text::CSV::PV(), # airport_ident
	Text::CSV::PV(), # type
	Text::CSV::PV(), # description
	Text::CSV::NV(), # frequency_mhz
	]);

my $navaidCSV;
$navaidCSV = Text::CSV->new({binary => 1})
or die Text::CSV->error_diag();
$navaidCSV->types([
	Text::CSV::IV(), # id
	Text::CSV::PV(), # filename
	Text::CSV::PV(), # ident
	Text::CSV::PV(), # name
	Text::CSV::PV(), # type
	Text::CSV::NV(), # frequency_khz
	Text::CSV::NV(), # latitude_deg
	Text::CSV::NV(), # longitude_deg
	Text::CSV::NV(), # elevation_ft
	Text::CSV::PV(), # iso_country
	Text::CSV::NV(), # dme_frequency_khz
	Text::CSV::PV(), # dme_channel
	Text::CSV::NV(), # dme_latitude_deg
	Text::CSV::NV(), # dme_longitude_deg
	Text::CSV::NV(), # dme_elevation_Ft
	Text::CSV::NV(), # slaved_variation_deg
	Text::CSV::NV(), # magnetic_variation_deg
	Text::CSV::PV(), # usageType
	Text::CSV::PV(), # power
	Text::CSV::PV(), # associationed_airport
	]);

startDatasource(Datasources::DATASOURCE_WO_OA);

# I want to know all the states
my $statefh = new IO::File(">states");
# I want to know if we have any dups
my $dupfh = new IO::File(">dups");
my %done = ();

# First line is header
<$airportFH>;
<$runwaysFH>;
<$freqFH>;
<$navaidFH>;

my @lastRunwaysRec;
my @lastFreqRec;

sub parseRunways($$)
{
  my ($airport_pk, $waypointRef) = @_;

  while (!@lastRunwaysRec || $lastRunwaysRec[1] < $airport_pk)
  {
print "skipping runway record $lastRunwaysRec[0] \n";
	my $runwaysRec = <$runwaysFH>;
	chomp $runwaysRec;
	$runwaysCSV->parse($runwaysRec)
	or die $runwaysCSV->error_diag();
	@lastRunwaysRec = $runwaysCSV->fields();
  }

  my @runways;

  while ($lastRunwaysRec[1] == $airport_pk)
  {
	my ($id, $a_pk, $airport_ident, $length, $width,
		$surface, $lighted, $closed,
		$le_ident, $le_lat, $le_long, $le_elev, $le_head, $le_displaced,
		$he_ident, $he_lat, $he_long, $he_elev, $he_head, $he_displaced)
		= @lastRunwaysRec;
		
print "processing runway $id \n";
  	my $runwaysRec = <$runwaysFH>;
	chomp $runwaysRec;
	$runwaysCSV->parse($runwaysRec)
	or die $runwaysCSV->error_diag();
	@lastRunwaysRec = $runwaysCSV->fields();
  }
}

sub parseCommFreqs($$)
{
  my ($airport_pk, $waypointRef) = @_;
}



while (<$airportFH>)
{
	chomp;
	$airportCSV->parse($_)
	or die $airportCSV->error_diag ();
	my @record = $airportCSV->fields();

	my ($airport_primary_key, $ident, $type, $name, 
		$latitude, $longitude,
		$elevation, $continent,
		$country, $region,
		$municipality, $hasScheduledService,
		$gps_code, $iata_code, $local_code, $home_link,
		$wikipedia_link, $keywords) = @record;
print "ident = $ident, gps_code = $gps_code, iata = $iata_code, local = $local_code\n";
	if ($country eq "CA" or $country eq "US")
	{
	  print "skipping Canada or US\n";
	  next;
	}
	my $id;
	my $isGoodID = 0; # True for ICAO-style ids only
	if ($ident =~ /^[A-Z]{4}$/)
	{
	  # 4 alpha characters, looks like an ICAO id
	  $id = $ident;
	  $isGoodID = 1;
	}
	elsif ($gps_code =~ /^[A-Z][A-Z0-9]{3}$/)
	{
	  # 4 alphanumeric characters, looks like a semi-unique airport code
	  $id = $gps_code;
	  $isGoodID = 1;
	}
	elsif ($iata_code =~ /^[A-Z][A-Z0-9]{3}$/)
	{
	  # Once or twice the semi-unique GPS code appears here instead.
	  $id = $iata_code;
	  $isGoodID = 1;
	}
	elsif ($gps_code =~ /^[A-Z0-9]{3}$/)
	{
	  # 3 characters, probably not unqiue.
	  $id = $gps_code;
	}
	elsif ($local_code =~ /^[A-Z0-9]{4}$/)
	{
	  # 4 characters, probably unqiue.
	  $id = $local_code;
	  $isGoodID = 1;
	}
	elsif ($local_code ne "")
	{
	  $id = $local_code;
	}
	else
	{
	  # Probably one of the sucky ids that were invented by whoever loaded
	  # them to ourairports.com.
	  $id = $ident;
	}

	# OurAirports is inconsistent about putting a K at the beginning of US
	# IDs whether or not they're supposed to have them.
	# (Consider removing this and fixing OurAirports instead)
	if ($country eq "US" and $region ne "AK" and $region ne "HI")
	{
	  print $statefh "region: $region\n";
	  if ($id =~ /^K[A-Z0-9]{3}$/ && $id =~ /[0-9]/)
	  {
		# If it has a 4 character id starting with K, and with a number in
		# it, then remove the initial K.
		$id =~ s/^K//;
	  }
	  elsif ($id =~ /^[A-Z]{3}$/)
	  {
		# If it's a three alphabetic characters only, then put a K at the
		# beginning
		$id = "K" . $id;
	  }
	}

	if (defined($done{$id}))
	{
	  print $dupfh "id $id is a dup\n";
	}
	$done{$id} = 1;

	#print "getting mag var for $id ($latitude, $longitude, $elevation)\n";
	my $decl = getMagVar($latitude, $longitude, $elevation);
	#print "got $decl\n";

	if ($type eq "closed")
	{
	  closeWaypoint($id, "AIRPORT", $latitude, $longitude);
	  next;
	}

	#if ($type eq "")
	#{
	  # There are a couple of airports in Iran that Dave doesn't seem sure
	  # about.
	#  $type = "AIRPORT";
	#}
	elsif (!defined($typeMap{$type}))
	{
	  die "unknown type $type in id $id\n";
	}
	$type = $typeMap{$type};

	my $fcountry;
	# "UM" (Federated States of Micronesia) is a bitch, because DAFIF
	# treated them like separate countries.
	if ($country eq "UM")
	{
	  if ($id eq "PWAK" or $id eq "PMDY")
	  {
		$fcountry = "WQ";
	  }
	  elsif ($id eq "PJON")
	  {
		$fcountry = "JQ";
	  }
	  elsif ($id eq "PLPA")
	  {
		$fcountry = "LQ";
	  }
	}
	else
	{
	  $fcountry = translateCountryCode($country);
	}
	if (!defined($fcountry))
	{
	  die "invalid country code $country for $id\n";
	}

	#utf8::upgrade($name);

	my %waypoint;
	$waypoint{id} = $id;
	$waypoint{type} = $type;
	$waypoint{name} = $name;
	if ($country eq "US" or $country eq "CA")
	{
	  $waypoint{state} = $region;
	}
	$waypoint{country} = $fcountry;
	$waypoint{latitude} = $latitude;
	$waypoint{longitude} = $longitude;
	if (defined($decl))
	{
	  $decl += 0;
	}
	$waypoint{declination} = $decl;
	if (defined($elevation))
	{
	  $elevation += 0;
	}
	if ($elevation != 0)
	{
	  $waypoint{elevation} = $elevation;
	}
	#$waypoint{ispublic} = 1;
	$waypoint{orig_datasource} = Datasources::DATASOURCE_WO_OA;
	
	parseRunways($airport_primary_key, \%waypoint);
	parseCommFreqs($airport_primary_key, \%waypoint);

	insertWaypoint(\%waypoint);
}

close($airportFH);
close($runwaysFH);
close($freqFH);

exit;

print "ending datasource\n";
endDatasource(Datasources::DATASOURCE_WO_OA);

print "postload\n";
postLoad();

print "dbclose\n";
dbClose();
print "Done\n";

