#!/usr/bin/perl -w

# FAA Format as of 25Oct2007
#

use warnings FATAL => 'all';

use DBI;
use IO::File;
use Data::Dumper;

use POSIX qw(floor);

use strict;

binmode STDOUT, ":utf8";

$| = 1; # for debugging

use Datasources;
use WaypointTypes;
use WPInfo;

use PostGIS;

my $faadir = shift;
my $dbName = "navaid";
if ($faadir eq "-d")
 {
  $dbName = shift;
  $faadir = shift;
}
print "loading $faadir into $dbName\n";

PostGIS::initialize($dbName);

# Store partial waypoints until it's time to store them.
my %waypoints;

sub updateChartMap($$)
{
  my ($faa_key, $chart) = @_;
  if (!defined($waypoints{$faa_key}))
  {
	$waypoints{$faa_key} = {};
  }
  my $ref = $waypoints{$faa_key};
  if (!defined($ref->{chart_map}) || $ref->{chart_map} eq "")
  {
	  $ref->{chart_map} = 0;
  }
  $ref->{chart_map} |= $chart;
}

sub storeWaypoint($$$$$$$$$$$$$$$$$$)
{
  my ($id, $faa_key, $type, $name, $city, $state, $country,
  		$latitude, $longitude, $declination, $elevation, $isDeleted,
		$main_frequency, $isPublic, $tpa, $chart_map, $fuel, $faa_id) = @_;
#print "storing id = $id, type = $type\n";
  if (!defined($waypoints{$faa_key}))
  {
	$waypoints{$faa_key} = {};
  }
  utf8::upgrade($name);
  my $ref = $waypoints{$faa_key};
  $ref->{id} = $id;
  $ref->{type} = $type;
  $ref->{name} = $name;
  $ref->{address} = $city;
  $ref->{state} = $state;
  $ref->{country} = $country;
  $ref->{latitude} = $latitude;
  $ref->{longitude} = $longitude;
  if (defined($declination))
  {
	$declination += 0;
  }
  $ref->{declination} = $declination;
  if (defined($elevation))
  {
	$elevation += 0;
  }
  $ref->{elevation} = $elevation;
  $ref->{main_frequency} = $main_frequency;
  $ref->{ispublic} = $isPublic;
  $ref->{tpa} = $tpa;
  $ref->{chart_map} = $chart_map;
  $ref->{orig_datasource} = Datasources::DATASOURCE_FAA;
  if (defined($fuel) && $fuel ne "")
  {
	$ref->{hasfuel} = 1;
  }
  $ref->{faa_id} = $faa_id;

  if ($isDeleted)
  {
	$ref->{deletedon} = localtime;
  }
  else
  {
	$ref->{deletedon} = undef;
  }
  $ref->{trust_deleted} = 1;
}

sub storeRunway($$$$$$$$$$$$$)
{
  my ($faa_key, $designation, $length, $width, $surface,
	$b_lat, $b_long, $b_heading, $b_elev, 
	$e_lat, $e_long, $e_heading, $e_elev) = @_;

  if (!defined($waypoints{$faa_key}))
  {
	$waypoints{$faa_key} = {};
  }
  my $ref = $waypoints{$faa_key};
  if (!defined($ref->{runways}))
  {
	$ref->{runways} = [];
  }
  my $rwyRef = $ref->{runways};
  my %record;
  $record{designation} = $designation;
  if (defined($length))
  {
	$length += 0;
  }
  $record{length} = $length;
  if (defined($width))
  {
	$width += 0;
  }
  $record{width} = $width;
  $record{surface} = $surface;
  $record{b_lat} = $b_lat;
  $record{b_long} = $b_long;
  if (defined($b_heading))
  {
	$b_heading += 0;
  }
  $record{b_heading} = $b_heading;
  if (defined($b_elev))
  {
	$b_elev += 0;
  }
  $record{b_elev} = $b_elev;
  $record{e_lat} = $e_lat;
  $record{e_long} = $e_long;
  if (defined($e_heading))
  {
	$e_heading += 0;
  }
  $record{e_heading} = $e_heading;
  if (defined($e_elev))
  {
	$e_elev += 0;
  }
  $record{e_elev} = $e_elev;
  push @$rwyRef, \%record;
}

sub storeCommunication($$$$)
{
  my ($faa_key, $type, $name, $frequency) = @_;

  if (!defined($waypoints{$faa_key}))
  {
	$waypoints{$faa_key} = {};
  }
  my $ref = $waypoints{$faa_key};
  if (!defined($ref->{frequencies}))
  {
	$ref->{frequencies} = [];
  }
  my $commRef = $ref->{frequencies};
  my %record;
  $record{type} = $type;
  $record{name} = $name;
  $record{frequency} = fixFrequency($frequency);
  push @$commRef, \%record;
}

sub storeFix($$$$$)
{
  my ($faa_key, $navaid, $navaid_type, $radial_bearing, $distance) = @_;
  if (!defined($waypoints{$faa_key}))
  {
	$waypoints{$faa_key} = {};
  }
  my $ref = $waypoints{$faa_key};
  if (!defined($ref->{fixinfo}))
  {
	$ref->{fixinfo} = [];
  }
  my $fixRef = $ref->{fixinfo};
  my %record;
  $record{navaid} = $navaid;
  $record{navaid_type} = $navaid_type;
  if (defined($radial_bearing))
  {
	$radial_bearing = int($radial_bearing + 0.5);
  }
  $record{radial_bearing} = $radial_bearing;
  if (defined($distance))
  {
	$distance = int($distance + 0.5);
  }
  $record{distance} = $distance;
  push @$fixRef, \%record;
}

sub storeAllWaypoints($$)
{
  my $str = shift;
  my $flushNoChartMaps = shift;

print "$str starting\n";
  foreach my $ref (values(%waypoints))
  {
	if (!defined($ref->{id}))
	{
#print "ERROR no id data: ", Dumper($ref), "\n";
	  next;
	}
	if (!$flushNoChartMaps ||
		(defined($ref->{chart_map}) && $ref->{chart_map} ne "" &&
				 $ref->{chart_map} > 0))
	{
		insertWaypoint($ref);
	}
	else
	{
		print "WARNING: Skipping ", $ref->{id},
			  " because it isn't in any charts\n";
	}
  }
  %waypoints = ();
print "$str done\n";
}

