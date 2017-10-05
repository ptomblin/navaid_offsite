#!/usr/bin/perl -w
#File CreateGPSPilotDB.pl
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
use GPSPilot::Points;
use Getopt::Long;
use CreateDB;
use Encode;

# Parameters
my $pgm = "GPSPilot";
my $aptname = "waypointAPT.pdb";
my $navname = "waypointNAV.pdb";
my $logfile = "waypoint.log";
my $dbname = "GPSPilot";
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
my $runway = 0;
my $charts = 0;
my $metric = 0;

GetOptions(
			"aptname=s" => \$aptname,
			"navname=s" => \$navname,
			"logname=s" => \$logfile,
			"dbname=s" => \$dbname,
            "all!" => \$all,
            "country=s@" => \@countries,
            "state=s@" => \@states,
            "province=s@" => \@provinces,
            "type=s@" => \@types,
            "note=s@" => \@notes,
            "private!" => \$private,
            "public!" => \$public,
            "max_lat=f" => \$max_lat,
            "min_lat=f" => \$min_lat,
            "max_long=f" => \$max_long,
            "min_long=f" => \$min_long,
            "runway=i" => \$runway,
            "charts=i" => \$charts,
            "metric!" => \$metric);

print "aptname = $aptname\n";
print "navname = $navname\n";
print "logname = $logfile\n";
print "dbname = $dbname\n";
print "all = $all\n";
print "private = $private\n";
print "public = $public\n";
print "countries = " . join(",",@countries) . "\n";
print "states = " . join(",",@states) . "\n";
print "provinces = " . join(",",@provinces) . "\n";
print "types = " . join(",",@types) . "\n";
print "notes = " . join(",",@notes) . "\n";
print "max_lat = $max_lat\n";
print "min_lat = $min_lat\n";
print "max_long = $max_long\n";
print "min_long = $min_long\n";

