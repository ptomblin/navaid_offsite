#!/usr/bin/perl -w
#File CreateGPX.pl
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

# Parameters
my $pgm = "GPX";
my $xmlfile = "waypoint.gpx";
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
my $longCountry = 0;
my $metric = 0;
my $runway = 0;
my $charts = 0;
my $doExtension = 0;

GetOptions(
			"gpxname=s" => \$xmlfile,
			"logname=s" => \$logfile,
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
            "expandCountry!" => \$longCountry,
            "max_lat=f" => \$max_lat,
            "min_lat=f" => \$min_lat,
            "max_long=f" => \$max_long,
            "min_long=f" => \$min_long,
            "extension!" => \$doExtension);

print "gpxname = $xmlfile\n";
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

my $doNavFreq = 0;
my $doRunways = 0;
my $doMilFreq = 0;
my $doCommFreq = 0;
my $doTPA = 0;
my $doFix = 0;

foreach my $key (@notes)
{
	if ($key eq "navfrequency")
	{
		$doNavFreq = 1;
        $doExtension = 1;
	}
	elsif ($key eq "runways")
	{
		$doRunways = 1;
        $doExtension = 1;
	}
	elsif ($key eq "airfrequencymil")
	{
		$doMilFreq = 1;
        $doExtension = 1;
	}
	elsif ($key eq "airfrequencynonmil")
	{
		$doCommFreq = 1;
        $doExtension = 1;
	}
	elsif ($key eq "tpa")
	{
		$doTPA = 1;
        $doExtension = 1;
	}
	elsif ($key eq "fixinfo")
	{
		$doFix = 1;
        $doExtension = 1;
	}
}

