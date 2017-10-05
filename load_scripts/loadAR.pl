#!/usr/bin/perl -w

use IO::File;

use strict;

#$| = 1; # for debugging

use WaypointTypes;
use Datasources;
use CoPilot::Waypoint;

use DBLoad;
DBLoad::initialize();

deleteWaypointData(Datasources::DATASOURCE_AR_OO);
deleteCommFreqData(Datasources::DATASOURCE_AR_OO);
deleteRunwayData(Datasources::DATASOURCE_AR_OO);

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
        # Eventually I should probably parse out the notes, since they
        # have the runway designation and length (in thousand metres) and
        # surface type (in some one-character abbreviation) and TWR
        # frequency.
        my $name = $record->{name};

        my $elev = $record->{elev};
        my $decl = getMagVar($record->{lat}, $record->{long}, $elev);

        my $datasource_key = "AR_OO_AIRPORT_".$id;

        insertWaypoint($id, $datasource_key, "AIRPORT", $name, "",
                        "", "AR", $record->{lat}, $record->{long},
                        $decl, $elev, undef,
                        Datasources::DATASOURCE_AR_OO, 1, 0);

    }
}

updateDatasourceExtents(Datasources::DATASOURCE_AR_OO);

print "Done loading\n";

post_load();

finish();

print "Done\n";

undef $fn;
