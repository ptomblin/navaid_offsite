#!/usr/bin/perl -w

# FAA Format as of 25Oct2007
#

use DBI;
use IO::File;

use strict;

$| = 1; # for debugging

use Datasources;
use WaypointTypes;
use WPInfo;

use DBLoad;
DBLoad::initialize();

my %DAFIF_navaid_types =
  (1 => "VOR", 2 => "VORTAC", 3 => "TACAN", 4 => "VOR/DME", 5 => "NDB",
    7 => "NDB/DME", 9 => "DME");

# These mappings are pretty arbitrary.
my %DAFIF_waypoint_types =
  ("I"	=> "CNF",
   "IF" => "GPS-WP",
   "R"	=> "REP-PT",
   "RF" => "RNAV-WP",
   "V"	=> "VFR-WP",
   "W"  => "RNAV-WP");

my %DAFIF_use_codes =
  ("H"	=> WaypointTypes::WPTYPE_HIGH_ENROUTE,
   "L"  => WaypointTypes::WPTYPE_LOW_ENROUTE,
   "B"  => WaypointTypes::WPTYPE_LOW_ENROUTE|
           WaypointTypes::WPTYPE_HIGH_ENROUTE,
   "R"  => WaypointTypes::WPTYPE_RNAV,
   "T"  => WaypointTypes::WPTYPE_APPROACH,
   "G"  => WaypointTypes::WPTYPE_APPROACH,
   "P"  => WaypointTypes::WPTYPE_RNAV,
   "E"  => WaypointTypes::WPTYPE_RNAV,
   "S"  => WaypointTypes::WPTYPE_HIGH_ENROUTE
   );

my %FAA_chart_codes =
  ("AREA"                   =>  WaypointTypes::WPTYPE_RNAV,
   "CONTROLLER"             =>  0,
   "CONTROLLER CHART ONLY"  =>  0,
   "ENROUTE HIGH"           =>  WaypointTypes::WPTYPE_HIGH_ENROUTE,
   "ENROUTE LOW"            =>  WaypointTypes::WPTYPE_LOW_ENROUTE,
   "HELICOPTER ROUTE"       =>  WaypointTypes::WPTYPE_VFR,
   "IAP"                    =>  WaypointTypes::WPTYPE_APPROACH,
   "IFR GOM VERTICAL FLT"   =>  WaypointTypes::WPTYPE_APPROACH,
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

sub parseMagVar($)
{
	my $mag_var = shift;
	my $ew = substr($mag_var, 0, 1);
	my $decl = substr($mag_var, 1, 3);
	my $decl_tenth_mins = substr($mag_var, 4, 3);
	$decl += (int($decl_tenth_mins / 6 + 0.5)/100.0);
	if ($ew eq "E")
	{
		$decl = -$decl;
	}
	return $decl;
}

sub getStateProvince($$$$)
{
    my ($state_prov, $country, $lat, $long) = @_;
	my $state = '';
	if ($state_prov ne '')
	{
		$state = $DBLoad::states{$state_prov}->{"code"};
	}
	if ($country eq 'CA')
	{
		$state = getProvince($lat, $long);
	}
    return $state;
}

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
		"BS"	=>	"BF"
		);
# Long names that convert to states
my %faaStates = (
		"OFFSHORE ATLANTIC"		=>	"OA",
		"OFFSHORE GULF"			=>	"OG",
		"OFFSHORE PACIFIC"		=>	"OP",
		"PACIFIC OCEAN"			=>	"OP"
);
# Long names that convert to countries
my %faaCountries = (
		"AMA"					=>	"PM", # Truncated "PANAMA"
		"AMERICAN SAMOA"		=>	"AQ",
		"ANTIGUA AND BARBUDA"	=>	"AC",
		"BAHAMAS"				=>	"BF",
		"BAHAMA ISLANDS"		=>	"BF",
		"BARBADOS"				=>	"BB",
		"BELIZE"				=>	"BH",
		"BERMUDA"				=>	"BD",
		"BRITISH WEST INDIES"	=>	"TK",
		"CANADA"				=>	"CA",
		"CAYMAN ISLANDS"		=>	"CJ",
		"COLOMBIA"				=>	"CO",
		"COSTA RICA"			=>	"CS",
		"CUBA"					=>	"CU",
		"DOMINICA"				=>	"DO",
		"DOMINICAN REPUBLIC"	=>	"DR",
		"DURAS"					=>	"HO", # Truncated "HONDURAS"
		"ECUADOR"				=>	"EC",
		"EL SALVADOR"			=>	"ES",
		"FED STS MICRONESIA"	=>	"FM",
		"FRENCH WEST INDIES"	=>	"GP", # Maybe should be Martinique
		"GRENADA"				=>	"GJ",
		"GUAM"					=>	"GQ",
		"GUYANA"				=>	"GY",
		"HAITI"					=>	"HA",
		"HONDURAS"				=>	"HO",
		"ICO"					=>	"MX", # Truncated "MEXICO"
		"JAMAICA"				=>	"JM",
		"MARSHALL ISLANDS"		=>	"RM",
		"MEXICO"				=>	"MX",
		"MIDWAY ATOLL"			=>	"MQ",
		"NETHERLANDS ANTILLES"	=>	"NT",
		"NICARAGUA"				=>	"NU",
		"NOTHERN MARIANA ISLA"	=>	"CQ", # Note the FAA spelling
		"NORTHERN MARIANA ISL"	=>	"CQ", # In case they fix the spelling
		"N MARIANA ISLANDS"		=>	"CQ", # They took the easy way out.
		"PALAU"					=>	"PS",
		"PANAMA"				=>	"PM",
		"PERU"					=>	"PE",
		"PUERTO RICO"			=>	"RQ",
		"SAINT KITTS AND NEVI"	=>	"SC",
		"TRINIDAD AND TOBAGO"	=>	"TD",
		"TRUST TERRITORIES"		=>	"JQ", # Lump them all together
		"TURKS AND CAICOS ISL"	=>	"TK",
		"VENEZUELA"				=>	"VE",
		"VIRGIN ISLANDS"		=>	"VQ",
		"SAINT LUCIA"			=>	"ST",
		"MARTINIQUE"			=>	"MB",
		"ST. VINCENT AND THE"	=>	"VC",
		"GUADELOUPE"			=>	"GP",
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
		# Difficult state, translate it.
		$state = $difficultStates{$state};
		$country = "US";
		$idDone = 1;
	}
	elsif (exists($insaneStates{$state}))
	{
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
  if ($letter eq "S" || $letter eq "E")
  {
	$latlong = -$latlong;
  }
  return $latlong;
}