my %FAA_chart_codes =
  ("AREA"                   =>  WaypointTypes::WPTYPE_RNAV,
   "CONTROLLER"             =>  0,
   "CONTROLLER ONLY"        =>  0,
   "CONTROLLER CHART ONLY"  =>  0,
   "ENROUTE HIGH"           =>  WaypointTypes::WPTYPE_HIGH_ENROUTE,
   "ENROUTE LOW"            =>  WaypointTypes::WPTYPE_LOW_ENROUTE,
   "HELICOPTER ROUTE"       =>  WaypointTypes::WPTYPE_VFR,
   "IAP"                    =>  WaypointTypes::WPTYPE_APPROACH,
   "IFR GOM VERTICAL FLT"   =>  WaypointTypes::WPTYPE_LOW_ENROUTE,
   "MILITARY IAP"           =>  WaypointTypes::WPTYPE_APPROACH,
   "MILITARY SID"           =>  WaypointTypes::WPTYPE_APPROACH,
   "MILITARY STAR"          =>  WaypointTypes::WPTYPE_APPROACH,
   "NOT REQUIRED"           =>  0,
   "PRIVATE IAP"            =>  WaypointTypes::WPTYPE_APPROACH,
   "PROFILE DESCENT"        =>  WaypointTypes::WPTYPE_APPROACH,
   "RNAV HIGH"              =>  WaypointTypes::WPTYPE_RNAV,
   "RNAV LOW"               =>  WaypointTypes::WPTYPE_RNAV,
   "SECTIONAL"              =>  WaypointTypes::WPTYPE_VFR,
   "SID"                    =>  WaypointTypes::WPTYPE_APPROACH,
   "SPECIAL IAP"            =>  WaypointTypes::WPTYPE_APPROACH,
   "STAR"                   =>  WaypointTypes::WPTYPE_APPROACH,
   "VFR FLYWAY PLANNING"    =>  WaypointTypes::WPTYPE_VFR,
   "VFR TERMINAL AREA"      =>  WaypointTypes::WPTYPE_VFR);

my %FAA_fix_navaids = (
    "C"                     =>  "VORTAC",
    "T"                     =>  "TACAN",
    "D"                     =>  "VOR/DME",
    "F"                     =>  "FAN MARKER",
    "K"                     =>  "CONSOLAN",
    "L"                     =>  "LOW FREQ. RANGE",
    "M"                     =>  "MARINE NDB",
    "MD"                    =>  "MARINE NDB/DME",
    "O"                     =>  "VOT",
    "R"                     =>  "NDB",
    "RD"                    =>  "NDB/DME",
    "U"                     =>  "UHF/NDB",
    "V"                     =>  "VOR",
    "DD"                    =>  "LDA/DME",
    "LA"                    =>  "LDA",
    "LC"                    =>  "LOCALIZER",
    "LD"                    =>  "ILS/DME",
    "LE"                    =>  "LOC/DME",
    "LG"                    =>  "LOC/GS",
    "LS"                    =>  "ILS",
    "ML"                    =>  "MLS",
    "SD"                    =>  "SDF/DME",
    "SF"                    =>  "SDF",
    "LO"                    =>  "LOM",
    "LM"                    =>  "LMM"
    );

# States that should not be converted to "K"-type ICAOs, but are otherwise
# normal.
my @stupidStates = ("HI","AK","OG","OP","OA");

# States that should be converted to other states
my %difficultStates = (
		"IQ"	=>	"OP"
);

# States that should be converted to countries
my %insaneStates = (
		"CZ"	=>	"PM",
		"AS"	=>	"AQ",
		"CQ"	=>	"CQ",
		"GU"	=>	"GQ",
		"MQ"	=>	"MQ",
		"PR"	=>	"RQ",
		"VI"	=>	"VQ",
		"WQ"	=>	"WQ",
        "MH"    =>  "RM",
        "PS"    =>  "PS",
        "FM"    =>  "FM",
        "TQ"    =>  "JQ",
		"AI"	=>	"AV",
		"AN"	=>	"NT",
		"BS"	=>	"BF",
		"PW"	=>	"PS",
		"BM"	=>	"BD",
		"GL"	=>	"GL",
		"IO"	=>	"IO",
		"MF"	=>	"NF",
		"SH"	=>	"SH",
		"TC"	=>	"TK",
		"VG"	=>	"VI",
		);

# Long names that convert to states
my %faaStates = (
		"OFFSHORE ATLANTIC"		=>	"OA",
		"OFFSHORE GULF"			=>	"OG",
		"OFFSHORE PACIFIC"		=>	"OP",
		"OFFSHORE CARIB"		=>	"OC",
		"PACIFIC OCEAN"			=>	"OP",
		"DIST. OF COLUMBIA"		=>	"DC"
);
# Long names that convert to countries
my %faaCountries = (
		"AMA"						=>	"PM", # Truncated "PANAMA"
		"AMERICAN SAMOA"			=>	"AQ",
		"ANTIGUA AND BARBUDA"		=>	"AC",
		"BAHAMAS"					=>	"BF",
		"BAHAMA ISLANDS"			=>	"BF",
		"BARBADOS"					=>	"BB",
		"BELIZE"					=>	"BH",
		"BERMUDA"					=>	"BD",
		"BRITISH WEST INDIES"		=>	"TK",
		"CANADA"					=>	"CA",
		"CAYMAN ISLANDS"			=>	"CJ",
		"COLOMBIA"					=>	"CO",
		"COSTA RICA"				=>	"CS",
		"CUBA"						=>	"CU",
		"DOMINICA"					=>	"DO",
		"DOMINICAN REPUBLIC"		=>	"DR",
		"DURAS"						=>	"HO", # Truncated "HONDURAS"
		"ECUADOR"					=>	"EC",
		"EL SALVADOR"				=>	"ES",
		"FED STS MICRONESIA"		=>	"FM",
		"MICRONESIA, FED STAT"		=>	"FM",
		"MICRONESIA, FED STATES OF"	=>	"FM",
		"FRENCH WEST INDIES"		=>	"GP", # Maybe should be Martinique
		"GRENADA"					=>	"GJ",
		"GUAM"						=>	"GQ",
		"GUYANA"					=>	"GY",
		"HAITI"						=>	"HA",
		"HONDURAS"					=>	"HO",
		"ICO"						=>	"MX", # Truncated "MEXICO"
		"JAMAICA"					=>	"JM",
		"MARSHALL ISLANDS"			=>	"RM",
		"MEXICO"					=>	"MX",
		"MIDWAY ATOLL"				=>	"MQ",
		"NETHERLANDS ANTILLES"		=>	"NT",
		"NICARAGUA"					=>	"NU",
		"NOTHERN MARIANA ISLA"		=>	"CQ", # Note the FAA spelling
		"NORTHERN MARIANA ISL"		=>	"CQ", # In case they fix the spelling
		"N MARIANA ISLANDS"			=>	"CQ", # They took the easy way out.
		"NORTHERN MARIANA ISLANDS"	=>	"CQ", # And now the field is longer
		"PALAU"						=>	"PS",
		"PANAMA"					=>	"PM",
		"PERU"						=>	"PE",
		"PUERTO RICO"				=>	"RQ",
		"SAINT KITTS AND NEVI"		=>	"SC",
		"TRINIDAD AND TOBAGO"		=>	"TD",
		"TRUST TERRITORIES"			=>	"JQ", # Lump them all together
		"TURKS AND CAICOS ISL"		=>	"TK",
		"VENEZUELA"					=>	"VE",
		"VIRGIN ISLANDS"			=>	"VQ",
		"SAINT LUCIA"				=>	"ST",
		"MARTINIQUE"				=>	"MB",
		"ST. VINCENT AND THE"		=>	"VC",
		"GUADELOUPE"				=>	"GP",
		"ARUBA"						=>	"AA",
		"WAKE ISLAND"				=>	"WQ",
		"TURKS AND CAICOS ISLANDS"	=>	"TK",
		"ST. VINCENT AND THE GRENADINES"
									=>	"VC",
		"SAINT KITTS AND NEVIS"		=>	"SC",
		"RUSSIAN FEDERATION"		=>	"RS",
		);

