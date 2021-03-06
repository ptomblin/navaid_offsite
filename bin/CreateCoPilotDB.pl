#!/usr/bin/perl -w
#File CreateCoPilotDB.pl
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
use CoPilot::Waypoint;
use Getopt::Long;
use CreateDB;
use Encode;

# Parameters
my $pgm = "CoPilot";
my $url = "http://navaid.com/CoPilot/";
my $pdbfile = "waypoint.pdb";
my $logfile = "waypoint.log";
my $all = 0;
my @countries = ();
my @states = ();
my @provinces = ();
my @types = ();
my @notes = ();
my $max_lat = 91;
my $min_lat = -91;
my $max_long = 181;
my $min_long = -181;
my $private = 1;
my $public = 1;
my $metric = 0;
my $longCountry = 0;
my $version = 4;
my $runway = 0;
my $doAddOn = 0;
my $doAeroPalm = 0;
my $charts = 0;

my $latin1Encoder = find_encoding("iso-8859-15");
if (!defined($latin1Encoder))
{
    die "WTF?";
}

GetOptions(
	"pdbname=s" => \$pdbfile,
	"logname=s" => \$logfile,
    "all!" => \$all,
    "country=s@" => \@countries,
    "state=s@" => \@states,
    "province=s@" => \@provinces,
    "type=s@" => \@types,
    "note=s@" => \@notes,
    "private!" => \$private,
    "public!" => \$public,
    "metric!" => \$metric,
    "runway=i" => \$runway,
    "charts=i" => \$charts,
    "version=i" => \$version,
    "expandCountry!" => \$longCountry,
    "max_lat=f" => \$max_lat,
    "min_lat=f" => \$min_lat,
    "max_long=f" => \$max_long,
    "min_long=f" => \$min_long,
    "doAddOn!" => \$doAddOn,
    "doAeroPalm!" => \$doAeroPalm);

if ($doAeroPalm)
{
    $pgm = "AeroPalm";
    $url = "http://www.AeroPDA.com/";
}

print "pdbname = $pdbfile\n";
print "logname = $logfile\n";
print "all = $all\n";
print "private = $private\n";
print "public = $public\n";
print "metric = $metric\n";
print "version = $version\n";
print "expandCountry = $longCountry\n";
print "countries = " . join(",",@countries) . "\n";
print "states = " . join(",",@states) . "\n";
print "provinces = " . join(",",@provinces) . "\n";
print "types = " . join(",",@types) . "\n";
print "notes = " . join(",",@notes) . "\n";
print "max_lat = $max_lat\n";
print "min_lat = $min_lat\n";
print "max_long = $max_long\n";
print "min_long = $min_long\n";
print "runway = $runway\n";

my $doType = 0;
my $doNavFreq = 0;
my $doRunways = 0;
my $doMilFreq = 0;
my $doCommFreq = 0;
my $doTPA = 0;
my $doFix = 0;
foreach my $key (@notes)
{
	if ($key eq "type")
	{
		$doType = 1;
	}
	elsif ($key eq "navfrequency")
	{
		$doNavFreq = 1;
	}
	elsif ($key eq "runways")
	{
		$doRunways = 1;
	}
	elsif ($key eq "airfrequencymil")
	{
		$doMilFreq = 1;
	}
	elsif ($key eq "airfrequencynonmil")
	{
		$doCommFreq = 1;
	}
	elsif ($key eq "tpa")
	{
		$doTPA = 1;
	}
	elsif ($key eq "fixinfo")
	{
		$doFix = 1;
	}
}
print "doFix = $doFix\n";
print "doTPA = $doTPA\n";

