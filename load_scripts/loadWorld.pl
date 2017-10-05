#!/usr/bin/perl -w

use DBI;
use IO::File;

use strict;

#$| = 1; # for debugging

use Datasources;
use WaypointTypes;
use WPInfo;

use DBLoad;
DBLoad::initialize();

deleteWaypointData(Datasources::DATASOURCE_WO_DR,1);

# Convert one of the FAA's latitudes and longitudes in seconds fields.
sub parseLatLong($)
{
  my $wgsLL = shift;
  my ($nsew, $deg, $min, $sec, $dec) = ($wgsLL =~
	  m/([NSEW])([0-9]{2,3})([0-9]{2})([0-9]{2})([0-9]{2})/);

  my $latLong = $deg + ($min / 60.0) + ($sec / 3600.0) +
	  ($dec / 360000.0);
  if ($nsew eq "S" or $nsew eq "E")
  {
	$latLong *= -1.0;
  }
  return $latLong;
}

my %countries;
my $conn = getDBConnection();
my $getCountriesStmt = $conn->prepare(
	"SELECT			code, country_name ".
	"FROM			dafif_country_codes ")
or die $conn->errstr;

$getCountriesStmt->execute();
my @row;
while (@row = $getCountriesStmt->fetchrow_array)
{
  my $name = uc($row[1]);
  $name =~ s/, THE//;
  my $code = $row[0];
  $countries{"$name"} = $code;
print "storing: name = $name, code = $code\n";
}

# Some of these are invalid countries, some because the guy who typed them
# seems to now be speaking English.
my %countryExceptions =
(
  "ASCENCION ISLAND" => "SH",
  "BURKINA FASSO" => "UV",
  "CANARIES ISLANDS" => "SP",
  "GUINEA BISSEAU" => "PU",
  "IVORY COAST" => "IV",
  "MAMAWI" => "MI",
  "NAMIMBIA" => "WA",
  "SAL ISLAND" => "CV",
  "SAO TOME" => "TP",
  "TANZANIA" => "TZ",
  "TONGO" => "TO",
  "AZERBIJAN" => "AJ",
  "BHAHREIN" => "BA",
  "KABODIA" => "CB",
  "KAZAKSTAN" => "KZ",
  "KOREA" => "KS",
  "KOREA NORTH" => "KN",
  "KUWEIT" => "KU",
  "MALAISIA" => "MY",
  "MYANMAR (BURMA)" => "BM",
  "SHRI LANKA" => "CE",
  "SOLOMON ISLANDS" => "BP",
  "TADJIKISTAN" => "TI",
  "EASTER ISLAND" => "CI",
  "MARIANNA ISLANDS (US)" => "CQ",
  "MICRONESIA" => "FM",
  "MIDWAY ISLAND (US)" => "MQ",
  "PAGO PAGO ISLAND" => "AQ",
  "WAKE ISLAND (US)" => "WQ",
  "AZORES ISLANDS" => "PO",
  "BOSNIA" => "BK",
  "FYROM" => "MK",
  "HERZEGOVINA" => "HR",
  "HOLLAND" => "NL",
  "ISLAND" => "IC",
  "SERVIA" => "RB",
  "SWITCHERLAND" => "SZ",
  "ANTIGUA" => "AC",
  "NETHERLAND ANTILLES" => "NT",
  "SAINT VINCENT AND THE GRENADINES" => "VC",
  "SAN SALVADOR" => "ES",
  "TRINIDAD & TOBAGO" => "TD",
  "VIRGIN ISLANDS (UK)" => "VI",
  "VIRGIN ISLANDS (US)" => "VQ",
  "EQUADOR" => "EC",
  "DIEGO GARCIA" => "IO",
  "PULAU" => "PS",
);

sub lookupCountry($)
{
  my $name = shift;

  $name = uc($name);
print "lookup name = $name, ";
  if (exists($countries{$name}))
  {
print "database code = ", $countries{$name}, "\n";
	return $countries{$name};
  }
  my $truncName = $name;
  $truncName =~ s/ ISLANDS?//;
  $truncName =~ s/SAINT/ST./;
  $truncName =~ s/SANTA/ST./;
  if (exists($countries{$truncName}))
  {
print "truncated database code = ", $countries{$truncName}, "\n";
	return $countries{$truncName};
  }
  if (exists($countryExceptions{$name}))
  {
print "database code = ", $countryExceptions{$name}, "\n";
	return $countryExceptions{$name};
  }
print "code not found\n";
  return undef;
}

my $fn = shift;
my $fh = new IO::File($fn) or die "Airport file $fn not found\n";

#$/ = "\r";

while (<$fh>)
 {
   last if /^CONTINENT/;
 }

my $countryCode = "";
my $lastID = "";

while (<$fh>)
{
  chomp;
  next if (/^\s*$/);

  my ($continent, $country, $intlCountryCode, $city, $fir, $icao, $iata, 
  		$name, $wgsLat, $wgsLon, $wgsVar, $elev, $numRwys, $longestRwy,
		$runways, $precisionAppr, $fuelTypes, $timeDiff, $spare) = 
			split("\t");
  next if ($icao eq "");

  # The data for US sucks.
  next if ($country eq "United States");

  if ($icao !~ m/^[A-Z]{4}$/ &&
	  $country ne "Canada")
  {
	print "skipping invalid icao = $icao\n";
	next;
  }

  if ($icao eq $lastID)
  {
	print "skipping duplicate icao = $icao\n";
	next;
  }
  $lastID = $icao;

  my $lat = parseLatLong($wgsLat);
  my $lon = parseLatLong($wgsLon);

  my ($nsew, $decl) = ($wgsVar =~ m/([NSEW])0*([0-9\.]*)/);
  if ($nsew eq "E")
  {
	$decl *= -1.0;
  }

  # Fucking Microsoft's fucking pathetic excuse for "tab delimited".
  $name =~ s/^"(.*)"$/$1/;
  $city =~ s/^"(.*)"$/$1/;


print "[$country, $icao ($lat, $lon) decl = $decl, elev = $elev]\n";
  $countryCode = lookupCountry($country);
  last if (!defined($countryCode));

  # The data confuses Congo and Zaire
  if ($countryCode eq "CF" && $icao =~ m/^FZ/)
  {
	$countryCode = "CG";
  }
  # Also, St. Pierre and Miquelon should have a separate country code
  if ($countryCode eq "FR" && $lon > 40.0)
  {
	$countryCode = "SB";
  }
  # Kazakhstan and Kyrgyzstan are NOT the same country
  if ($countryCode eq "KZ" && $intlCountryCode eq "KGZ")
  {
	$countryCode = "KG";
  }
  # Faroe Islands
  if ($countryCode eq "DA" && $intlCountryCode eq "FRO")
  {
	$countryCode = "FO";
  }
  # Western Sahara
  if ($countryCode eq "MO" && $intlCountryCode eq "XJU")
  {
	$countryCode = "WI";
  }

  my $type = 'AIRPORT';
  my $datasource_key = generateDSKey($icao, "WO_DR", $type, undef,
  	$countryCode, $lat, $lon);
  insertWaypoint($icao, $datasource_key, $type, $name, $city,
  	undef, $countryCode, $lat, $lon, $decl, $elev, undef,
	Datasources::DATASOURCE_WO_DR, 1, 0, undef);
}


updateDatasourceExtents(Datasources::DATASOURCE_WO_DR,1);

print "Done loading\n";

post_load();

finish();