sub faaToICAOCountry($)
{
	my $country = shift;

	if ($country eq "")
	{
		return "US";
	}

	if (exists($faaCountries{$country}))
	{
		$country = $faaCountries{$country};
	}
	else
	{
	  die "no mapping for country $country\n";
	}

	return $country;
}

sub normalizeID($$$$$)
{
    my ($id, $state, $country, $icaoID, $isAirport) = @_;
	my $idDone = 0;

	if (defined($icaoID) && $icaoID ne "")
	{
	  if ($icaoID =~ m/K[A-Z]*[0-9]/)
	  {
		# I don't know the FAA is thinking, but they need to put down the
		# crack pipe and open the window
		;
	  }
	  else
	  {
		$id = $icaoID;
		$idDone = 1;
	  }
	}

	if (grep(/^$state$/, @stupidStates))
	{
		# Stupid state, don't do anything
		$idDone = 1;
	}
	elsif (exists($difficultStates{$state}))
	{
print "found a difficult state $state\n";
		# Difficult state, translate it.
		$state = $difficultStates{$state};
		$country = "US";
		$idDone = 1;
	}
	elsif (exists($insaneStates{$state}))
	{
print "found a insane state $state\n";
		$country = $insaneStates{$state};
		$state = '';
		$idDone = 1;
	}

	if (!$idDone)
	{
	  if ($isAirport && length($id) < 4 && !($id =~ /[0-9]/))
	  {
		  $id = "K" . $id;
	  }
	  elsif ($isAirport && length($id) == 4 && ($id =~ /^K.*[0-9]/))
	  {
		  # What the fuck is the DAFIF thinking?
		  $id =~ s/^K//;
	  }
	}
	return ($id, $state, $country);
}

# Convert one of the FAA's latitudes and longitudes in seconds fields.
sub parseSeconds($)
{
  my $seconds = shift;
  my $latlong = substr($seconds, 0, 10) / 3600.00;
  my $letter = substr($seconds, -1);
  if ($letter eq "S" || $letter eq "W")
  {
	$latlong = -$latlong;
  }
  return $latlong;
}

sub fixCommNameAndFreq($$)
{
	my ($type, $freq) = @_;

	$type =~ s@/[PS]@@g;
	$type =~ s/\(.*\)//g;
	$type =~ s/^\s+//g;

	if ($type =~ m/APCH DEP/ ||
		$type =~ m/\bCLASS\b/ ||
	    $type =~ m/\bSTAGE\b/ || $type =~ m/\bIC\b/)
	{
		$type = "A/D";
	}
	elsif ($type =~ m/\bAPCH\b/)
	{
		$type = "APP";
	}
	elsif ($type =~ m/\bDEP/)
	{
		$type = "DEP";
	}
	elsif ($type =~ m/RAMP/)
	{
		$type = "RMP";
	}
	elsif ($type =~ m/GND/)
	{
		$type = "GND";
	}
	elsif ($type =~ m/TRML/ || $type =~ m/HOLD/)
	{
		$type = "GTE";
	}
	elsif ($type =~ m/CLNC.DEL/ || $type =~ m/CD/ || $type =~ m/PRE TAXI/)
	{
		$type = "CLD";
	}
	elsif ($type =~ m/TFC /)
	{
		$type = "CTAF";
	}
	elsif ($type =~ m/BOEING/)
	{
		$type = "UNIC";
	}
	elsif ($type =~ m/LCL/ || $type =~ m/TWR/)
	{
		$type = "TWR";
	}
	elsif ($type =~ m/MIL / || $type =~ m/\bADV/)
	{
		$type = "A/G";
	}
	elsif ($type =~ m/ADZY/ || $type =~ m/^AAS/)
	{
		$type = "AAS";
	}
	elsif ($type =~ m/RDR/ || $type =~ m/RADAR/ || $type =~ m/^FINAL/ ||
		   $type =~ m/\bASR\b/ || $type =~ m/\bPAR\b/ || $type =~ m/^GCA/)
	{
		$type = "GCA";
	}
	elsif ($type =~ m/POST/ || $type =~ m/ALCP/ || $type =~ m/\bCP\b/ ||
		   $type =~ m/RAYMOND/ || $type =~ m/\bTAC\b/)
	{
		$type = "POST";
	}
	elsif ($type =~ m/\bEMER/ || $type =~ m/RESCUE/ || $type =~ m/EVAC/)
	{
		$type = "EMR";
	}
	elsif ($type =~ m/^RANG/ || $type =~ m/COMD/ || $type =~ m/OPS/ ||
		   $type =~ m/OPNS/  || $type =~ m/ANG\s*/ || $type =~ m/ARMY/ ||
		   $type =~ m/\bRNG\b/ || $type =~ m/BASE/ ||
		   $type =~ m/\bPRARNG\b/ || $type =~ m/\bFM\b/ || $type =~ m/HEL/)
	{
		$type = "OPS";
	}
	elsif ($type =~ m/AMC / || $type =~ m/AMCC/ || $type =~ m/USAF/ ||
		   $type =~ m/^PTD/)
	{
		$type = "PTD";
	}
	elsif ($type =~ m/ATIS/ || $type =~ m/ATIA/ || $type =~ /RTIS/)
	{
		$type = "ATIS";
	}
	elsif ($type =~ m/FSS/ || $type =~ m/RDO/ || $type =~ m/\bFS\b/)
	{
		$type = "FSS";
	}
	elsif ($freq =~ m/PMSV/ || $type =~ m/PMSV/ || $type =~ m/METRO/)
	{
		$type = "PMSV";
	}
	elsif ($type =~ m/ALCE/)
	{
		# I think there's only one of these!
		$type = "ACP";
	}
	elsif ($type =~ m/^ARR/)
	{
		$type = "ARR";
	}
	elsif ($type =~ m/^SFA/)
	{
		$type = "SFA";
	}
#	elsif ($type =~ m/AS ASSIGNED/ || $type =~ m/MAINT/ || $type =~ m/CTL/ ||
#		   $type =~ m/CONTROL/ || $type =~ m/NEST/ || $type =~ m/FCLP/ ||
#		   $type =~ m/FLIGHT/ || $type =~ m/FLT/ || $type =~ m/TEST/ ||
#		   $type =~ m/\bLC\b/ || $type =~ m/LSO/ || $type =~ m/RADIO/ ||
#		   $type =~ m/NARF/ || $type =~ m/RESERVED/ || $type =~ m/\bSOF\b/ ||
#		   $type =~ m/SSB/ || $type =~ m/TRNG/ || $type =~ m/SEASONAL/ ||
#		   $type =~ m/UTIL/)
	else
	{
		$type = "MISC";
	}
#	$type = substr($type,0,4);
#	$type =~ s/\s+$//;

	$freq =~ s/[A-Z]*//g;   # remove these if I increase the length of the
	$freq =~ s/\(.*\).*$//;   # frequency field
	$freq =~ s/\([^)]*$//;   # frequency field
	$freq =~ s/ .*$//;

	return ($type, $freq);
}