my %param = (
	"min_lat" => $min_lat,
	"max_lat" => $max_lat,
	"min_long" => $min_long,
	"max_long" => $max_long,
	"doRunways" => $doRunways,
	"doComm" => $doMilFreq||$doCommFreq,
	"doTPA" => $doTPA,
	"doFix" => $doFix,
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

# 
open(LOGFILE, ">".$logfile);
my $ofh = select(LOGFILE); $| = 1; select $ofh;
print LOGFILE "$pgm 0";

my $maxDebug = 0;

my $rowInc = 100;
my $maxRowNum = undef;

my %ids;

open(DEBUG,">>/www/navaid.com/tmp/CreateCoPilotDB" . ($maxDebug?"_test":"") .
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

#   Generate a nice appinfo
my $appstr = 
		"Generated by NAVAID database generator at\n" .
		"$url\n\n";
sub doHeader()
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


my $pdb = new CoPilot::Waypoint;
$pdb->{version} = $version;
if ($doAeroPalm)
{
    $pdb->{name} = "AeroPalm Waypoint";
    $pdb->{creator} = "AP-P";
}
if ($doAddOn)
{
	$pdb->{type} = "swpu";
	$pdb->{name} = "AddOn";
}

print DEBUG "pdb open\n" if ($maxDebug);

sub wayPointCode($)
{
    my ($record) = @_;

    if ($record->{rownum} > 32766)
    {
        print LOGFILE "\n$pgm TOOBIG ", $record->{rownum};
        close LOGFILE;
        exit 1;
    }


	if (defined($record->{id}))
	{
        my $id = $record->{id};
        if (exists $ids{$id})
        {
            debugCode("Skipping duplicate ID $id\n");
            return 0;
        }
        $ids{$id} = $id;
		my $rownum = $record->{rownum};
		if (($rownum % $rowInc) == 0)
		{
			print LOGFILE "\n$pgm $rownum";
		}

		my $airport_type = ($record->{category} == 1);
		my $waypoint_type = ($record->{category} == 3);
		my $name = $record->{name};
		my $address = $record->{address};
		if ($address)
		{
			$name .= ", " . $address;
		}
		my $state = $record->{state};
		if ($state)
		{
			$name .= ", " . $state;
		}
		my $country = $record->{country};
		if (exists($record->{longCountry}))
		{
			$country = $record->{longCountry};
		}
		if ($country)
		{
			$name .= ", " . $country;
		}
        #$name = $latin1Encoder->encode($name);
        Encode::from_to($name, "utf8", "iso-8859-1", Encode::FB_WARN);

		my $notestr = "";
		if ($doType)
		{
			$notestr .= "Type:\t" . $record->{type} . "\n\n";
		}
        if ($doTPA && $airport_type && defined($record->{tpa}) &&
            $record->{tpa} ne "")
		{
			$notestr .= "TPA:\t" . feetToMetres($record->{tpa}) . "\n\n";
		}
		if ($doNavFreq && !$airport_type &&
			defined($record->{main_frequency}) && $record->{main_frequency})
		{
			$notestr .= "Frequency:\t" . $record->{main_frequency} . "\n\n";
		}
		if (($doMilFreq || $doCommFreq) && $airport_type)
		{
			$notestr .= formatCommFreqs($record->{frequencies}, $doMilFreq,
					$doCommFreq);
		}
		if ($doRunways && $airport_type)
		{
			$notestr .= formatRunways($record->{runways});
		}
        if ($doFix && $waypoint_type)
        {
            $notestr .= formatFix($record->{fixinfo});
        }

		print DEBUG "adding id = $id, name = $name\n" if ($maxDebug);

		$pdb->addWaypointWithID(
			$record->{pdb_id},
			$record->{latitude},
			-$record->{longitude},
			$record->{declination},
			$record->{elevation},
			$id,
			$name,
			$notestr,
			"");
	}
	else
	{
        $maxRowNum = $record->{rownum};
	}
    return 1;
}

sub formatCommFreqs($$$)
{
    my ($commFreqRef, $mil, $nonmil) = @_;
    my $retstring = "Frequencies:\nType Freq.      Name\n";
    my $found = 0;

    foreach my $rowRef (@{$commFreqRef})
    {
		my $comm_type = $rowRef->{type};
		my $frequency = $rowRef->{frequency};
		my $comm_name = $rowRef->{name};

        my ($numFreq, $suffix) = ($frequency =~ m/^([0-9\.]*)([A-Z]*)$/);
        my $milfreq = ($numFreq ne "" &&
                            ($numFreq < 108.0 || $numFreq > 137.0)) &&
                            ($suffix eq "" || $suffix eq "M");
        if (($mil && $milfreq) || ($nonmil && !$milfreq))
        {
            $found = 1;
			my $thisStr = sprintf("%-4s %-10s %s\n",
				$comm_type, $frequency, $comm_name);
            $retstring .= $thisStr;
        }
    }
    $retstring .= "\n";

    if ($found)
    {
        return $retstring;
    }
    return "";
}


sub feetToMetres($)
{
  my $feet = shift;
  if ($metric)
  {
	$feet = int($feet * .3048 + .5);
  }
  return $feet;
}

sub formatRunways($)
{
    my ($runwaysRef) = shift;
    my $retstring = "Runways:\nRunway   LxW       Surface\n";
    my $found = 0;

    foreach my $rowRef (@{$runwaysRef})
    {
		my $runway_designation = $rowRef->{designation};
		my $length = feetToMetres($rowRef->{length});
		my $width = feetToMetres($rowRef->{width});
		my $surface = $rowRef->{surface};

        $found = 1;
		my $thisStr = sprintf("%-8s %-9s %s\n",
				$runway_designation, $length . "x" . $width, $surface);
        $retstring .= $thisStr;
    }

    $retstring .= "\n";

    if ($found)
    {
        return $retstring;
    }
    return "";
}

sub formatFix($)
{
    my ($fixRef) = shift;

    my $retstring = "Fix Info:\nNavaid   Type      Radial     Distance\n";
    my $found = 0;

    foreach my $rowRef (@{$fixRef})
    {
		my $navaid = $rowRef->{navaid};
		my $type = $rowRef->{navaid_type};
		my $radial = $rowRef->{radial_bearing};
		my $distance = $rowRef->{distance};

        if (!defined($radial))
        {
            $radial = "";
        }
        if (!defined($distance))
        {
            $distance = "";
        }
        if (!defined($distance))
        {
            $distance = "";
        }

        $found = 1;
		my $thisStr = sprintf("%-8s %-9s %-10s %s\n",
				$navaid, $type, $radial, $distance);
        $retstring .= $thisStr;
    }
    $retstring .= "\n";

    if ($found)
    {
        return $retstring;
    }
    return "";
}

CreateDB::generate(\%param, \&wayPointCode, \&doHeader, \&debugCode);
$pdb->{appinfo}{infoString} = $appstr;

$pdb->Write($pdbfile);

if (defined($maxRowNum))
{
    print LOGFILE "\n$pgm FINISHED ", $maxRowNum, " ", $pdbfile ;
    close(LOGFILE);
}
else
{
	close(LOGFILE);
	unlink($logfile);
}

undef $pdb;
