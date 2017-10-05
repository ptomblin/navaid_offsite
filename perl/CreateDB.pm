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

package CreateDB;

@ISA = 'Exporter';
@EXPORT = qw(generate);

use strict;
use DBI;

my $conn;
$conn = DBI->connect(
        "DBI:mysql:database=navaid",
        "ptomblin", "navaid") or die $conn->errstr;
$conn->{"AutoCommit"} = 1;

my $commFreqStmt = $conn->prepare(
        "SELECT     comm_type, frequency, comm_name " .
        "FROM       comm_freqs " .
        "WHERE      datasource_key = ? " .
        "ORDER BY   (frequency+0.0), comm_type");

my $runwaysStmt = $conn->prepare(
        "SELECT     runway_designation, length, width, surface, " .
                   "b_lat, b_long, b_heading, b_elev, " .
                   "e_lat, e_long, e_heading, e_elev " .
        "FROM       runways " .
        "WHERE      datasource_key = ? and (closed is null or not closed) " .
        "ORDER BY   runway_designation");

my $runwaysMaxLenStmt = $conn->prepare(
        "SELECT     max(length) " .
        "FROM       runways " .
        "WHERE      datasource_key = ? and (closed is null or not closed)");

my $fixStmt = $conn->prepare(
        "SELECT     id, datasource, navaid, navaid_type, " .
        "           radial_bearing, distance " .
        "FROM       fix " .
        "WHERE      datasource_key = ?");

sub getFrequencies($$$)
{
    my ($conn, $datasource_key, $main_frequency) = @_;

    my @freqs = ();

    my $found = 0;

    $commFreqStmt->execute($datasource_key)
	or die $commFreqStmt->errstr;

    my ($numMainFreq, $suffix) =
        (defined($main_frequency) && $main_frequency ne "") ?
            ($main_frequency =~ m/^([0-9\.]*)([A-Z]*)$/) :
            (0,"");
    while (my @row = $commFreqStmt->fetchrow_array)
    {
        my ($comm_type, $frequency, $comm_name) = @row;

        my ($numFreq, $suffix) = ($frequency =~ m/^([0-9\.]*)([A-Z]*)$/);
        if (($comm_type eq "CTAF" || $comm_type eq "UNIC") &&
            $numMainFreq == $numFreq)
        {
            $found = 1;
        }
        push @freqs, {
            "type" => $comm_type,
            "frequency" => $frequency,
            "name" => $comm_name
        };
    }

    if ($main_frequency && !$found)
    {
        push @freqs, { 
            "type" => "CTAF",
            "frequency" => $main_frequency,
            "name" => "CTAF"
        };
    }

    return \@freqs;
}

sub getRunways($$)
{
    my ($conn, $datasource_key) = @_;

    $runwaysStmt->execute($datasource_key)
	or die $runwaysStmt->errstr;

    my $maxLen = 0;
    my @runways = ();
    while (my @row = $runwaysStmt->fetchrow_array)
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
            "e_elev" => $e_elev
        };
        if ($length > $maxLen)
        {
            $maxLen = $length;
        }
    }

    return (\@runways, $maxLen);
}

sub getFIX($$)
{
    my ($conn, $datasource_key) = @_;

    $fixStmt->execute($datasource_key)
	or die $fixStmt->errstr;

    my @fixes = ();
    while (my @row = $fixStmt->fetchrow_array)
    {
        my ($id, $datasource, $navaid, $navaid_type,
            $radial_bearing, $distance) = @row;
        push @fixes, {
            "id" => $id,
            "datasource" => $datasource,
            "navaid" => $navaid,
            "navaid_type" => $navaid_type,
            "radial_bearing" => $radial_bearing,
            "distance" => $distance
        };
    }
    return \@fixes;
}

sub getMaxRunwayLen($$)
{
    my ($conn, $datasource_key) = @_;

    $runwaysMaxLenStmt->execute($datasource_key)
	or die $runwaysMaxLenStmt->errstr;

    my $myLen = 0;
    while (my @row = $runwaysMaxLenStmt->fetchrow_array)
    {
        $myLen = shift(@row);
    }
    return $myLen;
}

