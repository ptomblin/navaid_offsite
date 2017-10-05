#!/usr/bin/perl -w
#
#	This file creates a consolidated database.
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
use Datasources;
use DBI;
use DBLoad;

my $epsilon = 0.5;

my $conn;
$conn = DBI->connect(
        "DBI:mysql:database=navaid;",
        "navaid2", "2nafish2") or die $conn->errstr;

my $commFreqStmt = $conn->prepare(
        "SELECT     comm_type, frequency, comm_name " .
        "FROM       comm_freqs " .
        "WHERE      datasource_key = ? " .
        "ORDER BY   (frequency+0.0), comm_type");

my $runwaysStmt = $conn->prepare(
        "SELECT     runway_designation, length, width, surface, " .
                   "b_lat, b_long, b_heading, b_elev, " .
				   "e_lat, e_long, e_heading, e_elev, closed  " .
        "FROM       runways " .
        "WHERE      datasource_key = ? " .
        "ORDER BY   runway_designation");

my $fixStmt = $conn->prepare(
        "SELECT     id, datasource, navaid, navaid_type, " .
        "           radial_bearing, distance " .
        "FROM       fix " .
        "WHERE      datasource_key = ?");

sub lfindRecord($$$)
{
  my ($idHashRef, $recordRef, $createIfMissing) = @_;
  my $country = $recordRef->{country};
  if (($country eq "US" || $country eq "CA") && exists($recordRef->{state}) && $recordRef->{state} ne "")
  {
	$country .= "/" . $recordRef->{state};
  }
  if (!exists($idHashRef->{$country}))
  {
	$idHashRef->{$country} = [];
  }
  my $arrayRef = $idHashRef->{$country};

  my $recType = $recordRef->{type};
  my $recCat = $recordRef->{category};
  my $recLat = $recordRef->{latitude};
  my $recLong = $recordRef->{longitude};

  foreach my $recRef (@{$arrayRef})
  {
	next if ($recRef->{category} != $recCat);
	next if ($recCat != 3 && $recRef->{type} ne $recType);
	# This is a pretty quick and dirty distance - if necessary, we could
	# replace this with great circle distance calcs.
	my $dist = sqrt(($recLat - $recRef->{latitude})**2 +
		  ($recLong - $recRef->{longitude})**2);
	next if ($dist > $epsilon);
	return $recRef;
  }
  if ($createIfMissing)
  {
	push @{$arrayRef}, $recordRef;
	return $recordRef;
  }
  return undef;
}

sub copyAttribute($$$)
{
  my ($fromRec, $toRec, $attribute) = @_;
  if ((!exists($toRec->{$attribute}) || !defined($toRec->{$attribute}) ||
	$toRec->{$attribute} eq "" || $toRec->{$attribute} eq "0" ||
	(ref($toRec->{$attribute}) eq "ARRAY" &&
	scalar(@{$toRec->{$attribute}}) == 0)) &&
	   (exists($fromRec->{$attribute}) && defined($fromRec->{$attribute}) &&
	   $fromRec->{$attribute} ne "" && $fromRec->{$attribute} ne "0"))
  {
	$toRec->{$attribute} = $fromRec->{$attribute};
  }
}

sub findAndReplace($$)
{
  my ($idHashRef, $recordRef) = @_;
  my $existingRef = lfindRecord($idHashRef, $recordRef, 1);
  return if $existingRef == $recordRef;
  # Copy whatever isn't set.
  copyAttribute($recordRef, $existingRef, "name");
  copyAttribute($recordRef, $existingRef, "address");
  copyAttribute($recordRef, $existingRef, "main_frequency");
  copyAttribute($recordRef, $existingRef, "elevation");
  copyAttribute($recordRef, $existingRef, "ispublic");
  if (exists($existingRef->{chart_map}) && defined($existingRef->{chart_map}) &&
	  exists($recordRef->{chart_map}) && defined($recordRef->{chart_map}))
  {
	$existingRef->{chart_map} |= $recordRef->{chart_map};
  }
  else
  {
	copyAttribute($recordRef, $existingRef, "chart_map");
  }
  copyAttribute($recordRef, $existingRef, "tpa");
  copyAttribute($recordRef, $existingRef, "runways");
  copyAttribute($recordRef, $existingRef, "frequencies");
  copyAttribute($recordRef, $existingRef, "fixinfo");
}