#   This is a really convoluted and bizarre attempt to correct "FAA" airport
#   ids from the FAA datafile based on the data in the DAFIF file.
sub updateWaypoint($$$$$$$$$$$$$$$)
{
    my ($faa_host_id, $id, $datasource_key, $type, $name, $address,
        $state, $country, $latitude, $longitude, $declination, $elevation,
        $main_frequency, $datasource, $isPublic) = @_;

    finishWaypoint();
    if ($faa_host_id ne 'N')
    {
        if (findRecord($faa_host_id, $country, $state, $type,
            $latitude, $longitude, 0))
        {
            updateWaypointID($id, $faa_host_id, $type, $country,
                $state);
            print "renamed $type $faa_host_id to $id\n";
        }
    }
    return insertWaypoint($id, $datasource_key, $type, $name, $address,
                    $state, $country, $latitude, $longitude, $declination,
                    $elevation, $main_frequency, $datasource, $isPublic,
                    0, undef);
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
	elsif ($type =~ m/CLNC DEL/ || $type =~ m/CD/ || $type =~ m/PRE TAXI/)
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

#   Read a record from the DAFIF ACOM file.
sub readACOM($$)
{
    my ($cfh, $comm_ref) = @_;

    my $line = <$cfh>;

    if (!defined($line))
    {
        $comm_ref->{ident} = "ZZZZZZZZZ";
        return;
    }

    chomp($line);

    my ($ident, $type, $name, $sym, $freq1, $freq2, $freq3, $freq4, $freq5,
        $sec, $s_opr_h, $cycle_date, $multi, $freq_multi,
        $com_freq1, $freq_unit1, $com_freq2, $freq_unit2,
        $com_freq3, $freq_unit3, $com_freq4, $freq_unit4,
        $com_freq5, $freq_unit5) = split("\t", $line);

   $comm_ref->{ident} = $ident;
   $comm_ref->{type} = $type;
   $comm_ref->{name} = $name;
   $comm_ref->{sym} = $sym;
   $freq1 =~ s/ .*//g;
   $freq2 =~ s/ .*//g;
   $freq3 =~ s/ .*//g;
   $freq4 =~ s/ .*//g;
   $freq5 =~ s/ .*//g;
   $comm_ref->{freq1} = $freq1;
   $comm_ref->{freq2} = $freq2;
   $comm_ref->{freq3} = $freq3;
   $comm_ref->{freq4} = $freq4;
   $comm_ref->{freq5} = $freq5;
   $comm_ref->{sec} = $sec;
   $comm_ref->{s_opr_h} = $s_opr_h;
   $comm_ref->{cycle_date} = $cycle_date;
   $comm_ref->{multi} = $multi;
}

#   Read a record from the DAFIF HCOM file.
sub readHCOM($$)
{
    my ($cfh, $comm_ref) = @_;

    my $line = <$cfh>;

    if (!defined($line))
    {
        $comm_ref->{ident} = "ZZZZZZZZZ";
        return;
    }

    chomp($line);

    my ($ident, $type, $name, $sym, $freq1, $freq2, $freq3, $freq4, $freq5,
        $sec, $s_opr_h, $cycle_date, $multi, $freq_multi,
        $com_freq1, $freq_unit1, $com_freq2, $freq_unit2,
        $com_freq3, $freq_unit3, $com_freq4, $freq_unit4,
        $com_freq5, $freq_unit5) = split("\t", $line);

   $comm_ref->{ident} = $ident;
   $comm_ref->{type} = $type;
   $comm_ref->{name} = $name;
   $comm_ref->{sym} = $sym;
   $freq1 =~ s/ .*//g;
   $freq2 =~ s/ .*//g;
   $freq3 =~ s/ .*//g;
   $freq4 =~ s/ .*//g;
   $freq5 =~ s/ .*//g;
   $comm_ref->{freq1} = $freq1;
   $comm_ref->{freq2} = $freq2;
   $comm_ref->{freq3} = $freq3;
   $comm_ref->{freq4} = $freq4;
   $comm_ref->{freq5} = $freq5;
   $comm_ref->{sec} = $sec;
   $comm_ref->{s_opr_h} = $s_opr_h;
   $comm_ref->{cycle_date} = $cycle_date;
   $comm_ref->{multi} = $multi;
}

#   Read a record from the DAFIF RWY file.
sub readRWY($$)
{
    my ($rfh, $rwy_ref) = @_;

    my $line = <$rfh>;

    if (!defined($line))
    {
        $rwy_ref->{ident} = "ZZZZZZZZZ";
        return;
    }

    chomp($line);

    my ($ident, $high_ident, $low_ident, $high_hdg, $low_hdg, $rwy_length,
        $rwy_width, $surface, $pcn,
        $he_wgs_lat, $he_wgs_dlat, $he_wgs_long, $he_wgs_dlong, $he_elev,
        $he_slope, $he_tdze, $he_dt, $he_dt_elev,
        $hlgt_sys_1, $hlgt_sys_2, $hlgt_sys_3, $hlgt_sys_4, $hlgt_sys_5,
        $hlgt_sys_6, $hlgt_sys_7, $hlgt_sys_8,
        $le_wgs_lat, $le_wgs_dlat, $le_wgs_long, $le_wgs_dlong, $le_elev,
        $le_slope, $le_tdze, $le_dt, $le_dt_elev,
        $llgt_sys_1, $llgt_sys_2, $llgt_sys_3, $llgt_sys_4, $llgt_sys_5,
        $llgt_sys_6, $llgt_sys_7, $llgt_sys_8,
        $he_true_hdg, $le_true_hdg, $cld_rwy,
        $heland_dis, $he_takeoff, 
        $leland_dis, $le_takeoff,
        $cycle_date) = split("\t", $line);

   $rwy_ref->{ident} = $ident;
   $rwy_ref->{high_ident} = $high_ident;
   $rwy_ref->{low_ident} = $low_ident;
   $rwy_ref->{high_hdg} = $high_hdg;
   $rwy_ref->{low_hdg} = $low_hdg;
   $rwy_ref->{rwy_length} = $rwy_length;
   $rwy_ref->{rwy_width} = $rwy_width;
   $rwy_ref->{surface} = $surface;
   $rwy_ref->{pcn} = $pcn;
   $rwy_ref->{he_wgs_lat} = $he_wgs_lat;
   $rwy_ref->{he_wgs_dlat} = $he_wgs_dlat;
   $rwy_ref->{he_wgs_long} = $he_wgs_long;
   $rwy_ref->{he_wgs_dlong} = $he_wgs_dlong;
   $rwy_ref->{he_elev} = $he_elev;
   $rwy_ref->{he_slope} = $he_slope;
   $rwy_ref->{he_tdze} = $he_tdze;
   $rwy_ref->{he_dt} = $he_dt;
   $rwy_ref->{he_dt_elev} = $he_dt_elev;
   $rwy_ref->{hlgt_sys_1} = $hlgt_sys_1;
   $rwy_ref->{hlgt_sys_2} = $hlgt_sys_2;
   $rwy_ref->{hlgt_sys_3} = $hlgt_sys_3;
   $rwy_ref->{hlgt_sys_4} = $hlgt_sys_4;
   $rwy_ref->{hlgt_sys_5} = $hlgt_sys_5;
   $rwy_ref->{hlgt_sys_6} = $hlgt_sys_6;
   $rwy_ref->{hlgt_sys_7} = $hlgt_sys_7;
   $rwy_ref->{hlgt_sys_8} = $hlgt_sys_8;
   $rwy_ref->{le_wgs_lat} = $le_wgs_lat;
   $rwy_ref->{le_wgs_dlat} = $le_wgs_dlat;
   $rwy_ref->{le_wgs_long} = $le_wgs_long;
   $rwy_ref->{le_wgs_dlong} = $le_wgs_dlong;
   $rwy_ref->{le_elev} = $le_elev;
   $rwy_ref->{le_slope} = $le_slope;
   $rwy_ref->{le_tdze} = $le_tdze;
   $rwy_ref->{le_dt} = $le_dt;
   $rwy_ref->{le_dt_elev} = $le_dt_elev;
   $rwy_ref->{llgt_sys_1} = $llgt_sys_1;
   $rwy_ref->{llgt_sys_2} = $llgt_sys_2;
   $rwy_ref->{llgt_sys_3} = $llgt_sys_3;
   $rwy_ref->{llgt_sys_4} = $llgt_sys_4;
   $rwy_ref->{llgt_sys_5} = $llgt_sys_5;
   $rwy_ref->{llgt_sys_6} = $llgt_sys_6;
   $rwy_ref->{llgt_sys_7} = $llgt_sys_7;
   $rwy_ref->{llgt_sys_8} = $llgt_sys_8;
   $rwy_ref->{he_true_hdg} = $he_true_hdg;
   $rwy_ref->{le_true_hdg} = $le_true_hdg;
   $rwy_ref->{cld_rwy} = $cld_rwy;
   $rwy_ref->{heland_dis} = $heland_dis;
   $rwy_ref->{he_takeoff} = $he_takeoff;
   $rwy_ref->{leland_dis} = $leland_dis;
   $rwy_ref->{le_takeoff} = $le_takeoff;
   $rwy_ref->{cycle_date} = $cycle_date;
}

sub insertACOM($$$)
{
    my ($key, $cfh, $comm_ref) = @_;

    while ($key gt $comm_ref->{ident})
    {
        readACOM($cfh, $comm_ref);
    }
    while ($key eq $comm_ref->{ident})
    {
		insertCommunications($comm_ref->{ident}, $comm_ref->{type},
                        $comm_ref->{name},
						$comm_ref->{freq1}, $comm_ref->{freq2},
						$comm_ref->{freq3}, $comm_ref->{freq4},
						$comm_ref->{freq5}, "",
                        Datasources::DATASOURCE_DAFIF, 0);

        readACOM($cfh, $comm_ref);
    }
}

sub insertHCOM($$$)
{
    my ($key, $cfh, $comm_ref) = @_;

    while ($key gt $comm_ref->{ident})
    {
        readHCOM($cfh, $comm_ref);
    }
    while ($key eq $comm_ref->{ident})
    {
		insertCommunications($comm_ref->{ident}, $comm_ref->{type},
                        $comm_ref->{name},
						$comm_ref->{freq1}, $comm_ref->{freq2},
						$comm_ref->{freq3}, $comm_ref->{freq4},
						$comm_ref->{freq5}, "",
                        Datasources::DATASOURCE_DAFIF, 0);

        readHCOM($cfh, $comm_ref);
    }
}

sub insertRWY($$$)
{
    my ($key, $rfh, $rwy_ref) = @_;

    while ($key gt $rwy_ref->{ident})
    {
        readRWY($rfh, $rwy_ref);
    }
    while ($key eq $rwy_ref->{ident})
    {
        my $rwy_des = $rwy_ref->{low_ident} . "/" . $rwy_ref->{high_ident};

		my $b_lat = $rwy_ref->{le_wgs_dlat};
		if (!defined($b_lat) || $b_lat eq "U")
		{
		  $b_lat = undef;
		}
		my $b_long = $rwy_ref->{le_wgs_dlong};
		if (defined($b_long) && $b_long ne "U")
		{
			$b_long = 0.0 - $b_long;
		}
		else
		{
		  $b_long = undef;
		}
		my $e_lat = $rwy_ref->{he_wgs_dlat};
		if (!defined($e_lat) || $e_lat eq "U")
		{
		  $e_lat = undef;
		}
		my $e_long = $rwy_ref->{he_wgs_dlong};
		if (defined($b_long) && $b_long ne "U")
		{
			$e_long = 0.0 - $e_long;
		}

		if ($rwy_ref->{he_elev} eq "U")
		{
			$rwy_ref->{he_elev} = undef;
		}

		if ($rwy_ref->{le_elev} eq "U")
		{
			$rwy_ref->{le_elev} = undef;
		}

		insertRunway($rwy_ref->{ident}, $rwy_des,
					$rwy_ref->{rwy_length}, $rwy_ref->{rwy_width},
                    $rwy_ref->{surface}, ($rwy_ref->{cld_rwy} ne ""),
					$b_lat, $b_long,
                    $rwy_ref->{le_true_hdg}, $rwy_ref->{le_elev},
					$e_lat, $e_long,
                    $rwy_ref->{he_true_hdg}, $rwy_ref->{he_elev},
                    Datasources::DATASOURCE_DAFIF, 0);
        readRWY($rfh, $rwy_ref);
    }
}

sub delete_FAA_data()
{
	deleteWaypointData(Datasources::DATASOURCE_FAA, 1);
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
		$militaryJoint, $militaryRights, $nationalEmergency, $milUse,
		$inspMeth, $inspAgency, $lastInsp, $lastInfo, $fuel, $airframeRepairs,
		$engineRepairs, $bottledOyxgen, $bulkOxygen,
		$lightingSchedule, $tower, $unicomFreqs, $ctafFreq, $segmentedCircle,
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
		"A42 A2 A2 A35 A72 A45 A16 A35 A72 A45 A16 A15 A12 A15 A12 A1 A5 A1 " .
		"A3 A4 A4 A30 A2 A3 A5 A4 A3 A30 A4 A3 A30 A1 A4 A30 A16 A16 " .
        "A4 A30 A16 A4 " .
		"A1 A7 A2 A15 A7 A13 A1 A1 A1 A1 A18 A6 A2 A1 A8 A8 A40 A5 A5 A8 " .
        "A8 A9 A1 A42 A7 A4 A3 A1 A1 A3 A3 A3 A3 A3 A3 A3 " .
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
            $state = getProvince($lat, -$long);
            $id = "C" . $id;
        }
    }

