#!/usr/bin/perl -w
#File CreateAeroCalc.pl
#
#	This file creates a waypoint db.  It's designed to run in the background,
#	spawned by Apache.
#
#   This file is copyright (c) 2001 by Paul Tomblin, and may be distributed
#   under the terms of the "Clarified Artistic License", which should be
#   bundled with this file.  If you receive this file without the Clarified
#   Artistic License, email ptomblin@xcski.com and I will mail you a copy.
#

BEGIN
{
    push @INC, "/www/navaid.com/perl";
}

use strict;
use Getopt::Long;
use CreateDB;
use Encode;

# Parameters
my $txtfile = "waypoint.txt";
my $logfile = "waypoint.log";
my $pgm = "AeroCalc";
my $all = 0;
my @countries = ();
my @states = ();
my @provinces = ();
my @types = ();
my $max_lat = 91;
my $min_lat = -91;
my $max_long = 181;
my $min_long = -181;
my $runway = 0;
my $metric = 0;
my $private = 1;
my $public = 1;
my $longCountry = 0;
my $charts = 0;

GetOptions(
			"txtname=s" => \$txtfile,
			"logname=s" => \$logfile,
            "country=s@" => \@countries,
            "state=s@" => \@states,
            "province=s@" => \@provinces,
            "type=s@" => \@types,
            "private!" => \$private,
            "public!" => \$public,
            "expandCountry!" => \$longCountry,
            "max_lat=f" => \$max_lat,
            "min_lat=f" => \$min_lat,
            "max_long=f" => \$max_long,
            "min_long=f" => \$min_long,
            "runway=i" => \$runway,
            "charts=i" => \$charts,
            "metric!" => \$metric);

print "txtname = $txtfile\n";
print "logname = $logfile\n";
print "all = $all\n";
print "private = $private\n";
print "public = $public\n";
print "expandCountry = $longCountry\n";
print "countries = " . join(",",@countries) . "\n";
print "states = " . join(",",@states) . "\n";
print "provinces = " . join(",",@provinces) . "\n";
print "types = " . join(",",@types) . "\n";
print "max_lat = $max_lat\n";
print "min_lat = $min_lat\n";
print "max_long = $max_long\n";
print "min_long = $min_long\n";

my %param = (
	"min_lat" => $min_lat,
	"max_lat" => $max_lat,
	"min_long" => $min_long,
	"max_long" => $max_long,
	"doRunways" => 0,
	"doComm" => 0,
	"longCountry" => $longCountry);
if (scalar(@countries) > 0)
{
	$param{countries} = \@countries;
}
if (scalar(@states) > 0)
{
	$param{states} = \@states;
}
if (scalar(@provinces) > 0)
{
	$param{provinces} = \@provinces;
}
if ($private && !$public)
{
	$param{privacy} = 1;
}
elsif (!$private && $public)
{
	$param{privacy} = 0;
}
else
{
    $param{privacy} = 2;
}

if (scalar(@types) > 0)
{
	$param{types} = \@types;
}
if ($runway > 0)
{
    if ($metric)
    {
        $runway = $runway / 0.3048;
    }
    $param{minRunwayLength} = $runway;
}

if ($charts > 0)
{
    $param{charts} = $charts;
}

# XXX Maybe do some error checking.

my %typeMap = (
	"AIRPORT"		=>	1,
	"AWY-INTXN"		=>	6,
	"BALLOONPORT"	=>	2,
	"CNF"			=>	6,
	"COORDN-FIX"	=>	6,
	"DME"			=>	9,
	"FAN MARKER"	=>	9,
	"GLIDERPORT"	=>	1,
	"GPS-WP"		=>	6,
	"HELIPORT"		=>	1,
	"MARINE NDB"	=>	4,
	"MIL-REP-PT"	=>	6,
	"MIL-WAYPOINT"	=>	6,
	"NDB"			=>	4,
	"NDB/DME"		=>	4,
	"PLATFORM"		=>	2,
	"REP-PT"		=>	5,
	"RNAV-WP"		=>	6,
	"SEAPLANE BASE"	=>	1,
	"STOLPORT"		=>	1,
	"TACAN"			=>	3,
	"TVOR"			=>	3,
	"TVOR/DME"		=>	3,
	"UHF/NDB"		=>	4,
	"ULTRALIGHT"	=>	2,
	"UNSPECIFIED NAVAID" =>	3,
	"VFR-WP"		=>	5,
	"VOR"			=>	3,
	"VOR/DME"		=>	3,
	"VOR/TACAN"		=>	3,
	"VORTAC"		=>	3,
	"VOT"			=>	3,
	"WAYPOINT"		=>	5
);

