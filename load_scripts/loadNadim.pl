#!/usr/bin/perl -w

use IO::File;

use strict;

#$| = 1; # for debugging

use WaypointTypes;
use Datasources;
use CoPilot::Waypoint;

use DBLoad;
DBLoad::initialize();

my %typeCodes = (
    "FIX (NR)"      =>  "REP-PT",
    "GLIDER"        =>  "GLIDERPORT",
    "INTERSECTION"  =>  "AWY-INTXN",
    "MICROLIGHT"    =>  "ULTRALIGHT",
    "VRP"           =>  "VFR-WP");

my %icaoCountryCodes = (
    "EB" => "BE",
    "EG" => "UK",
    "EH" => "NL",
    "EI" => "EI",
    "EN" => "NO",
    "LF" => "FR");

my @records;

deleteWaypointData(Datasources::DATASOURCE_UK_NJ);
deleteCommFreqData(Datasources::DATASOURCE_UK_NJ);
deleteRunwayData(Datasources::DATASOURCE_UK_NJ);

my $fn;
while ($fn = shift)
{
    print "loading $fn\n";

    my $pdb = new CoPilot::Waypoint;
    $pdb->Load($fn);

    foreach my $record (@{$pdb->{records}})
    {
        my $id = $record->{waypoint_id};
        my $notes = $record->{notes};
        my $type;
        my $frequency;
        my @freqs;
        my @runways;
        open (NOTES, '<', \$notes);
        while (<NOTES>)
        {
            if (/^Type:\s+(.*)$/) { $type = $1; }
            elsif (/^Frequency:\s+(.*)$/) { $frequency = $1; }
            elsif (/^Source:.*$/) {}
            elsif (/^$/) {}
            elsif (/^elev/) {}
            elsif (/^various publications$/) {}
            elsif (/^Airport:/) {}
            elsif (/^Frequencies:/)
            {
                while (<NOTES>)
                {
                    last if (/^$/);
                    next if (/^Type\s+Freq.\s+Name/);
                    my ($type, $freq, $name) = m/(\S+)\s+(\S+\s*K?)\s+(\S.*)/;
                    print "type = $type, freq = $freq, name = $name\n";
                    push @freqs, {
                        "type" => $type,
                        "freq" => $freq,
                        "name" => $name };
                }
            }
            elsif (/^Runways:/)
            {
                while (<NOTES>)
                {
                    last if (/^$/);
                    next if (/^Runway\s+LxW.\s+Surface/);
                    my ($rwy, $length, $width, $surface) =
                            m/(\S+)\s+(\S+)[xX](\S+)\s+(\S.*)/;
                    print "rwy = $rwy, length = $length, width = $width, surface = $surface\n";
                    push @runways, {
                        "rwy" => $rwy,
                        "length" => $length,
                        "width" => $width,
                        "surface" => $surface };
                }
            }
            elsif (/^Headings:/)
            {
                while (<NOTES>)
                {
                    last if (/^$/);
                }
            }
            elsif (/^ILS.*:/)
            {
                while (<NOTES>)
                {
                    last if (/^$/);
                }
            }
            elsif (/^Remarks:/)
            {
                while (<NOTES>)
                {
                    last if (/^$/);
                }
            }
            elsif (/^Type of Airport:/)
            {
                while (<NOTES>)
                {
                    last if (/^$/);
                }
            }
            else { print "-->", $_, "<--\n"; }
        }
        $type = uc $type;
        next if (!defined($type) || $type eq "");
        if (!defined($frequency) || $frequency eq "N/A")
        {
            $frequency = "";
        }

        # Don't bother with "DISUSED"
        next if ($type eq "DISUSED");

        my ($name, $country) = ($record->{name} =~ m/(.*), ([A-Z][A-Z])/);
        if (!defined($country))
        {
            $name = $record->{name};
            $country = "UK";
            my $icao_cc;
            if (($icao_cc) = ($id =~ m/^([LE][A-Z])[A-Z][A-Z]$/))
            {
                $country = $icaoCountryCodes{$icao_cc};
                die "bad country\n" if !defined($country);
            }
            else
            {
                $country = "UK";
                print "unknown country, id = $id, name = $name\n";
            }
        }

        if (defined($typeCodes{$type}))
        {
            $type = $typeCodes{$type};
        }
        my $chart = 0;
        if ($type eq "AWY-INTXN" ||
            $type eq "REP-PT" ||
            $type eq "RNAV-WP")
        {
            $chart = WaypointTypes::WPTYPE_VFR |
                WaypointTypes::WPTYPE_LOW_ENROUTE;
        }
        elsif ($type eq "VFR-WP")
        {
            $chart = WaypointTypes::WPTYPE_VFR;
        }

        #print "waypoint_id = $id\n";
        #print "name = $name\n";
        #print "country = $country\n";
        #print "frequency = $frequency\n";
        #print "type = [$type]\n";
        #print "[", $notes, "]\n";

        my $datasource_key = generateDSKey($id, "UK_NJ", $type, "",
            $country, $record->{lat}, $record->{long});

        insertWaypoint($id, $datasource_key, $type, $name, "",
                        "", $country, $record->{lat}, $record->{long},
                        $record->{decl}, $record->{elev},
                        $frequency, Datasources::DATASOURCE_UK_NJ, 1,
                        $chart, undef);

        foreach my $rwyRef (@runways)
        {
            insertRunway($datasource_key,
                $rwyRef->{rwy},
                $rwyRef->{length},
                $rwyRef->{width},
                $rwyRef->{surface},
                1,
                undef, undef, undef, undef,
                undef, undef, undef, undef,
                Datasources::DATASOURCE_UK_NJ, undef);
        }

        foreach my $commRef (@freqs)
        {
            insertCommunication($datasource_key,
                $commRef->{type},
                $commRef->{name},
                $commRef->{freq},
                Datasources::DATASOURCE_UK_NJ, undef);
        }
    }
}

updateDatasourceExtents(Datasources::DATASOURCE_UK_NJ);

print "Done loading\n";

post_load();

finish();

print "Done\n";

undef $fn;