my %param = (
	"min_lat" => $min_lat,
	"max_lat" => $max_lat,
	"min_long" => $min_long,
	"max_long" => $max_long,
	"doRunways" => $doRunways && $doExtension,
	"doComm" => ($doMilFreq||$doCommFreq) && $doExtension,
	"doTPA" => $doTPA && $doExtension,
	"doFix" => $doFix && $doExtension,
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

open(DEBUG,">>/www/navaid.com/tmp/CreateGPX" . ($maxDebug?"_test":"") .
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

sub normalizeDegrees($)
{
    my $deg = shift;

    # Modulo 360
    $deg *= 10;
    $deg %= 3600;

    return sprintf("%.1f", $deg/10.0);
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

sub wrapDegrees($$$$)
{
    my ($deg, $maxDeg, $minDeg, $nDec) = @_;
    my $range = $maxDeg - $minDeg;
    while ($deg >= $maxDeg)
    {
        $deg -= $range;
    }
    while ($deg < $minDeg)
    {
        $deg += $range;
    }
    return sprintf("%.*f", $nDec, $deg);
}

sub escapeString($)
{
    my $str = shift;
    $str =~ s/&/&amp;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s/'/&apos;/g;
    $str =~ s/"/&quot;/g;
    return $str;
}

open(XML, ">$xmlfile");
print XML (<<EOF);
<?xml version="1.0" encoding="UTF-8"?>
<gpx
 version="1.1"
 creator="Navaid Waypoint Generator - http://navaid.com/GPX/"
 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
 xmlns="http://www.topografix.com/GPX/1/1"
 xmlns:navaid="http://navaid.com/GPX/NAVAID/0/9"
 xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd
 http://navaid.com/GPX/NAVAID/0/9 http://navaid.com/GPX/NAVAID/0/9">
 <metadata>
    <author>
        <name>Paul Tomblin</name>
        <email id="ptomblin" domain="xcski.com"/>
        <link href="http://xcski.com/blogs/pt/"/>
    </author>
    <link href="http://navaid.com/GPX/"/>
</metadata>
EOF
print DEBUG "xml open\n" if ($maxDebug);


sub encode($)
{
    my $string = shift;
    $string =~ s/&/&amp\;/g;
    $string =~ s/"/&quot\;/g;
    $string =~ s/</&lt\;/g;
    $string =~ s/>/&gt\;/g;
    return $string;
}

sub dbSourceCode($)
{
#    my $hashRef = shift;
#	$appstr .= $hashRef->{source_name} .
#		"(" . $hashRef->{source_long_name} .  ")\ndata from " .
#		$hashRef->{credit} .
#		"\nLast Updated\t" . $hashRef->{updated} . "\n\n";
}

sub debugCode($)
{
	my $line = shift;
	if ($maxDebug)
	{
		print DEBUG $line;
	}
}

sub cdata($)
{
    my $string = shift;
    if ($string =~ m/[&<>]/)
    {
        $string = "<![CDATA[".$string."]]>";
    }
    return $string;
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

		my $airport_type = ($record->{category} == 1);
		my $waypoint_type = ($record->{category} == 3);
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
		print XML "<wpt lat=\"", wrapDegrees($record->{latitude},90.0,-90.0,6),
            "\" lon=\"", wrapDegrees($record->{longitude},180.0,-180.0,6), "\">\n";

		if ($airport_type)
		{
			print XML "<ele>", ($record->{elevation} * 0.3048), "</ele>\n";
		}
		else
		{
			if (defined($record->{main_frequency}) &&
				$record->{main_frequency})
			{
				$name .= ", Frequency:" . $record->{main_frequency};
			}
		}
        # Until they fix the schema, can't use this properly.
        if (defined($record->{declination}))
        {
            my $weird_decl = normalizeDegrees($record->{declination});
            print XML "<magvar>$weird_decl</magvar>\n";
        }
		print XML "<name>", $record->{id}, "</name>\n";
		print XML "<cmt>", cdata($name), "</cmt>\n";
		print XML "<type>", $record->{type} , "</type>\n";

        if ($doExtension)
        {
            print XML "<extensions>\n";
            $name = $record->{name};
            if ($name)
            {
                print XML "<navaid:name>", cdata($name), "</navaid:name>\n";
            }
            if ($address)
            {
                print XML "<navaid:address>", cdata($address), "</navaid:address>\n";
            }
            if ($state)
            {
                print XML "<navaid:state>", cdata($state), "</navaid:state>\n";
            }
            if ($country)
            {
                print XML "<navaid:country>", cdata($country), "</navaid:country>\n";
            }
            if ($doTPA && $airport_type && defined($record->{tpa}) &&
                $record->{tpa} ne "")
            {
                print XML "<navaid:tpa>", feetToMetres($record->{tpa}),
                    "</navaid:tpa>\n";
            }
            if ($doExtension && $airport_type && defined($record->{hasfuel}) &&
                $record->{hasfuel})
            {
                print XML "<navaid:hasfuel>true</navaid:hasfuel>\n";
            }
            if ($doNavFreq && !$airport_type &&
                defined($record->{main_frequency}) && $record->{main_frequency})
            {
                print XML "<navaid:frequencies>\n";
                print XML "<navaid:frequency type=\"NAV\" frequency=\"" .
                    $record->{main_frequency} . "\" name=\"NAVAID\"/>\n";
                print XML "</navaid:frequencies>\n";
            }
            if (($doMilFreq || $doCommFreq) && $airport_type &&
                scalar(@{$record->{frequencies}}) > 0)
            {
                print XML "<navaid:frequencies>\n";
                foreach my $rowRef (@{$record->{frequencies}})
                {
                    my $comm_type = $rowRef->{type};
                    my $frequency = $rowRef->{frequency};
                    my $comm_name = encode($rowRef->{name});
                    my ($numFreq, $suffix) = ($frequency =~ m/^([0-9\.]*)([A-Z]*)$/);
                    my $milfreq = ($numFreq ne "" && ($numFreq < 108.0 || $numFreq > 137.0) &&
                                        ($suffix eq "" || $suffix eq "M"));
                    if (($doMilFreq && $milfreq) || ($doCommFreq && !$milfreq))
                    {
                        print XML "<navaid:frequency type=\"$comm_type\" " . 
                            "frequency=\"$frequency\" " .
                            "name=\"$comm_name\"/>\n";
                    }
                }
                print XML "</navaid:frequencies>\n";
            }
            if ($doRunways && $airport_type &&
                scalar(@{$record->{runways}}) > 0)
            {
                print XML "<navaid:runways>\n";
                foreach my $rowRef (@{$record->{runways}})
                {
                    my $runway_designation =
                        escapeString($rowRef->{designation});
                    my $length = feetToMetres($rowRef->{length});
                    my $width = feetToMetres($rowRef->{width});
                    my $surface = escapeString($rowRef->{surface});

                    print XML
                        "<navaid:runway designation=\"$runway_designation\" " . 
                        "length=\"$length\" " .
                        "width=\"$width\" " .
                        "surface=\"$surface\">\n";
                    if (defined($rowRef->{b_lat}) &&
                        defined($rowRef->{b_long}))
                    {
                        print XML
                            "<navaid:beginning lat=\"" .
                             wrapDegrees($rowRef->{b_lat},90.0,-90.6,6) . "\" lon=\"".
                             wrapDegrees($rowRef->{b_long},180.0,-180.0,6) . "\">\n";
                        if (defined($rowRef->{b_heading}))
                        {
                            print XML
                                "<navaid:heading>".
                                normalizeDegrees($rowRef->{b_heading}).
                                "</navaid:heading>\n";
                        }
                        if (defined($rowRef->{b_elev}))
                        {
                            print XML
                                "<navaid:elev>".$rowRef->{b_elev}.
                                "</navaid:elev>\n";
                        }
                        print XML
                            "</navaid:beginning>\n";
                    }
                    if (defined($rowRef->{e_lat}) &&
                        defined($rowRef->{e_long}))
                    {
                        print XML
                            "<navaid:ending lat=\"" .
                             wrapDegrees($rowRef->{e_lat},90.0,-90.6,6) . "\" lon=\"".
                             wrapDegrees($rowRef->{e_long},180.0,-180.0,6) . "\">\n";
                        if (defined($rowRef->{e_heading}))
                        {
                            print XML
                                "<navaid:heading>".
                                normalizeDegrees($rowRef->{e_heading}).
                                "</navaid:heading>\n";
                        }
                        if (defined($rowRef->{e_elev}))
                        {
                            print XML
                                "<navaid:elev>".$rowRef->{e_elev}.
                                "</navaid:elev>\n";
                        }
                        print XML
                            "</navaid:ending>\n";
                    }
                    print XML "</navaid:runway>\n";
                }
                print XML "</navaid:runways>\n";
            }
            if ($doFix && $waypoint_type &&
                scalar(@{$record->{fixinfo}}) > 0)
            {
                print XML "<navaid:fix_defn>\n";
                foreach my $rowRef (@{$record->{fixinfo}})
                {
                    my $navaid = $rowRef->{navaid};
                    my $type = $rowRef->{navaid_type};
                    my $radial = $rowRef->{radial_bearing};
                    my $distance = $rowRef->{distance};

                    print XML "<navaid:fix navaid=\"$navaid\" type=\"$type\"";
                    if (defined($radial))
                    {
                        $radial = wrapDegrees($radial, 360, 0, 0);
                        print XML " radial=\"$radial\"";
                    }
                    if (defined($distance))
                    {
                        print XML " distance=\"$distance\"";
                    }
                    print XML "/>\n";
                }
                print XML "</navaid:fix_defn>\n";
            }
            if (defined($record->{declination}))
            {
                print XML "<navaid:magvar>",$record->{declination},"</navaid:magvar>\n";
            }
            print XML "</extensions>\n";
        }

		print DEBUG "adding id = ", $record->{id}, ", name = $name\n" if ($maxDebug);
		print XML "</wpt>\n";
	}
	else
	{
		print XML "</gpx>\n";
		print LOGFILE "\n$pgm FINISHED ", $record->{rownum};
	}
    return 1;
}

CreateDB::generate(\%param, \&wayPointCode, \&dbSourceCode, \&debugCode);


#print LOGFILE "\nFINISHED $rownum";

close(LOGFILE);
close(XML);