sub putRecordOut($$$)
{
  my ($datasource, $dsName, $idHashRef) = @_;

  foreach my $stateCountry (keys %{$idHashRef})
  {
      foreach my $recRef (@{$idHashRef->{$stateCountry}})
      {
        my $id = $recRef->{id};
        my $type = $recRef->{type};
        my $latitude = $recRef->{latitude};
        my $longitude = $recRef->{longitude};
        my $llat = int($latitude*10+900.5);
        my $llon = int($longitude*10+1800.5);
        my $datasource_key = $id."_".$dsName."_".$type."_".$stateCountry."_".
                $llat."_".$llon;
        my $main_freq = $recRef->{main_frequency};
        my $origDatasource = $recRef->{datasource};
        print "id = $id, datasource_key = $datasource_key\n";

        insertWaypoint($id, $datasource_key, $type, $recRef->{name},
          $recRef->{address}, $recRef->{state}, $recRef->{country},
          $latitude, $longitude, $recRef->{declination},
          $recRef->{elevation}, $main_freq, $datasource,
          $recRef->{ispublic}, $recRef->{chart_map}, $origDatasource);
        if (defined($recRef->{tpa}))
        {
          insertTPA($datasource_key, $recRef->{tpa});
        }
        if (defined($recRef->{frequencies}))
        {
          foreach my $freqRef (@{$recRef->{frequencies}})
          {
            my $type = $freqRef->{type};
            my $freq = $freqRef->{frequency};
            if ($type ne "CTAF" || $freq ne $main_freq)
            {
              insertCommunication($datasource_key, $type,
                $freqRef->{name}, $freq, $datasource, $origDatasource);
            }
          }
        }
        if (defined($recRef->{runways}))
        {
          foreach my $rwyRef (@{$recRef->{runways}})
          {
            insertRunway($datasource_key, $rwyRef->{designation},
                $rwyRef->{length}, $rwyRef->{width}, $rwyRef->{surface},
                $rwyRef->{closed},
                $rwyRef->{b_lat}, $rwyRef->{b_long}, $rwyRef->{b_heading},
                $rwyRef->{b_elev},
                $rwyRef->{e_lat}, $rwyRef->{e_long}, $rwyRef->{e_heading},
                $rwyRef->{e_elev},
                $datasource, $origDatasource);
          }
        }
        if (defined($recRef->{fixinfo}))
        {
          foreach my $fixRef (@{$recRef->{fixinfo}})
          {
            insertFix($id, $datasource_key, $datasource,
                $fixRef->{navaid}, $fixRef->{navaid_type},
                $fixRef->{radial_bearing},
                $fixRef->{distance}, $origDatasource);
          }
        }
      }
  }
}