# 
open(LOGFILE, ">".$logfile);
my $ofh = select(LOGFILE); $| = 1; select $ofh;
print LOGFILE "$pgm 0";

my $maxDebug = 0;

my $rowInc = 100;

open(DEBUG, ">>/www/navaid.com/tmp/CreateAeroCalc" . ($maxDebug?"_test":"") .
		".out");
if ($maxDebug)
{
    $ofh = select(DEBUG); $| = 1; select $ofh;
}

sub sigEndHandler
{
	my ($sig) = @_;

	# Get rid of the log file so that the app knows it failed.
	close(LOGFILE);
	unlink($logfile);
}

open(TXT, ">$txtfile");
=pod
print TXT (<<EOF);
#
# Navaid Waypoint Generator for AeroCalc - http://navaid.com/AeroCalc/
#
# AeroCalc comes from http://www.2flyeasy.com/
#
# Waypoint generator by Paul Tomblin, ptomblin\@xcski.com
EOF
=cut
print DEBUG "txt open\n" if ($maxDebug);


sub dbSourceCode()
{
}

sub debugCode($)
{
	my $line = shift;
	if ($maxDebug)
	{
		print DEBUG $line;
	}
}

sub trunc($$)
{
	my ($str, $len) = @_;
	if (length($str) > $len)
	{
		$str = substr($str, 0, $len);
	}
	return $str;
}

sub convLatLong($$$)
{
	my ($posnegStr, $lendeg, $decdeg) = @_;

	my $firstChar = substr($posnegStr, (($decdeg < 0)?1:0), 1);

	$decdeg = abs($decdeg);

	my $intdeg = int($decdeg);
	my $min = ($decdeg - $intdeg) * 60;
	my $intmin = int($min);
	my $sec = ($min - $intmin) * 60;
	my $intsec = int($sec * 100 + 0.5);

	my $format = "%s%0" . $lendeg . "d%02d%04d";
	my $retstr = sprintf($format, $firstChar, $intdeg, $intmin, $intsec);
	return $retstr;
}

sub wayPointCode($)
{
    my ($record) = @_;
	if (defined($record->{id}))
	{
		my $rownum = $record->{rownum};
		if (($rownum % $rowInc) == 0)
		{
			print LOGFILE "\n$pgm $rownum";
		}

		my $id = trunc($record->{id}, 5);
		my $typestr = $record->{type};
		my $typenum = $typeMap{$typestr};
		if (!defined($typenum))
		{
			debugCode("couldn't map type $typestr\n");
		}

		my $name = $record->{name};
		my $address = $record->{address};
		if ($address)
		{
			$name .= "," . $address;
		}
		my $state = $record->{state};
		if ($state)
		{
			$name .= "," . $state;
		}
		my $country = $record->{country};
		if (exists($record->{longCountry}))
		{
			$country = $record->{longCountry};
		}
		if ($country)
		{
			$name .= "," . $country;
		}
        Encode::from_to($name, "utf8", "iso-8859-1", Encode::FB_WARN);
		$name = trunc($name, 30);

		my $lat = convLatLong("NS", 2, $record->{latitude});
		my $lon = convLatLong("EW", 3, $record->{longitude});
		print TXT "$id;$typenum;$name;$lat;$lon\r\n";

		print DEBUG "adding id = ", $id, ", name = $name\n" if ($maxDebug);
	}
	else
	{
		print LOGFILE "\n$pgm FINISHED ", $record->{rownum};
	}
    return 1;
}

CreateDB::generate(\%param, \&wayPointCode, \&dbSourceCode, \&debugCode);


#print LOGFILE "\nFINISHED $rownum";

close(LOGFILE);
close(TXT);