sub parseFAAAirportAirportRecord($)
{
	my ($line) = @_;

	my ($recordType, $datasource_key, $type, $id, $effDate, $faaRegion,
		$faaFieldOffice, $state, $stateName, $county, $countyState,
		$city, $name, $ownershipType, $facilityUse, $ownersName,
		$ownersAddress, $ownersCityStateZip, $ownersPhone, $facilitiesManager,
		$managersAddress, $managersCityStateZip, $managersPhone,
		$formattedLat, $secondsLat, $formattedLong, $secondsLong,
		$refDetermined, $elev, $elevDetermined, $magVar, $magVarEpoch, $tph,
		$sectional, $distFromTown, $dirFromTown, $acres,
        $bndryARTCC, $bndryARTCCid,
		$bndryARTCCname, $respARTCC, $respARTCCid, $respARTCCname,
		$fssOnAirport, $fssId, $fssName, $fssPhone, $fssTollFreePhone,
        $altFss, $altFssName,
		$altFssPhone, $notamFacility, $notamD, $arptActDate,
        $arptStatusCode, $arptCert,
		$naspAgreementCode, $arptAirspcAnalysed, $aoe, $custLandRights,
		$militaryJoint, $militaryRights, 
		$inspMeth, $inspAgency, $lastInsp, $lastInfo, $fuel, $airframeRepairs,
		$engineRepairs, $bottledOyxgen, $bulkOxygen,
		$lightingSchedule, $beaconLightingSched,
		$tower, $unicomFreq, $ctafFreq, $segmentedCircle,
		$lens, $landingFee, $isMedical,
		$numBasedSEL, $numBasedMEL, $numBasedJet,
		$numBasedHelo, $numBasedGliders, $numBasedMilitary,
        $numBasedUltraLight,
		$numScheduledOperation, $numCommuter, $numAirTaxi,
        $numGAlocal, $numGAItinerant,
		$numMil, $countEndingDate,
        $aptPosSrc, $aptPosSrcDate, $aptElevSrc, $aptElevSrcDate,
		$contractFuel, $transientStorage, $otherServices, $windIndicator,
		$icaoId) =
        unpack("A3 A11 A13 A4 A10 A3 A4 A2 A20 A21 A2 A40 " .
		"A50 A2 A2 A35 A72 A45 A16 A35 A72 A45 A16 A15 A12 A15 A12 A1 A7 A1 " .
		"A3 A4 A4 A30 A2 A3 A5 A4 A3 A30 A4 A3 A30 A1 A4 A30 A16 A16 " .
        "A4 A30 A16 A4 " .
		"A1 A7 A2 A15 A7 A13 A1 A1 A1 A1 A2 A1 A8 A8 A40 A5 A5 A8 " .
        "A8 A7 A7 A1 A7 A7 A4 A3 A1 A1 A3 A3 A3 A3 A3 A3 A3 " .
		"A6 A6 A6 A6 A6 A6 A10" .
		"A16 A10 A16 A10 A1 A12 A71 A3 A7", $line);
	
	my $country = "US";

	my $isPublic = ($facilityUse eq "PU") ? 1 : 0;

	my $lat = parseSeconds($secondsLat);

	my $long = parseSeconds($secondsLong);

    if ($state eq "")
    {
        $state = $countyState;
        if ($state eq "CN")
        {
            $country = "CA";
            $state = getProvince($lat, $long);
			if ($id =~ m/C[A-Z0-9]{3}/)
			{
			  ;
			}
			else
			{
			  $id = "C" . $id;
			}
        }
    }

	($id,$state,$country) = normalizeID($id,$state,$country,$icaoId, 1);

	# For some insane reason, the FAA has started giving fractional elevations
	if ($elev ne "")
	{
		$elev = POSIX::floor($elev + 0.5);
	}

    # Ignore the given declination, because it's often way out of date.
	#my $decl = 0;
	#if ($magVar ne "")
	#{
	#	my $ew = substr($magVar, -1);
	#	$decl = substr($magVar, 0, -1);
	#	if ($ew eq "E")
	#	{
	#		$decl = -$decl;
	#	}
	#}
	#
	#if ($decl == 0)
	#{
	#	$decl = getMagVar($lat, $long, $elev);
	#}
	my $decl = getMagVar($lat, $long, $elev);

	my $tpa = undef;
    if ($tph ne "")
    {
        $tpa = $tph + $elev;
    }
	my $isDeleted = $arptStatusCode ne "O" && $arptStatusCode ne "";

	storeWaypoint($id, $datasource_key, $type, $name, $city,
					$state, $country, $lat, $long, $decl, $elev,
					$isDeleted,
					$ctafFreq, $isPublic, $tpa, undef, $fuel,
					$datasource_key);

	if ($unicomFreq ne "")
	{
	  storeCommunication($datasource_key,
		  		"UNIC", "UNICOM", $unicomFreq);
	}

	return $datasource_key;
}