my $doType = 0;
my $doAddress = 0;
my $doNavFreq = 0;
my $doRunways = 0;
my $doMilFreq = 0;
my $doCommFreq = 0;
my $doTPA = 0;
if (scalar(@notes) < 1)
{
	$doAddress = 1;
}
foreach my $key (@notes)
{
	if ($key eq "type")
	{
		$doType = 1;
	}
	elsif ($key eq "address")
	{
		$doAddress = 1;
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
}

my %param = (
	"min_lat" => $min_lat,
	"max_lat" => $max_lat,
	"min_long" => $min_long,
	"max_long" => $max_long,
	"doRunways" => $doRunways,
	"doComm" => $doMilFreq||$doCommFreq);
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
print LOGFILE "$pgm 0\t0\t0";

my $maxDebug = 0;

my $rowInc = 100;

open(DEBUG,">>/www/navaid.com/tmp/CreateGPSPilotDB" . ($maxDebug?"_test":"") .
		".out");
if ($maxDebug)
{
    $ofh = select(DEBUG); $| = 1; select $ofh;
}

sub sigEndHandler
{
	my ($sig) = @_;

	# Get rid of the log file so that the app knows it failed.
	print LOGFILE "\nKILLED sig = $sig";
	#close(LOGFILE);
	#unlink($logfile);
}

$SIG{__DIE__} = \&sigEndHandler;

sub dbSourceCode($)
{
	# Don't do anything with the datasource info.
}

sub debugCode($)
{
	my $line = shift;
	if ($maxDebug)
	{
		print DEBUG $line;
	}
}


my $APTpdb = new GPSPilot::Points;
my $NAVpdb = new GPSPilot::Points;

print DEBUG "pdb open\n" if ($maxDebug);

$APTpdb->{name} = $dbname . " Airports";
$NAVpdb->{name} = $dbname . " Navaids";

my $numAPTs = 0;
my $numNAVs = 0;
my $maxRowNum = undef;

sub wayPointCode($)
{
    my ($record) = @_;

    if ($numAPTs > 32766 || $numNAVs > 32766)
    {
        print LOGFILE "\n$pgm TOOBIG\t$numAPTs\t$numNAVs";
        close LOGFILE;
        exit 1;
    }

	if (defined($record->{id}))
	{

		my $rownum = $record->{rownum};
		if (($rownum % $rowInc) == 0)
		{
			print LOGFILE "\n$pgm $rownum\t$numAPTs\t$numNAVs";
		}

		my $airport_type = ($record->{category} == 1);
		my $name = $record->{name};
        Encode::from_to($name, "utf8", "iso-8859-1", Encode::FB_WARN);
		my $notestr = "";
		if ($doAddress)
		{
			my $addressstr = $record->{address};
			my $state = $record->{state};
			if ($state)
			{
				$addressstr .= ($addressstr?",":"") . $state;
			}
			my $country = $record->{country};
			if ($country)
			{
				$addressstr .= ($addressstr?",":"") . $country;
			}
			if ($addressstr)
			{
				$addressstr .= "\n";
			}
            Encode::from_to($addressstr, "utf8", "iso-8859-1", Encode::FB_WARN);
			$notestr .= $addressstr;
		}
		if ($doType)
		{
			$notestr .= "Type:\t" . $record->{type} . "\n";
		}
        if ($doTPA && $airport_type && defined($record->{tpa}) &&
            $record->{tpa} ne "")
		{
            my $tpa = $record->{tpa};
            if ($metric)
            {
                $tpa = $tpa * .3048;
            }
			$notestr .= "TPA:\t$tpa\n";
		}
		if ($doNavFreq && !$airport_type &&
			defined($record->{main_frequency}) && $record->{main_frequency})
		{
			$notestr .= "Frequency:\t" . $record->{main_frequency} . "\n";
		}
		if (($doMilFreq || $doCommFreq) && $airport_type)
		{
			$notestr .= formatCommFreqs($record->{frequencies}, $doMilFreq,
					$doCommFreq);
		}

		print DEBUG "adding id = ", $record->{id}, ", name = $name\n" if ($maxDebug);

		if ($airport_type)
		{
			my $pdb_record = $APTpdb->addAirport(
				$record->{latitude},
				-$record->{longitude},
				$record->{declination},
				$record->{elevation},
				$record->{id},
				$name,
				$notestr);
			getRunways($APTpdb, $pdb_record, $record->{runways});
			$numAPTs++;
		}
		else
		{
			$NAVpdb->addNavaid(
				$record->{latitude},
				-$record->{longitude},
				$record->{declination},
				$record->{elevation},
				$record->{id},
				$name,
				$notestr);
			$numNAVs++;
		}
	}
	else
	{
        $maxRowNum = $record->{rownum};
	}
}

sub formatCommFreqs($$$)
{
    my ($commFreqRef, $mil, $nonmil) = @_;
    #my $retstring = "Frequencies:\nType Freq.      Name\n";
    my $retstring = "Frequencies:\n";
    my $found = 0;

    foreach my $rowRef (@{$commFreqRef})
    {
		my $comm_type = $rowRef->{type};
		my $frequency = $rowRef->{frequency};

        my ($numFreq, $suffix) = ($frequency =~ m/^([0-9\.]*)([A-Z]*)$/);
        my $milfreq = ($numFreq ne "" && ($numFreq < 108.0 || $numFreq > 137.0) &&
                ($suffix eq "" || $suffix eq "M"));
        if (($mil && $milfreq) || ($nonmil && !$milfreq))
        {
            $found = 1;
			my $thisStr = sprintf("%-4s %-8s\n",
				$comm_type, $frequency);
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


sub getRunways($$$)
{
    my ($APTpdb, $pdb_record, $runwaysRef) = @_;

    foreach my $rowRef (@{$runwaysRef})
    {
		my $runway_designation = $rowRef->{designation};
		my $b_lat = $rowRef->{b_lat};
		my $b_long = $rowRef->{b_long};
        if (defined($b_long))
        {
            $b_long = -$b_long;
        }
		my $e_lat = $rowRef->{e_lat};
		my $e_long = $rowRef->{e_long};
        if (defined($e_long))
        {
            $e_long = -$e_long;
        }
		if ($b_lat && $b_long && $e_lat && $e_long)
		{
			$APTpdb->addRunway($pdb_record, $runway_designation,
				$b_lat, $b_long,
				$e_lat, $e_long);
		}
    }
}

CreateDB::generate(\%param, \&wayPointCode, \&dbSourceCode, \&debugCode);

if (defined($maxRowNum))
{
    if ($numAPTs > 0)
    {
        $APTpdb->Write($aptname);
    }
    if ($numNAVs > 0)
    {
        $NAVpdb->Write($navname);
    }
    print LOGFILE "\n$pgm FINISHED ", $maxRowNum,
        "\t$numAPTs\t$numNAVs";
    close(LOGFILE);
}
else
{
	close(LOGFILE);
	unlink($logfile);
}

undef $APTpdb;
undef $NAVpdb;