sub generate($$$$)
{
    my ($paramRef, $waypointCodeRef, $datasourceHashCodeRef,
        $debugCodeRef) = @_;

    my $longCountry = defined($paramRef->{longCountry}) &&
        $paramRef->{longCountry};

    my $doRunways = 1;
    if (defined($paramRef->{doRunways}))
    {
        $doRunways = $paramRef->{doRunways};
    }
    my $doComm = 1;
    if (defined($paramRef->{doComm}))
    {
        $doComm = $paramRef->{doComm};
    }
    my $doFix = 0;
    if (defined($paramRef->{doFix}))
    {
        $doFix = $paramRef->{doFix};
    }
    my $minRunway = 0;
    my $doMinRunway = 0;
    if (defined($paramRef->{minRunwayLength}))
    {
        $minRunway = $paramRef->{minRunwayLength};
        $doMinRunway = 1;
    }

    my $result;

    # Get the list of data sources
    $result = $conn->prepare(
            "SELECT     ds_index, source_name, source_long_name, source_url, " .
            "			credit, available_types, updated " .
            "FROM       datasource " .
            "WHERE		ds_index = 99")
    or die $conn->errstr;

    $result->execute()
    or die $conn->errstr;

    my %datasource_hash;
    my @row;
    while (@row = $result->fetchrow_array)
    {
      my $index = $row[0];
      $datasource_hash{$index} =
         {"index" => $index,
          "source_name" => $row[1],
          "source_long_name" => $row[2],
          "source_url" => $row[3],
          "credit" => $row[4],
          "available_types" => $row[5],
          "updated" => $row[6]};
    }

    # Get the list of country codes
    my %country_codes;
    if ($longCountry)
    {
        $result = $conn->prepare(
             "SELECT    code, country_name " .
             "FROM      dafif_country_codes")
        or die $conn->errstr;

        $result->execute()
        or die $conn->errstr;

        while (my @row = $result->fetchrow_array)
        {
            $country_codes{$row[0]} = $row[1];
        }
    }

    my $min_lat = $paramRef->{"min_lat"};
    my $max_lat = $paramRef->{"max_lat"};
    my $min_long = $paramRef->{"min_long"};
    my $max_long = $paramRef->{"max_long"};
    my $select_string =
            "SELECT     a.id, c.pdb_id, datasource_key, a.type, name, " .
            "           address, state, country, latitude, longitude, " .
            "           declination, main_frequency, elevation, " .
            "           b.category, chart_map, tpa, ispublic " .
            "FROM       waypoint a, type_categories b, " .
            "           id_mapping c " .
            "WHERE      a.type = b.type AND " .
            "			a.id = c.id AND ";
    if (defined($min_lat) && defined($max_long))
    {
        $select_string .=
            "			latitude >= $min_lat AND latitude <= $max_lat AND " .
            "           longitude >= $min_long AND longitude <= $max_long AND ";
    }

    my $additional_string = "(";

    if (defined($paramRef->{"countries"}))
    {
        my @countries = @{$paramRef->{"countries"}};
        for (@countries) { s/'/''/g }
        $additional_string .= "country IN ('" .
                join("','", @countries) . "') ";
    }
    if (defined($paramRef->{"states"}))
    {
        my @states = @{$paramRef->{"states"}};
        for (@states) { s/^No State$// }
        if (length($additional_string) > 1)
        {
            $additional_string .= " OR ";
        }
        $additional_string .= "(state IN ('" .
                join("','", @states) .
                "') AND country = 'US') ";
    }
    if (defined($paramRef->{"provinces"}))
    {
        my @provinces = @{$paramRef->{"provinces"}};
        for (@provinces) { s/^No Province$// }
        if (length($additional_string) > 1)
        {
            $additional_string .= " OR ";
        }
        $additional_string .= "(state IN ('" .
                join("','", @provinces) .
                "') AND country = 'CA') ";
    }

    if (length($additional_string) > 1)
    {
        $select_string .= $additional_string . ") AND ";
    }

    if (defined($paramRef->{"privacy"}))
    {
        my $privacy = $paramRef->{"privacy"};
        if ($privacy == 0)
        {
            $select_string .= "ispublic = 1 AND ";
        }
        elsif ($privacy == 1)
        {
            $select_string .= "ispublic = 0 AND ";
        }
    }
    else
    {
        if (!defined($paramRef->{"private"}) || !$paramRef->{"private"})
        {
            $select_string .= "ispublic = 1 AND ";
        }
    }

    if (defined($paramRef->{"types"}) || defined($paramRef->{"charts"}))
    {
        my $typestr = "";
        my $chartstr = "";
        if (defined($paramRef->{"types"}))
        {
            my @types = @{$paramRef->{"types"}};
            $typestr = "a.type IN ('" .  join("','", @types) . "') ";
        }
        if (defined($paramRef->{"charts"}))
        {
            my $cm = $paramRef->{"charts"};
            $chartstr = "(category = 3 AND (chart_map & $cm) != 0) ";
        }
        if (defined($paramRef->{"types"}) && defined($paramRef->{"charts"}))
        {
            $select_string .= "($typestr OR $chartstr) AND ";
        }
        else
        {
            $select_string .= $typestr . $chartstr . "AND ";
        }
    }

    $select_string .= "datasource = 99 ";
    &$debugCodeRef("select string = $select_string\n");

    my $bigSelect = $conn->prepare($select_string)
    or die $conn->errstr;

    my %ids;

    my $rownum = 0;

    &$datasourceHashCodeRef($datasource_hash{99});

    $bigSelect->execute()
    or die $conn->errstr;

    while (@row = $bigSelect->fetchrow_array)
    {
        my ($id, $pdb_id, $datasource_key, $type, $name, $address, $state, 
            $country, $latitude, $longitude, $declination,
            $main_frequency, $elevation, $category, $chart_map,
            $tpa, $ispublic) = @row;

        if (exists $ids{$id})
        {
            &$debugCodeRef("Skipping duplicate ID $id\n");
            next;
        }
        $ids{$id} = $id;

        my %record;
        $record{id} = $id;
        $record{pdb_id} = $pdb_id;
        $record{datasource_key} = $datasource_key;
        $record{type} = $type;
        $record{name} = $name;
        $record{address} = $address;
        $record{state} = $state;
        $record{country} = $country;
        $record{latitude} = $latitude;
        $record{longitude} = $longitude;
        $record{declination} = $declination;
        $record{main_frequency} = $main_frequency;
        $record{elevation} = $elevation;
        $record{category} =  $category;
        $record{chart_map} = $chart_map;
        $record{tpa} = $tpa;
        $record{private} = ($ispublic ? "N" : "Y");
        if ($country)
        {
            if ($longCountry && exists($country_codes{$country}))
            {
                $record{longCountry} = $country_codes{$country};
            }
        }
        if ($category == 1)
        {
            if ($doRunways)
            {
                my $myMax;
                ($record{runways}, $myMax) =
                    getRunways($conn, $datasource_key);
                if ($doMinRunway)
                {
                    next if ($minRunway > $myMax);
                }
            }
            elsif ($doMinRunway)
            {
                my $myMax = getMaxRunwayLen($conn, $datasource_key);
                next if ($minRunway > $myMax);
            }
            if ($doComm)
            {
                $record{frequencies} =
                    getFrequencies($conn, $datasource_key, $main_frequency);
            }
        }
        elsif ($category == 3)
        {
            if ($doFix)
            {
                $record{fixinfo} =
                    getFIX($conn, $datasource_key);
            }
        }
        $record{rownum} = $rownum++;
        $record{datasource} = $datasource_hash{99}->{source_name};

        &$waypointCodeRef(\%record);
    }
    # Send a record with nothing but a rownum to indicate the end.
    &$waypointCodeRef({"rownum" => $rownum});
    #$conn->commit;
    $conn->disconnect;
}

1;
__END__