sub parseFAAAirportRunwayRecord($$)
{
	my ($currentKey, $line) = @_;

	my ($recordType, $datasource_key, $state, $rwyId, $rwyLen,
		$rwyWidth, $rwySurfaceType, $rwySurfaceTreat, $pcn, $rlei,
		$beId, $beTrueAlign, $beILSType, $beRightHandTraffic, $beRwyMarkings,
		$beRwyMarkingsCond, $beFormattedLat,
		$beSecondsLat, $beFormattedLong, $beSecondsLong, $beElev,
		$beThreshCrossingHeight, $beVisGlideAngle, $bedtFormattedLat,
		$bedtSecondsLat, $bedtFormattedLong, $bedtSecondsLong, $bedtElev,
		$bedtDist, $betzElev, $beVASI, $beRVR, $beRVV, $beApprLights,
		$beREIL, $beRCL, $beRETL, $beCOdesc, $beCOmarkedlighted, $beCOrwyCat,
		$beCOclncSlope, $beCOheight, $beCOdist, $beCOoffset, 
		$reId, $reTrueAlign, $reILSType, $reRightHandTraffic, $reRwyMarkings,
		$reRwyMarkingsCond, $reFormattedLat,
		$reSecondsLat, $reFormattedLong, $reSecondsLong, $reElev,
		$reThreshCrossingHeight, $reVisGlideAngle, $redtFormattedLat,
		$redtSecondsLat, $redtFormattedLong, $redtSecondsLong, $redtElev,
		$redtDist, $retzElev, $reVASI, $reRVR, $reRVV, $reApprLights,
		$reREIL, $reRCL, $reRETL, $reCOdesc, $reCOmarkedlighted, $reCOrwyCat,
		$reCOclncSlope, $reCOheight, $reCOdist, $reCOoffset,
		$rlenSrc, $rlenSrcDate,
		$bearSW, $bearDW, $bearDT, $bearDDT,
		$beREGrad, $beREGradDir,
		$beREPosSrc, $beREPosSrcDate, $beREElevSrc, $beREElevSrcDate,
		$bedtPosSrc, $bedtPosSrcDate, $bedtElevSrc, $bedtElevSrcDate,
		$betzElevSrc, $betzElevSrcDate,
		$beTORA, $beTODA, $beACLTStop, $beLDA, $beLAHSODist, $beIntID,
		$beHSPId,
		$beLAHSOFormattedLat, $beLAHSOSecondsLat,
		$beLAHSOFormattedLong, $beLAHSOSecondsLong,
		$beLAHSOLatLongSrc, $beLAHSOLatLongSrcDate,
		$reREGrad, $reREGradDir,
		$reREPosSrc, $reREPosSrcDate, $reREElevSrc, $reREElevSrcDate,
		$redtPosSrc, $redtPosSrcDate, $redtElevSrc, $redtElevSrcDate,
		$retzElevSrc, $retzElevSrcDate,
		$reTORA, $reTODA, $reACLTStop, $reLDA, $reLAHSODist, $reIntID,
		$reHSPId,
		$reLAHSOFormattedLat, $reLAHSOSecondsLat,
		$reLAHSOFormattedLong, $reLAHSOSecondsLong,
		$reLAHSOLatLongSrc, $reLAHSOLatLongSrcDate) =
		unpack("A3 A11 A2 A7 A5 A4 A12 A5 A11 A5 " .
		"A3 A3 A10 A1 A5 A1 A15 A12 A15 A12 A7 A3 A4 A15 A12 A15 A12 A7" .
		"A4 A7 A5 A3 A1 A8 A1 A1 A1 A11 A4 A5 A2 A5 A5 A7" . 
		"A3 A3 A10 A1 A5 A1 A15 A12 A15 A12 A7 A3 A4 A15 A12 A15 A12 A7" .
		"A4 A7 A5 A3 A1 A8 A1 A1 A1 A11 A4 A5 A2 A5 A5 A7" . 
		"A16 A10 " .
		"A6 A6 A6 A6 " .
		"A5 A4 A16 A10 A16 A10 A16 A10 A16 A10 A16 A10 " .
		"A5 A5 A5 A5 A5 A5 A7 A40 A15 A12 A15 A12 A16 A10 ".
		"A5 A4 A16 A10 A16 A10 A16 A10 A16 A10 A16 A10 ".
		"A5 A5 A5 A5 A5 A7 A40 A15 A12 A15 A12 A16 A10", $line);

	die "Record corruption\n" if ($currentKey ne $datasource_key);

	$rwySurfaceType =~ s/ //g;
	$rwySurfaceType = uc($rwySurfaceType);

	if ($rwyLen == 0 && $rwyWidth == 0 && $rwySurfaceType eq "")
	{
		print "skipping 0 length runway, id = $rwyId\n";
		return;
	}

	my $b_lat = undef;
	my $b_long = undef;
	my $e_lat = undef;
	my $e_long = undef;
	my $beSLat = ($beSecondsLat ? $beSecondsLat : 
				($bedtSecondsLat ? $bedtSecondsLat : undef));
	my $beSLong = ($beSecondsLong ? $beSecondsLong : 
				($bedtSecondsLong ? $bedtSecondsLong : undef));
	my $reSLat = ($reSecondsLat ? $reSecondsLat : 
				($redtSecondsLat ? $redtSecondsLat : undef));
	my $reSLong = ($reSecondsLong ? $reSecondsLong : 
				($redtSecondsLong ? $redtSecondsLong : undef));
	if ($beSLat)
	{
		$b_lat = parseSeconds($beSLat);
	}
	if ($beSLong)
	{
		$b_long = parseSeconds($beSLong);
	}
	if ($reSLat)
	{
		$e_lat = parseSeconds($reSLat);
	}
	if ($reSLong)
	{
		$e_long = parseSeconds($reSLong);
	}
	if ($beTrueAlign eq "")
	{
	  $beTrueAlign = undef;
	}
	if ($reTrueAlign eq "")
	{
	  $reTrueAlign = undef;
	}
	if ($beElev eq "")
	{
	  $beElev = undef;
	}
	if ($reElev eq "")
	{
	  $reElev = undef;
	}

	storeRunway($datasource_key, $rwyId, $rwyLen, $rwyWidth, $rwySurfaceType,
        $b_lat, $b_long, $beTrueAlign, $beElev,
        $e_lat, $e_long, $reTrueAlign, $reElev);
}

sub parseFAAAirportRemarkRecord($$)
{
	my ($currentKey, $line) = @_;

	# Actually, I don't need remarks for anything, so skip these for now.
}

sub parseFAAAirportAttendenceRecord($$)
{
	my ($currentKey, $line) = @_;

	# Actually, I don't need this for anything, so skip it for now.
}

sub read_FAA_Airports($)
{
    my ($fn) = @_;

    my $fh = new IO::File($fn.".txt") || new IO::File($fn.".TXT") or
    die "Airport file $fn not found";

	my $currentKey;
    while (<$fh>)
    {
        chomp;

		my $recordType = unpack("A3", $_);

		if ($recordType eq "APT")
		{
			$currentKey = parseFAAAirportAirportRecord($_);
		}
		elsif ($recordType eq "ATT")
		{
			parseFAAAirportAttendenceRecord($currentKey, $_);
		}
		elsif ($recordType eq "RWY")
		{
			parseFAAAirportRunwayRecord($currentKey, $_);
		}
		elsif ($recordType eq "RMK")
		{
			parseFAAAirportRemarkRecord($currentKey, $_);
		}
	}
    undef $fh;
	storeAllWaypoints("end of airports", 0);
}

