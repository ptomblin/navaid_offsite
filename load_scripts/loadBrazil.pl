#!/usr/bin/perl -w

use IO::File;

use strict;

#$| = 1; # for debugging

use WaypointTypes;
use Datasources;

use DBLoad;
DBLoad::initialize();

my $apt_fn = shift;

my $apt_fh = new IO::File($apt_fn) or die "Airport file $apt_fn not found";

deleteWaypointData(Datasources::DATASOURCE_BR_FB);
deleteCommFreqData(Datasources::DATASOURCE_BR_FB);
deleteRunwayData(Datasources::DATASOURCE_BR_FB);

my $datasource_key;
my $rep_pt_id;

<$apt_fh>;
print "starting\n";

while (<$apt_fh>)
{
	chomp;

	my @record = split("\t", $_);
    my ($id, $lat, $long, $city_state_name, 
        $elev, $decl, $rwy, $rwylen, $pad1, $x, $rwywid, $rwysurf,
        $pad2, $pad3,
        $name, $city_state) = @record;
    $elev = $elev / 0.3048;
    $long = -$long;
    # decl isn't in the file.
    $decl = getMagVar($lat, $long, $elev);
    $id =~ s/\?//g;

    $datasource_key = "BR_FB_APT_".$id;
    insertWaypoint($id, $datasource_key, "AIRPORT", $name, $city_state,
                    undef, "BR", $lat, $long, $decl, $elev,
                    undef, Datasources::DATASOURCE_BR_FB, 1, 0, 0);
}


updateDatasourceExtents(Datasources::DATASOURCE_BR_FB);

print "Done loading\n";

post_load();

finish();
print "Done\n";

undef $apt_fh;