print "unnormalized id = $id, icaoID = $icaoId, ";
	($id,$state,$country) = normalizeID($id,$state,$country,$icaoId, 1);
print "normalized id = $id\n";

	my $decl = 0;
	if ($magVar ne "")
	{
		my $ew = substr($magVar, -1);
		$decl = substr($magVar, 0, -1);
		if ($ew eq "E")
		{
			$decl = -$decl;
		}
	}

	if ($decl == 0)
	{
		$decl = getMagVar($lat, $long, $elev);
	}

	insertWaypoint($id, $datasource_key, $type, $name, $city,
					$state, $country, $lat, $long, $decl, $elev,
					$ctafFreq, Datasources::DATASOURCE_FAA, $isPublic, 0,
					undef);

#	if ($ctafFreq ne "")
#	{
#		insertCommunication($datasource_key,
#				"CTAF", "CTAF", $ctafFreq, Datasources::DATASOURCE_FAA,
#				undef);
#	}
	my @unicoms = unpack("A7 A7 A7 A7 A7 A7", $unicomFreqs);
	if ($unicoms[0] ne "")
	{
	  foreach my $freq (@unicoms)
	  {
		if (defined($freq) && $freq ne $ctafFreq)
		{
		  insertCommunication($datasource_key,
		  		"UNIC", "UNICOM", $freq, Datasources::DATASOURCE_FAA,
				undef);
		}
	  }
	}
	# Get the rest of them from the database.
	mergeInCommFreqs();

    if ($tph ne "")
    {
        my $tpa = $tph + $elev;
        insertTPA($datasource_key, $tpa);
    }

	return $datasource_key;
}