sub parseFAANavaidNAV1($)
{
	my ($line) = @_;

	my ($recordType, $id, $type, $officialId, $effDate, $name, $city,
		$cityStateName, $cityState, $faaRegion, $country, $countryCode,
		$ownerName, $operatorName, $commonSystemUsage, $publicUse, $class,
		$hours, $artccHiId, $artccHiName, $artccLoId, $artccLoName,
		$formattedLat, $secondsLat, $formattedLong,
		$secondsLong, $surveyAcc, $tacanFormattedLat, $tacanSecondsLat,
		$tacanFormattedLong, $tacanSecondsLong, $elev, $magVar,
		$magVarEpoch, $simultaneousVoice, $power, $avif,
		$monitoringCategory, $radioVoiceCallName, $tacanChannel, $freq,
		$beaconMorse, $fanMarkerType, $fanMarkerBearing, $protectedFreq,
		$lowInHigh, $zMarker, $twebHours, $twebPhone,
		$fssId, $fssName, $fssHours,
		$notamCode, $quadId, $navaidStatus,
		$pitchFlag, $catchFlag, $suaFlag,
		$navaidRestriction, $hiwas, $tweb) = unpack("A4 A4 A20 A4 A10" .
		"A30 A40 A30 A2 A3 A30 A2 A50 A50 A1 A1 A11 A11 A4 " .
		"A30 A4 A30 A14 A11 A14" .
		"A11 A1 A14 A11 A14 A11 A7 A5 A4 A3 A4 A3 A1 A30 A4 A6 A24 A10" .
		"A3 A1 A3 A3 A9 A20 A4 A30 A100 A4 A16 A30 A1 A1 A1 A1 A1", $line);
	$country = faaToICAOCountry($country);

print "navaid before id = $id, officialId = $officialId";
	if ($country eq "US")
	{
		($id,$cityState,$country) =
			normalizeID($id,$cityState,$country,undef, 0);
	}
print ", normalized id = $id\n";

	my $lat = parseSeconds($secondsLat);

	my $long = parseSeconds($secondsLong);

	if ($elev eq "")
	{
		$elev = undef;
	}

    # use the given declination for navaids
	my $decl = 0;
	if ($magVar ne "")
	{
		my $ew = substr($magVar, -1);
		$decl = substr($magVar, 0, -1);
		if ($ew eq "E")
		{
			$decl = -$decl;
		}
		else
		{
		  $decl += 0;
		}
	}

	if ($decl == 0)
	{
		$decl = getMagVar($lat, $long, defined($elev) ? $elev : 0);
	}

	if ($country eq 'CA')
	{
		$cityState = getProvince($lat, $long);
	}

	if ($city eq $name)
	{
		$city = "";
	}

	my %waypoint;
	$waypoint{id} = $id;
	$waypoint{type} = $type;
	$waypoint{name} = $name;
	$waypoint{city} = $city;
	$waypoint{state} = $cityState;
	$waypoint{country} = $country;
	$waypoint{latitude} = $lat;
	$waypoint{longitude} = $long;
	$waypoint{declination} = $decl;
	if (defined($elev))
	{
	  $elev += 0;
	}
	$waypoint{elevation} = $elev;
	$waypoint{main_frequency} = $freq;
	$waypoint{ispublic} = ($publicUse ne "N") ? 1 : 0;
	$waypoint{orig_datasource} = Datasources::DATASOURCE_FAA;

	return \%waypoint;
}

sub parseFAANavaidNAV2($$)
{
	my ($currentKey, $line) = @_;
	# Don't care.
}

sub parseFAANavaidNAV3($$)
{
	my ($currentKey, $line) = @_;
	# Don't care.
}

sub parseFAANavaidNAV4($$)
{
	my ($currentKey, $line) = @_;
	# Don't care.
}

sub parseFAANavaidNAV5($$)
{
	my ($currentKey, $line) = @_;
	# Don't care.
}

sub read_FAA_Navaids($)
{
    my ($fn) = @_;
    my $fh = new IO::File($fn.".txt") || new IO::File($fn.".TXT") or
    die "Navaid file $fn not found";

	my $waypointRef;
    while (<$fh>)
    {
        chomp;

		my $recordType = unpack("A4", $_);

		if ($recordType eq "NAV1")
		{
			$waypointRef = parseFAANavaidNAV1($_);

			# We don't use the other records, so write it now.
			insertWaypoint($waypointRef);
		}
		elsif ($recordType eq "NAV2")
		{
			parseFAANavaidNAV2($waypointRef, $_);
		}
		elsif ($recordType eq "NAV3")
		{
			parseFAANavaidNAV3($waypointRef, $_);
		}
		elsif ($recordType eq "NAV4")
		{
			parseFAANavaidNAV4($waypointRef, $_);
		}
		elsif ($recordType eq "NAV5")
		{
			parseFAANavaidNAV4($waypointRef, $_);
		}
	}
    undef $fh;
}

sub parseFAACommTWR1($)
{
	my ($line) = @_;

	my ($recordType, $id, $effDate, $datasource_key, $faa_region_code,
		$state_name, $state, $city, $name, $formattedLat, $secondsLat,
		$formattedLong, $secondsLong, $fssId, $fssName, $facilityType,
		$hours, $daysCode, $masterAirportCode, $masterAirportName, $dfType,
		$landingFacilityName, $landingFacilityCity, $landingFacilityStateName,
		$landingFacilityCountry, $landingFacilityState,
		$landingFacilityFAARegion,
		$asrFormattedLat, $asrSecondsLat,
		$asrFormattedLong, $asrSecondsLong,
		$dfFormattedLat, $dfSecondsLat,
		$dfFormattedLong, $dfSecondsLong,
		$twrAgencyName, $milAgencyName, $appAgencyName, $secAppAgencyName,
		$depAgencyName, $secDepAgencyName, $radioName, $milRadioName,
		$appRadioName, $secAppRadioName, $depRadioName, $secDepRadioName) =
		unpack("A4 A4 A10 A11 A3 A30 A2 A40 A50 A14 A11 A14 A11 A4" .
		"A30 A12 A2 A3 A4 A50 A15 A50 A40 A20 A25 A2 A3 A14 A11 A14 A11 " .
		"A14 A11 A14 A11 A40 A40 A40 A40 A40 A40 A26 A26 A26 A26 A26 A26",
		$line);
	return $datasource_key;
}

sub parseFAACommTWR2($$)
{
	my ($datasource_key, $line) = @_;
}

sub fiddleCommId($$$$)
{
	my ($datasource_key, $section, $frequency, $longFreq) = @_;
	if ($section eq "" or $frequency !~ m/^[0-9]/)
	{
		return;
	}
	my $freq_type;
	if ($longFreq ne "")
	{
		$frequency = $longFreq;
	}
	($freq_type,$frequency) = fixCommNameAndFreq($section, $frequency);
	storeCommunication($datasource_key, $freq_type,
        $section, $frequency);
}