sub getFrequencies($$$)
{
    my ($conn, $datasource_key, $main_frequency) = @_;

    my @freqs = ();

    my $found = 0;

    $commFreqStmt->execute($datasource_key)
	or die $commFreqStmt->errstr;

    while (my @row = $commFreqStmt->fetchrow_array)
    {
        my ($comm_type, $frequency, $comm_name) = @row;

        $found = 1;
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

    my @runways = ();
    while (my @row = $runwaysStmt->fetchrow_array)
    {
        my ($runway_designation, $length, $width, $surface,
            $b_lat, $b_long, $b_heading, $b_elev,
			$e_lat, $e_long, $e_heading, $e_elev,
			$closed) = @row;
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
            "e_elev" => $e_elev,
			"closed" => $closed
        };
    }

    return \@runways;
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

sub combineId($$$)
{
    my ($id, $datasource, $doDelete) = @_;

    print "processing $id\n";

    my %immutable_by_id;
    my %mutable_by_id;

    # Do we know this id already?
    if ($doDelete)
    {
        my $existingWP = $conn->prepare(
                "SELECT     datasource_key " .
                "FROM       waypoint " .
                "WHERE      id = '$id' AND " .
                "           datasource = $datasource")
        or die $conn->errstr;

        $existingWP->execute()
        or die $conn->errstr;

        while (my @row = $existingWP->fetchrow_array)
        {
            my ($datasource_key) = @row;

            print "Deleting existing records for $datasource_key\n";

            my $delRwyStmt = $conn->prepare(
                    "DELETE     " .
                    "FROM       runways " .
                    "WHERE      datasource_key = '$datasource_key'")
            or die $conn->errstr;
            $delRwyStmt->execute()
            or die $conn->errstr;

            my $delCommStmt = $conn->prepare(
                    "DELETE     " .
                    "FROM       comm_freqs " .
                    "WHERE      datasource_key = '$datasource_key'")
            or die $conn->errstr;
            $delCommStmt->execute()
            or die $conn->errstr;
        }

        print "deleting $id\n";
        my $delWpt = $conn->prepare(
                "DELETE " .
                "FROM       waypoint " .
                "WHERE      id = '$id' AND " .
                "           datasource = $datasource")
        or die $conn->errstr;

        $delWpt->execute()
        or die $conn->errstr;
        print "deleted\n";
    }

    my $select_string =
            "SELECT     datasource_key, a.type, name, " .
            "           address, state, country, latitude, longitude, " .
            "           declination, main_frequency, a.datasource, " .
			"			elevation, ispublic, chart_map, tpa, b.category " .
            "FROM       waypoint a, type_categories b, " .
            "           datasource c " .
            "WHERE      a.type = b.type AND " .
            "			a.datasource = c.ds_index AND ".
            "           ds_index > 1 AND ds_index < $datasource AND " .
            "           id = '$id' " .
			"ORDER BY	country, state, c.updated DESC";

    my $bigSelect = $conn->prepare($select_string)
    or die $conn->errstr;

	$bigSelect->execute()
	or die $conn->errstr;

	while (my @row = $bigSelect->fetchrow_array)
	{
		my ($datasource_key, $type, $name, $address, $state, 
			$country, $latitude, $longitude, $declination,
			$main_frequency, $datasource, $elevation, $ispublic,
			$chart_map, $tpa, $category) = @row;

        print "processing $id ($type, " . (defined($state)?$state:"") . ", $country) from datasource $datasource\n";

		my %record;
		$record{id} = $id;
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
		$record{ispublic} = $ispublic;
		$record{chart_map} = $chart_map;
		$record{tpa} = $tpa;
		$record{category} =  $category;
		$record{datasource} =  $datasource;
		if ($category == 1)
		{
		  $record{runways} =
			  getRunways($conn, $datasource_key);
		  $record{frequencies} =
			  getFrequencies($conn, $datasource_key, $main_frequency);
		}
		elsif ($category == 3)
		{
			$record{fixinfo} =
				getFIX($conn, $datasource_key);
		}
        findAndReplace(\%mutable_by_id, \%record);
	}
    putRecordOut(Datasources::DATASOURCE_COMBINED_USER,
        "USER", \%mutable_by_id);
}

sub process()
{
    deleteWaypointData(Datasources::DATASOURCE_COMBINED_USER);
    deleteCommFreqData(Datasources::DATASOURCE_COMBINED_USER);
    deleteRunwayData(Datasources::DATASOURCE_COMBINED_USER);

    # Select all the ids in the database
    my $allIds = $conn->prepare(
            "SELECT     distinct(id) " .
            "FROM       waypoint " .
            "WHERE      datasource > 1 AND datasource < 97")
    or die $conn->errstr;

	$allIds->execute()
	or die $conn->errstr;

	while (my @row = $allIds->fetchrow_array)
	{
        my ($id) = @row;
        combineId($id, Datasources::DATASOURCE_COMBINED_USER, 0);
    }

    updateDatasourceExtents(Datasources::DATASOURCE_COMBINED_USER);
}

DBLoad::initialize();

process();

post_load();
finish();
$conn->disconnect();