sub parseFAAAirportRunwayRecord($$)
{
	my ($currentKey, $line) = @_;

	my ($recordType, $datasource_key, $state, $rwyId, $rwyLen,
		$rwyWidth, $rwySurfaceType, $rwySurfaceTreat, $pcn, $rlei,
		$beId, $beTrueAlign, $beILSType, $beRightHandTraffic, $beRwyMarkings,
		$beRwyMarkingsCond, $beArrestingDevice, $beFormattedLat,
		$beSecondsLat, $beFormattedLong, $beSecondsLong, $beElev,
		$beThreshCrossingHeight, $beVisGlideAngle, $bedtFormattedLat,
		$bedtSecondsLat, $bedtFormattedLong, $bedtSecondsLong, $bedtElev,
		$bedtDist, $betzElev, $beVASI, $beRVR, $beRVV, $beApprLights,
		$beREIL, $beRCL, $beRETL, $beCOdesc, $beCOmarkedlighted, $beCOrwyCat,
		$beCOclncSlope, $beCOheight, $beCOdist, $beCOoffset, 
		$reId, $reTrueAlign, $reILSType, $reRightHandTraffic, $reRwyMarkings,
		$reRwyMarkingsCond, $reArrestingDevice, $reFormattedLat,
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
		$retzElevSrc, $retzElevSrcDate,
		$reTORA, $reTODA, $reACLTStop, $reLDA, $reLAHSODist, $reIntID,
		$reHSPId,
		$reLAHSOFormattedLat, $reLAHSOSecondsLat,
		$reLAHSOFormattedLong, $reLAHSOSecondsLong,
		$reLAHSOLatLongSrc, $reLAHSOLatLongSrcDate) =
		unpack("A3 A11 A2 A7 A5 A4 A12 A5 A11 A5 " .
		"A3 A3 A10 A1 A5 A1 A6 A15 A12 A15 A12 A7 A3 A4 A15 A12 A15 A12 A7" .
		"A4 A7 A5 A3 A1 A8 A1 A1 A1 A11 A4 A5 A2 A5 A5 A7" . 
		"A3 A3 A10 A1 A5 A1 A6 A15 A12 A15 A12 A7 A3 A4 A15 A12 A15 A12 A7" .
		"A4 A7 A5 A3 A1 A8 A1 A1 A1 A11 A4 A5 A2 A5 A5 A7" . 
		"A16 A10 " .
		"A6 A6 A6 A6 " .
		"A5 A4 A16 A10 A16 A10 A16 A10 A16 A10 A16 A10 " .
		"A5 A5 A5 A5 A5 A5 A7 A40 A15 A12 A15 A12 A16 A10 ".
		"A5 A4 A16 A10 A16 A10 A16 A10 A16 A10 A16 A10 A16 A10".
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

	insertRunway($datasource_key, $rwyId, $rwyLen, $rwyWidth, $rwySurfaceType,
		0,
        $b_lat, $b_long, $beTrueAlign, $beElev,
        $e_lat, $e_long, $reTrueAlign, $reElev,
        Datasources::DATASOURCE_FAA, 0);
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

    my $fh = new IO::File($fn) or die "Airport file $fn not found";

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
}

sub parseFAANavaidNAV1($)
{
	my ($line) = @_;

	my ($recordType, $id, $type, $officialId, $effDate, $name, $city,
		$cityStateName, $cityState, $faaRegion, $country, $countryCode,
		$ownerName, $operatorName, $commonSystemUsage, $publicUse, $class,
		$hours, $artcc, $formattedLat, $secondsLat, $formattedLong,
		$secondsLong, $surveyAcc, $tacanFormattedLat, $tacanSecondsLat,
		$tacanFormattedLong, $tacanSecondsLong, $elev, $magVar,
		$magVarEpoch, $simultaneousVoice, $power, $avif,
		$monitoringCategory, $radioVoiceCallName, $tacanChannel, $freq,
		$beaconMorse, $fanMarkerType, $fanMarkerBearing, $protectedFreq,
		$lowInHigh, $zMarker, $twebHours, $twebPhone,
		$fssId, $fssName, $fssHours,
		$notamCode, $quadId, $navaidStatus,
		$pitchFlag, $catchFlag, $suaFlag) = unpack("A4 A4 A20 A4 A10" .
		"A26 A26 A20 A2 A3 A20 A2 A50 A50 A1 A1 A11 A9 A20 A14 A11 A14" .
		"A11 A1 A14 A11 A14 A11 A5 A5 A4 A3 A4 A3 A1 A24 A4 A6 A24 A10" .
		"A3 A1 A3 A3 A9 A20 A4 A26 A100 A4 A16 A30 A1 A1 A1", $line);
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
		$elev = 0;
	}

	my $decl = 0;
	if ($magVar ne "")
	{
		my $ew = substr($magVar, -1);
		$decl = substr($magVar, 0, -1);
		if ($ew eq "E")
		{
			$decl = -$decl;
		}
	}

	if ($decl == 0)
	{
		$decl = getMagVar($lat, $long, $elev);
	}

	if ($country eq 'CA')
	{
		$cityState = getProvince($lat, -$long);
	}

	my $datasource_key = generateDSKey($id, "FAA", $type, $cityState,
        $country, $lat, $long);

	if ($city eq $name)
	{
		$city = "";
	}

	insertWaypoint($id, $datasource_key, $type, $name, $city,
					$cityState, $country, $lat, $long, $decl, $elev,
					$freq, Datasources::DATASOURCE_FAA,
					($publicUse ne "N") ? 1 : 0, 0, undef);

	return $datasource_key;
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
    my $fh = new IO::File($fn) or die "Navaid file $fn not found";

	my $currentKey;
    while (<$fh>)
    {
        chomp;

		my $recordType = unpack("A4", $_);

		if ($recordType eq "NAV1")
		{
			$currentKey = parseFAANavaidNAV1($_);
		}
		elsif ($recordType eq "NAV2")
		{
			parseFAANavaidNAV2($currentKey, $_);
		}
		elsif ($recordType eq "NAV3")
		{
			parseFAANavaidNAV3($currentKey, $_);
		}
		elsif ($recordType eq "NAV4")
		{
			parseFAANavaidNAV4($currentKey, $_);
		}
		elsif ($recordType eq "NAV5")
		{
			parseFAANavaidNAV4($currentKey, $_);
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
		unpack("A4 A4 A10 A11 A3 A20 A2 A26 A42 A14 A11 A14 A11 A4" .
		"A26 A12 A2 A3 A4 A42 A15 A42 A26 A20 A25 A2 A3 A14 A11 A14 A11 " .
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
	insertCommunicationImmediately($datasource_key, $freq_type,
        $frequency, $section, Datasources::DATASOURCE_FAA, undef);
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
	unpack("A4 A4 A44 A50 A11 A4 A3 A20 A2 A26 A42" .
		"A14 A11 A14 A11 A4 A26 A11 A3 A20 A2 A26 A42 A60", $line);

	fiddleCommId($satDatasource_key, $satFreqUse, $satFreq,
		$longSatFreq);
}

sub read_FAA_Comm($)
{
    my ($fn) = @_;
    my $fh = new IO::File($fn) or die "Comm file $fn not found";

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
    my $fh = new IO::File($fn) or die "AWOS file $fn not found";

    while (<$fh>)
    {
        chomp;
		my ($stationID, $stationType, $commissioningStatus,
			$stationLat, $stationLong, $stationFreq, $secondFreq,
			$stationTelephone, $datasource_key, $stationCity,
			$stationState, $effDate) =
			unpack("A4 A6 A1 A14 A15 A7 A7 A14 A11 A40 A2 A10", $_);

		next if ($datasource_key eq "");

		if ($stationFreq ne "")
		{
		  insertCommunicationImmediately($datasource_key, "AWOS",
			  $stationFreq, $stationType, Datasources::DATASOURCE_FAA,
			  undef);
		}

		if ($secondFreq ne "")
		{
		  insertCommunicationImmediately($datasource_key, "AWOS",
			  $secondFreq, $stationType, Datasources::DATASOURCE_FAA,
			  undef);
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

	if ($nsew eq "S" || $nsew eq "E")
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
		$state = getProvince($lat, -$long);
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
	  foreach $key (keys(%DBLoad::states))
	  {
		  #print "checking DBLoad::states{$key} = " .
		  #$DBLoad::states{$key}->{"name"} . "\n";
		  if ($DBLoad::states{$key}->{"name"} eq $state_name)
		  {
print "state $key equals\n";
			  $state = $DBLoad::states{$key}->{"code"};
			  $country = "US";
			  last;
		  }
	  }
	  if ($state eq "")
	  {
print "DESPERATION TIME!\n";
		$state = "";
		$country = "US";
	  }
	}
print "returning ($state, $country)\n";
	return ($state, $country);
}

sub read_FAA_Waypoints($)
{
    my ($fn) = @_;
    my $fh = new IO::File($fn) or die "Waypoint file $fn not found";

	my $state_code = "";
	my $old_stateName = "";
	my $newCountry = "";
	my $oldCountry = "";
    while (<$fh>)
    {
        chomp;
		my ($name, $stateName, $lat, $long, $fixCat, $chart1, $chart2,
			$chart3, $chart4, $chart5, $chart6, $chart7, $chart8, $chart9,
			$chart10, $loc1, $loc2, $loc3, $loc4, $ils1, $ils2, $fixLat,
			$fixLong, $fixDist, $obsId, $prevName, $chartingInfo,
			$published, $fixUse, $id, $artcc, $country, $remarks,
			$pitchFlag, $catchFlag, $suaFlag) =
			unpack("A30 A20 A14 A14 A3 A22 A22 A22 A22 A22 A22 A22 A22" .
			"A22 A22 A22 A22 A22 A22 A22 A22 A25 A25 A25 A5 A33 A38 A1 " .
			"A15 A5 A3 A20 A800 A1 A1 A1", $_);

		# Skip the ones with no category
		next if ($fixCat eq "");

		# Skip the ones that are colocated with a navaid.
		if ($loc1 =~ /\*\/0\s*$/)
		{
		  print "skipping colocated waypoint $name, $id\n"; $| = 1;
		  next;
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

		# Fix the name.  If the current name consists of nothing but the ident,
		# or the ident followed by some stuff in brackets (which seems to
		# always just by the ident/radial/distance) or just the bracketed
		# stuff, then we replace it.
		if ($name eq "")
		{
			$name = $id;
		}
		if ($loc1 ne "")
		{
            my $mloc1 = $loc1;
			$mloc1 =~ s#\*[A-Z][A-Z]?\*([^/]*/)# R$1D#;
			$name .= " ($mloc1)";
		}

		my $decl = getMagVar($lat, $long, 0);

        my $dskey = generateDSKey($id, "FAA", $fixUse, $state_code,
            $newCountry, $lat, $long);

        my $chart_map = 0;
        my $cc;
        foreach $cc (($chart1, $chart2, $chart3, $chart4, $chart5,
                    $chart6, $chart7, $chart8, $chart9, $chart10))
        {
            next if ($cc eq "");

            my $local_cmap = $FAA_chart_codes{$cc};
            if (!defined($local_cmap))
            {
                print "Unknown map code $cc\n";
            }
            $chart_map |= $local_cmap;
        }
        insertWaypoint($id, $dskey, $fixUse, $name, "",
						$state_code, $newCountry, $lat, $long, $decl, 0, "",
						Datasources::DATASOURCE_FAA, 1, $chart_map, undef);

        foreach my $st (($loc1, $loc2, $loc3, $loc4, $ils1, $ils2))
        {
            next if ($st eq "");

            FAA_FIX_code($id, $dskey, $st);
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
    if (defined($bear) && ($bear eq "" || $bear =~ /CRS/))
    {
        $bear = undef;
    }
    if (defined($dist))
    {
        if ($dist eq "")
        {
            $dist = undef;
        }
        else
        {
            $dist += 0.5;
        }
    }
    #print "id = $id, fixCode = $fixCode";
    #print ", navaid = $navaid";
    #print ", code = ", (defined($nc) ? "$code/$nc" : "undef/undef");
    #print ", bearing/distance = ", (defined($beardist) ? $beardist : "undef");
    #print ", bearing = ", (defined($bear) ? $bear : "undef");
    #print ", distance = ", (defined($dist) ? $dist : "undef");
    #print "\n";
    insertFix($id, $datasource_key, Datasources::DATASOURCE_FAA,
        $navaid, $code, $bear, $dist, 0);
}

sub delete_DAFIF_data()
{
	deleteWaypointData(Datasources::DATASOURCE_DAFIF,1);
}

sub read_DAFIF_Airports($)
{
    my ($arpt_dir) = @_;

    my $afn = $arpt_dir . "/ARPT.TXT";
    my $cfn = $arpt_dir . "/ACOM.TXT";
    my $rfn = $arpt_dir . "/RWY.TXT";

    my $afh = new IO::File($afn) or die "DAFIF airport file $afn not found";

    my $cfh = new IO::File($cfn) or die "DAFIF comm file $cfn not found";
    my %comm_rec;

    my $rfh = new IO::File($rfn) or die "DAFIF runway file $rfn not found";
    my %rwy_rec;

    #   Get rid of the first line
    <$afh>;
    <$cfh>;
    <$rfh>;
    readACOM($cfh, \%comm_rec);
    readRWY($rfh, \%rwy_rec);

    while (<$afh>)
    {
        chomp;

        my ($datasource_key, $name, $state_prov, $icao, $faa_host_id,
            $loc_hdatum, $wgs_datum, $wgs_lat, $lat, $wgs_long, $long,
            $elev, $type, $mag_var, $wac, $beacon, $second_arpt, $opr_agy,
            $sec_name, $sec_icao, $sec_faa, $sec_opr_agy, $cycle_date,
            $terrain, $hydro) =
                split("\t", $_);

		# XXX kludge for strange duplication in DAFIF data
		#next if    ($datasource_key eq "BF00002" ||
		#			$datasource_key eq 'BF00004');

        #   Parse the mag_var field
		my $decl = parseMagVar($mag_var);

        my $country = substr($datasource_key, 0, 2);

        my $state = getStateProvince($state_prov, $country, $lat, $long);

        $long = 0 - $long;

        my $id = $icao;
        my $didInsert = 0;
        if (length($id) < 4)
        {
            $id = $faa_host_id;
            # I have no idea what's going on with these airports with no IDs.
            next if ($id eq "N");
			if ($country eq "US")
			{
				($id,$state,$country) =
					normalizeID($id, $state, $country, undef, 1);
			}

            $didInsert = insertWaypoint($id, $datasource_key,
                            'AIRPORT', $name, "", $state, $country, $lat,
                            $long, $decl, $elev, "",
							Datasources::DATASOURCE_DAFIF,
                            $opr_agy ne "PV", 0, undef);
        }
        else
        {
            $didInsert = updateWaypoint($faa_host_id, $id,
                            $datasource_key, 'AIRPORT', $name, "", $state,
                            $country, $lat, $long, $decl, $elev, "",
							Datasources::DATASOURCE_DAFIF,
                            $opr_agy ne "PV");
        }

        if ($didInsert)
        {
            insertACOM($datasource_key, $cfh, \%comm_rec);
            insertRWY($datasource_key, $rfh, \%rwy_rec);
        }

        if ($second_arpt ne "")
        {
            my $id = $sec_icao;
            if (length($id) < 4)
            {
                $id = $sec_faa;
                # I have no idea what's going on with these airports with no
                # IDs.
                next if ($id eq "N");
				if ($country eq "US")
				{
					($id,$state,$country) = normalizeID($id, $state,
							$country, undef, 1);
				}

                insertWaypoint($id, $datasource_key, 'AIRPORT',
                                $sec_name, "", $state, $country, $lat, $long,
                                $decl, $elev, "",
								Datasources::DATASOURCE_DAFIF, 
                                $sec_opr_agy ne "PV", 0, undef);

            }
            else
            {
                updateWaypoint($faa_host_id, $id, $datasource_key,
                                'AIRPORT', $sec_name, "", $state, $country,
                                $lat, $long, $decl, $elev, "",
								Datasources::DATASOURCE_DAFIF, 
                                $sec_opr_agy ne "PV");
            }
        }
    }
    undef $afh;
}

sub read_DAFIF_Heliports($)
{
    my ($hlpt_dir) = @_;

    my $afn = $hlpt_dir . "/HLPT.TXT";
    my $cfn = $hlpt_dir . "/HCOM.TXT";

    my $afh = new IO::File($afn) or die "DAFIF heliport file $afn not found";

    my $cfh = new IO::File($cfn) or die "DAFIF heliport comm file $cfn not found";
    my %comm_rec;

    #   Get rid of the first line
    <$afh>;
    <$cfh>;
    readHCOM($cfh, \%comm_rec);

    while (<$afh>)
    {
        chomp;

        my ($datasource_key, $name, $state_prov, $icao, $faa_host_id,
            $loc_hdatum, $wgs_datum, $wgs_lat, $lat, $wgs_long, $long,
            $elev, $type, $mag_var, $wac, $beacon, $cycle_date) =
                split("\t", $_);

        #   Parse the mag_var field
		my $decl = parseMagVar($mag_var);

        my $country = substr($datasource_key, 0, 2);

        my $state = getStateProvince($state_prov, $country, $lat, $long);

        $long = 0 - $long;

        my $id = $icao;
        my $didInsert = 0;
        if (length($id) < 4)
        {
            $id = $faa_host_id;
            # I have no idea what's going on with these airports with no IDs.
            next if ($id eq "N");
			if ($country eq "US")
			{
				($id,$state,$country) =
					normalizeID($id, $state, $country, undef, 1);
			}

            $didInsert = insertWaypoint($id, $datasource_key,
                            'HELIPORT', $name, "", $state, $country, $lat,
                            $long, $decl, $elev, "",
							Datasources::DATASOURCE_DAFIF, 1, 0, undef);
        }
        else
        {
            $didInsert = updateWaypoint($faa_host_id, $id,
                            $datasource_key, 'HELIPORT', $name, "", $state,
                            $country, $lat, $long, $decl, $elev, "",
							Datasources::DATASOURCE_DAFIF, 1);
        }

        if ($didInsert)
        {
            insertHCOM($datasource_key, $cfh, \%comm_rec);
        }
    }
    undef $afh;
    undef $cfh;
}

sub read_DAFIF_Navaids($)
{
    my ($nav_dir) = @_;

    my $nfn = $nav_dir . "/NAV.TXT";

    my $nfh = new IO::File($nfn) or die "DAFIF navaid file $nfn not found";

    #   Get rid of the first line
    <$nfh>;

    while (<$nfh>)
    {
        chomp;

        my ($ident, $type, $cc, $nav_key_code, $state_prov,
            $name, $icao, $wac, $freq, $usage_code, $chan,
            $rcc, $freq_prot, $power, $nav_range, $loc_hdatum, $wgs_datum,
            $wgs_lat, $lat, $wgs_long, $long, $slaved_var, $mag_var,
            $elev, $dme_wgs_lat, $dme_wgs_dlat, $dme_wgs_long, $dme_wgs_dlong,
            $dme_elev, $arpt_icao, $os, $cycle_date) =
                split("\t", $_);

        #   Parse the mag_var field
		my $decl = parseMagVar($mag_var);

        #   Parse the frequency field
		my $frequency = "";
		if ($freq ne "")
		{
			my $freqtype = substr($freq, -1, 1);
			my $freqfrac = substr($freq, -4, 3);
			if (length($freq) > 4)
			{
				my $freqint = substr($freq, -8, 4);
				$frequency = $freqint;
				if ($freqtype eq "M")
				{
					$frequency .= "." . substr($freqfrac, 0, 2);
				}
			}
		}

        my $country = $cc;

        my $state = getStateProvince($state_prov, $country, $lat, $long);

        $long = 0 - $long;

		if ($elev eq "U")
		{
			$elev = 0;
		}
        $type = $DAFIF_navaid_types{$type};
        my $dsKey = generateDSKey($ident, "DAFIF", $type, $state,
                        $country, $lat, $long);
        insertWaypoint($ident, $dsKey,
						$type,
                        $name, "", $state, $country, $lat,
                        $long, $decl, $elev, $frequency,
						Datasources::DATASOURCE_DAFIF, 1, 0, undef);

    }
    undef $nfh;
}

sub read_DAFIF_Waypoints($)
{
    my ($wpt_dir) = @_;

    my $wfn = $wpt_dir . "/WPT.TXT";

    my $wfh = new IO::File($wfn) or die "DAFIF waypoint file $wfn not found";

    #   Get rid of the first line
    <$wfh>;

    while (<$wfh>)
    {
        chomp;

        my ($ident, $cc, $state_prov, $wpt_nav_flag, $type, $name, $icao,
			$usage_cd, $bearing, $distance, $wac, $loc_hdatum, $wgs_datum,
			$wgs_lat, $lat, $wgs_long, $long, $mag_var, $nav_ident, $nav_type,
			$nav_ctry, $nav_key_cd, $cycle_date, $wpt_rvsm, $rwy_id,
            $rwy_ica) =
                split("\t", $_);

		#	Skip co-located waypoints
		next if ($wpt_nav_flag eq "Y");

		#	Skip NDB waypoints
		next if ($type eq "NR" || $type eq "NF");

		#	Translate the type
		my $trans_type = $DAFIF_waypoint_types{$type};
		if (!defined($trans_type))
		{
			print "Untranslated type in DAFIF waypoints: $type\n";
			next;
		}

        # Set the chart map
        my $chart_map = 0;
        if ($type eq "V")
        {
            $chart_map = WaypointTypes::WPTYPE_VFR;
        }
        else
        {
            $chart_map = $DAFIF_use_codes{$usage_cd};
            if (!defined($chart_map))
            {
                print "Untranslated use_code in DAFIF waypoints: $usage_cd\n";
                exit;
            }
        }

        #   Parse the mag_var field
		my $decl = parseMagVar($mag_var);

        my $country = $cc;

        my $state = getStateProvince($state_prov, $country, $lat, $long);

        $long = 0 - $long;

		# Fix the name.  If we have a nav ident, and the current name consists
		# of nothing by the ident, or the ident followed by some stuff in
		# brackets (which seems to always just by the ident/radial/distance)
		# or just the bracketed stuff, then we replace it.
		if ($nav_ident ne "")
		{
			$name =~ s/\s*\(.*\)\s*$//;
			$name =~ s?\s*\(*$nav_ident\s*[0-9\.]+/[0-9\.]+\)*??;
			$name =~ s/^\s+//;
			if ($name eq '')
			{
				$name = $ident;
			}
			$name .= " ($nav_ident R$bearing/D$distance)";
		}

        my $dsKey = generateDSKey($ident, "DAFIF", $trans_type, $state,
                        $country, $lat, $long);
        insertWaypoint($ident, $dsKey,
						$trans_type,
                        $name, "", $state, $country, $lat,
                        $long, $decl, 0, "",
						Datasources::DATASOURCE_DAFIF, 1, $chart_map, undef);
    }
    undef $wfh;
}

#	Load the categories
#loadCategories();

#   DAFIF needs a list of country codes and state codes;
DBLoad::getStates();


my $faadir = shift;
my $DAFIFdir = shift;

if ($faadir ne "NO")
{
	print "deleting FAA data\n";
	delete_FAA_data();

	print "loading FAA comm freqs\n";
	read_FAA_Comm($faadir . "/TWR.txt");
	print "loading FAA AWOS freqs\n";
	read_FAA_AWOS($faadir . "/AWOS.txt");
	print "loading FAA airports\n";
	read_FAA_Airports($faadir . "/APT.txt");
	print "loading FAA navaids\n";
	read_FAA_Navaids($faadir . "/NAV.txt");
	print "loading FAA waypoints\n";
	read_FAA_Waypoints($faadir . "/FIX.txt");

	updateDatasourceExtents(Datasources::DATASOURCE_FAA,1);
}
else
{
	print "loading FAA ids\n";
	loadIDs(Datasources::DATASOURCE_FAA);
}

if ($DAFIFdir ne "NO")
{
	print "deleting DAFIF data\n";
	delete_DAFIF_data();

	my $DAFIFarptdir = $DAFIFdir . "/ARPT";
	my $DAFIFhlptdir = $DAFIFdir . "/HLPT";
	my $DAFIFnavdir = $DAFIFdir . "/NAV";
	my $DAFIFwptdir = $DAFIFdir . "/WPT";
	print "loading DAFIF airports\n";
	read_DAFIF_Airports($DAFIFarptdir);
	print "loading DAFIF heliports\n";
	read_DAFIF_Heliports($DAFIFhlptdir);
	print "loading DAFIF navaids\n";
	read_DAFIF_Navaids($DAFIFnavdir);
	print "loading DAFIF waypoints\n";
	read_DAFIF_Waypoints($DAFIFwptdir);

	updateDatasourceExtents(Datasources::DATASOURCE_DAFIF,1);
}
#else
#{
#	print "loading DAFIF ids\n";
#	loadIDs(Datasources::DATASOURCE_DAFIF);
#}

print "Done loading\n";

post_load();

finish();