sub parseFAACommTWR3($$)
{
	my ($datasource_key, $line) = @_;

	my ($recordType, $id, $freq1, $sec1, $freq2, $sec2, $freq3, $sec3,
		$freq4, $sec4, $freq5, $sec5, $freq6, $sec6, $freq7, $sec7,
		$freq8, $sec8, $freq9, $sec9,
		$longFreq1, $longFreq2, $longFreq3, $longFreq4, $longFreq5, $longFreq6,
		$longFreq7, $longFreq8, $longFreq9) =
		unpack("A4 A4" .
		"A44 A50 A44 A50 A44 A50 A44 A50 A44 A50 A44 A50 A44 A50 A44 A50" .
		"A44 A50 A60 A60 A60 A60 A60 A60 A60 A60 A60 A60",
		$line);

	fiddleCommId($datasource_key, $sec1, $freq1, $longFreq1);
	fiddleCommId($datasource_key, $sec2, $freq2, $longFreq2);
	fiddleCommId($datasource_key, $sec3, $freq3, $longFreq3);
	fiddleCommId($datasource_key, $sec4, $freq4, $longFreq4);
	fiddleCommId($datasource_key, $sec5, $freq5, $longFreq5);
	fiddleCommId($datasource_key, $sec6, $freq6, $longFreq6);
	fiddleCommId($datasource_key, $sec7, $freq7, $longFreq7);
	fiddleCommId($datasource_key, $sec8, $freq8, $longFreq8);
	fiddleCommId($datasource_key, $sec9, $freq9, $longFreq9);
}

sub parseFAACommTWR4($$)
{
	my ($datasource_key, $line) = @_;
}

sub parseFAACommTWR5($$)
{
	my ($datasource_key, $line) = @_;
}

sub parseFAACommTWR6($$)
{
	my ($datasource_key, $line) = @_;
}

sub parseFAACommTWR7($)
{
	my ($line) = @_;

	my ($recordType, $id, $satFreq, $satFreqUse, $satDatasource_key,
		$satId, $satFAARegionCode, $satStateName, $satState, $satCity,
		$satName, $formattedLat, $secondsLat, $formattedLong, $secondsLong,
		$fssId, $fssName, $maDatasource_key, $maFAARegionCode, $maStateName,
		$maState, $maCity, $maName, $longSatFreq) =
	unpack("A4 A4 A44 A50 A11 A4 A3 A30 A2 A40 A50 " .
		"A14 A11 A14 A11 A4 A30 A11 A3 A30 A2 A40 A50 A60", $line);

	fiddleCommId($satDatasource_key, $satFreqUse, $satFreq,
		$longSatFreq);
}

sub read_FAA_Comm($)
{
    my ($fn) = @_;
    my $fh = new IO::File($fn.".txt") || new IO::File($fn.".TXT") or
    die "Comm file $fn not found";

	my $currentKey;
    while (<$fh>)
    {
        chomp;

		my $recordType = unpack("A4", $_);

		if ($recordType eq "TWR1")
		{
			$currentKey = parseFAACommTWR1($_);
		}
		elsif ($recordType eq "TWR2")
		{
			next if ($currentKey eq "");
			parseFAACommTWR2($currentKey, $_);
		}
		elsif ($recordType eq "TWR3")
		{
			next if ($currentKey eq "");
			parseFAACommTWR3($currentKey, $_);
		}
		elsif ($recordType eq "TWR4")
		{
			next if ($currentKey eq "");
			parseFAACommTWR4($currentKey, $_);
		}
		elsif ($recordType eq "TWR5")
		{
			next if ($currentKey eq "");
			parseFAACommTWR5($currentKey, $_);
		}
		elsif ($recordType eq "TWR6")
		{
			next if ($currentKey eq "");
			parseFAACommTWR6($currentKey, $_);
		}
		elsif ($recordType eq "TWR7")
		{
		    # TWR7 is independent of the currentKey.
			parseFAACommTWR7($_);
		}
	}
    undef $fh;
}

sub read_FAA_AWOS($)
{
    my ($fn) = @_;
    my $fh = new IO::File($fn.".txt") || new IO::File($fn.".TXT") or
	die "AWOS file $fn not found";

    while (<$fh>)
    {
        chomp;
		my ($type, $stationID, $stationType,
			$commissioningStatus, $commissioningDate, $navaidFlag,
			$stationLat, $stationLong, $elevation, $surveyMethod,
			$stationFreq, $secondFreq,
			$stationTelephone, $secondTelephone,
			$datasource_key, $stationCity,
			$stationState, $effDate) =
			unpack("A5 A4 A10 A1 A10 A1 A14 A15 A7 A1 A7 A7 A14 A14 " .
					"A11 A40 A2 A10", $_);

		next if ($type ne "AWOS1");

		next if ($datasource_key eq "");

		if ($stationFreq ne "")
		{
		  storeCommunication($datasource_key, "AWOS",
			  $stationType, $stationFreq);
		}

		if ($secondFreq ne "")
		{
		  storeCommunication($datasource_key, "AWOS",
			  $stationType, $secondFreq);
		}
	}
    undef $fh;
}

sub parseLatLong($)
{
	my $latLong = shift;

	my $nsew = substr($latLong, -1);
	my $seconds = substr($latLong, -7, 6);
	my $mins = substr($latLong, -10, 2);
	my $degs = substr($latLong, -14, 3);

	$degs = $degs + ($mins / 60.0) + ($seconds / 3600.0);

	if ($nsew eq "S" || $nsew eq "W")
	{
		$degs = -$degs;
	}
	return $degs;
}

sub mapStateName($$$$)
{
	my ($state_name, $country, $lat, $long) = @_;
print "mapStateName($state_name, $country, $lat, $long)\n";
	my $key;
	my $state = "";

	if ($country eq "CANADA")
	{
print "Canada\n";
		$country = "CA";
		$state = getProvince($lat, $long);
	}
	elsif (exists($faaCountries{$country}))
	{
print "faaCountries equals country\n";
	  $state = "";
	  $country = $faaCountries{$country};
	}
	elsif (exists($faaCountries{$state_name}))
	{
print "faaCountries equals state_name\n";
	  $state = "";
	  $country = $faaCountries{$state_name};
	}
	elsif (exists($faaStates{$state_name}))
	{
print "faaStates equals\n";
	  $state = $faaStates{$state_name};
	  $country = "US";
	}
	else
	{
	  ($state, $country) = getStateCountry($state_name);
print "looking up in the database: ", 
	defined($state) ? $state : "-no state-", ",",
	defined($country) ? $country : "-no country-", "\n";

	  if (!defined($state) || $state eq "")
	  {
print "DESPERATION TIME!\n";
		$state = "";
		$country = "US";
	  }
	}
print "returning ($state, $country)\n";
	return ($state, $country);
}

sub parseFAAWaypointFIX1($$$$$$)
{
	my ($dsKey, $state_code, $old_stateName, $newCountry, $oldCountry,
			$line) = @_;

	storeAllWaypoints("flushing previous fix", 1);

	my ($code, $name, $stateName, $icaoRegion, $lat, $long, $fixCat,
			$fixDesc, $fixAptDesc, $prevName, $chartingInfo, $isPublished,
			$fixUse, $nasID, $artccHi, $artccLo, $country,
			$pitch, $catch, $sua, $blanks) = 
		unpack("A4 A30 A30 A2 A14 A14 A3 A22 A22 A33 A38 A1 A15 A5 A4 " .
		"A4 A30 A1 A1 A1 A192", $line);

	# Skip the ones with no category
	#next if ($fixCat eq "");

	my $id = $name;
	$id =~ s/\W+$//;

	# Skip the ones that are colocated with a navaid.
print "id = [$id], nasID = [$nasID]\n";
	if ($nasID ne "" && $nasID ne $id)
	{
	  print "skipping colocated waypoint $id, $nasID\n"; $| = 1;
	  return ($state_code, $old_stateName, $newCountry, $oldCountry);
	}

	$lat = parseLatLong($lat);
	$long = parseLatLong($long);

	if ($stateName ne $old_stateName || $country eq "CANADA")
	{
		($state_code, $newCountry) = mapStateName($stateName, $country,
				$lat, $long);
		$old_stateName = $stateName;
		$oldCountry = $newCountry;
	}

	my $decl = getMagVar($lat, $long, 0);

	storeWaypoint($id, $dsKey, $fixUse, $name, undef,
					$state_code, $newCountry, $lat, $long, $decl, 0,
					0, undef, 1, undef, undef, undef, undef);

	return ($state_code, $old_stateName, $newCountry, $oldCountry);
}

sub parseFAAWaypointFIX2($$)
{
	my ($dsKey, $line) = @_;

	my ($code, $name, $stateName, $icaoRegion, $fixInfo, $blanks) = 
		unpack("A4 A30 A30 A2 A23 A377", $line);

	my $id = $name;
	$id =~ s/\W+$//;

	FAA_FIX_code($id, $dsKey, $fixInfo);
}

sub parseFAAWaypointFIX3($$)
{
	my ($dsKey, $line) = @_;

	my ($code, $name, $stateName, $icaoRegion, $fixInfo, $blanks) = 
		unpack("A4 A30 A30 A2 A23 A377", $line);

	my $id = $name;
	$id =~ s/\W+$//;

	FAA_FIX_code($id, $dsKey, $fixInfo);
}

sub parseFAAWaypointFIX4($$)
{
	my ($dsKey, $line) = @_;
}

sub parseFAAWaypointFIX5($$)
{
	my ($dsKey, $line) = @_;

	my ($code, $name, $stateName, $icaoRegion, $chartInfo, $blanks) = 
		unpack("A4 A30 A30 A2 A22 A378", $line);

	my $id = $name;
	$id =~ s/\W+$//;

	$chartInfo =~ s/\W+$//;
	my $local_cmap = $FAA_chart_codes{$chartInfo};
	if (!defined($local_cmap))
	{
		print "ERROR: Unknown map code $chartInfo\n";
		return;
	}
	updateChartMap($dsKey, $local_cmap);
}

sub read_FAA_Waypoints($)
{
    my ($fn) = @_;
    my $fh = new IO::File($fn.".txt") || new IO::File($fn.".TXT") or
    die "Waypoint file $fn not found";

	my $dsKey = 0;

	my $state_code = "";
	my $old_stateName = "";
	my $newCountry = "";
	my $oldCountry = "";
    while (<$fh>)
    {
        chomp;
		my $recordType = unpack("A4", $_);


		if ($recordType eq "FIX1")
		{
			$dsKey++;
			($state_code, $old_stateName, $newCountry, $oldCountry) =
				parseFAAWaypointFIX1($dsKey, $state_code, $old_stateName,
					$newCountry, $oldCountry, $_);
		}
		elsif ($recordType eq "FIX2")
		{
			parseFAAWaypointFIX2($dsKey, $_);
		}
		elsif ($recordType eq "RIX3")
		{
			parseFAAWaypointFIX3($dsKey, $_);
		}
		elsif ($recordType eq "FIX4")
		{
			parseFAAWaypointFIX4($dsKey, $_);
		}
		elsif ($recordType eq "FIX5")
		{
			parseFAAWaypointFIX5($dsKey, $_);
		}
	}
	undef $fh;
}

sub FAA_FIX_code($$$)
{
    my ($id, $datasource_key, $fixCode) = @_;
    my ($navaid, $nc, $beardist) = split(/\*/, $fixCode);
    my ($bear, $dist) = defined($beardist) ?
            split(/\//, $beardist) :
            (undef, undef);
    my $code = defined($nc) ? $FAA_fix_navaids{$nc} : undef;
    die "undefined code for $nc, fixCode = $fixCode" if defined($nc) && !defined($code);
    if (defined($bear))
    {
	  if ($bear eq "" || $bear =~ /CRS/)
	  {
        $bear = undef;
	  }
	  elsif ($bear eq "N")
	  {
		$bear = 0;
	  }
	  elsif ($bear eq "NE")
	  {
		$bear = 45;
	  }
	  elsif ($bear eq "E")
	  {
		$bear = 90;
	  }
	  elsif ($bear eq "SE")
	  {
		$bear = 135;
	  }
	  elsif ($bear eq "S")
	  {
		$bear = 180;
	  }
	  elsif ($bear eq "SW")
	  {
		$bear = 225;
	  }
	  elsif ($bear eq "W")
	  {
		$bear = 270;
	  }
	  elsif ($bear eq "NW")
	  {
		$bear = 315;
	  }
	  elsif ($bear !~ m/^[0-9]*\.?[0-9]*$/)
	  {
		die "invalid bearing:", $bear, "\n";
	  }
    }
    if (defined($dist))
    {
        if ($dist eq "")
        {
            $dist = undef;
        }
        else
        {
            $dist = int($dist + 0.5);
        }
    }
    #print "id = $id, fixCode = $fixCode";
    #print ", navaid = $navaid";
    #print ", code = ", (defined($nc) ? "$code/$nc" : "undef/undef");
    #print ", bearing/distance = ", (defined($beardist) ? $beardist : "undef");
    #print ", bearing = ", (defined($bear) ? $bear : "undef");
    #print ", distance = ", (defined($dist) ? $dist : "undef");
    #print "\n";
    storeFix($datasource_key, $navaid, $code, $bear, $dist);
}

print "starting...\n";
startDatasource(Datasources::DATASOURCE_FAA);

print "loading FAA comm freqs\n";
read_FAA_Comm($faadir . "/TWR");

print "loading FAA AWOS freqs\n";
read_FAA_AWOS($faadir . "/AWOS");

print "loading FAA airports\n";
read_FAA_Airports($faadir . "/APT");
flushWaypoints();

print "loading FAA navaids\n";
read_FAA_Navaids($faadir . "/NAV");
flushWaypoints();

print "loading FAA waypoints\n";
read_FAA_Waypoints($faadir . "/FIX");
flushWaypoints();

print "finishing up\n";
endDatasource(Datasources::DATASOURCE_FAA);

print "Done loading\n";

postLoad();

dbClose();
